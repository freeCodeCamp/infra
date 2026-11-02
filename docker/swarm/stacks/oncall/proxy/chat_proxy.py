#!/usr/bin/env python3
"""Durably queue, digest, and deliver DevOps alert events."""

from __future__ import annotations

import contextlib
import hashlib
import json
import logging
import os
import random
import re
import shutil
import signal
import sqlite3
import threading
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen

LOG = logging.getLogger("chat-proxy")
UTC = timezone.utc
SCHEMA_VERSION = 1
STATUS_BY_ICON = {"✅": "ok", "⚠️": "warning", "🔴": "failed"}
ICON_BY_STATE = {"ok": "✅", "warning": "⚠️", "failed": "🔴", "firing": "🔴", "resolved": "✅", "no_data": "⚠️", "error": "🔴", "unknown": "⚠️", "test": "⚠️"}
SEVERITY_BY_STATE = {"ok": "info", "warning": "warning", "failed": "critical", "firing": "critical", "resolved": "info", "no_data": "warning", "error": "critical", "unknown": "unknown", "test": "warning"}
CHAT_LINK = re.compile(r"<([^>|]+)\|([^>]+)>")
LINK_SUFFIX = re.compile(r"\s*·\s*<([^>|]+)\|([^>]+)>\s*$")
RETRY_OFFSETS = (0, 30, 120, 600, 1800, 7200, 21600, 43200, 86400)
REMINDER_OFFSETS = (("1h", 3600), ("6h", 21600), ("24h", 86400))
EVENT_LIMITS = {"subject_key": 200, "subject_label": 300, "summary": 500, "details": 8192, "link": 2048}


class QueueCapacityError(RuntimeError):
    pass


class StorageCapacityError(RuntimeError):
    pass


def utc_now():
    return datetime.now(UTC)


def isoformat(value):
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)


def to_milliseconds(value):
    return int(value.astimezone(UTC).timestamp() * 1000)


def from_milliseconds(value):
    return datetime.fromtimestamp(value / 1000, UTC)


def sanitize_link(value):
    if not value:
        return None
    parts = urlsplit(value)
    if parts.scheme != "https" or not parts.netloc or parts.username or parts.password:
        return None
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def sanitize_chat_links(text):
    def replace(match):
        link = sanitize_link(match.group(1))
        return f"<{link}|{match.group(2)}>" if link else match.group(2)

    return CHAT_LINK.sub(replace, text)


def parse_message(text):
    icon = next((candidate for candidate in STATUS_BY_ICON if text.startswith(candidate)), None)
    state = STATUS_BY_ICON.get(icon, "unknown")
    lines = text.splitlines()
    first_line = lines[0] if lines else ""
    content = first_line[len(icon) :].strip() if icon else first_line.strip()
    parts = content.split(" · ", 2)
    source = parts[0].strip("* ") if parts else "unknown"
    subject = parts[1].strip() if len(parts) > 1 else "unknown"
    summary = parts[2].strip() if len(parts) > 2 else first_line.strip()
    link_match = LINK_SUFFIX.search(summary)
    link = sanitize_link(link_match.group(1)) if link_match else None
    link_label = link_match.group(2).strip() if link_match else None
    summary = LINK_SUFFIX.sub("", summary)
    return {
        "status": "warn" if state == "warning" else "fail" if state == "failed" else state,
        "state": state,
        "severity": SEVERITY_BY_STATE[state],
        "source": source or "unknown",
        "subject": subject or "unknown",
        "summary": summary or "(empty)",
        "details": "\n".join(lines[1:]) or None,
        "link": link,
        "link_label": link_label,
    }


def render_event(event):
    if event["source"]["adapter"] == "legacy-text/v1" and event["state"] == "unknown":
        return event["legacy_text"]
    icon = ICON_BY_STATE[event["state"]]
    text = (
        f"{icon} *{event['source']['instance']}* · {event['subject']['label']} · "
        f"{event['summary']}"
    )
    if event.get("link"):
        text += f" · <{event['link']}|{event.get('link_label') or 'link'}>"
    if event.get("details"):
        text += f"\n{event['details']}"
    return text


def field_matches(expression, value, minimum, maximum, sunday=False):
    for part in expression.split(","):
        base, separator, step_text = part.partition("/")
        step = int(step_text) if separator else 1
        if step < 1:
            return False
        if base == "*":
            start, end = minimum, maximum
        elif "-" in base:
            start_text, end_text = base.split("-", 1)
            start, end = int(start_text), int(end_text)
        else:
            start = int(base)
            end = maximum if separator else start
        candidate = 0 if sunday and value == 7 else value
        normalized_start = 0 if sunday and start == 7 else start
        normalized_end = 0 if sunday and end == 7 and start == end else end
        if normalized_start <= candidate <= normalized_end and (candidate - normalized_start) % step == 0:
            return True
    return False


def schedule_matches(schedule, moment):
    fields = schedule.split()
    if len(fields) != 6:
        raise ValueError(f"expected six cron fields, got {schedule!r}")
    second, minute, hour, day, month, weekday = fields
    cron_weekday = (moment.weekday() + 1) % 7
    return all(
        (
            field_matches(second, moment.second, 0, 59),
            field_matches(minute, moment.minute, 0, 59),
            field_matches(hour, moment.hour, 0, 23),
            field_matches(day, moment.day, 1, 31),
            field_matches(month, moment.month, 1, 12),
            field_matches(weekday, cron_weekday, 0, 7, sunday=True),
        )
    )


def occurrences_between(schedule, start, end):
    if end <= start:
        return []
    fields = schedule.split()
    if len(fields) != 6 or fields[0] != "0":
        raise ValueError(f"supported schedules require six fields with second 0, got {schedule!r}")
    cursor = start.astimezone(UTC).replace(second=0, microsecond=0) + timedelta(minutes=1)
    limit = end.astimezone(UTC)
    matches = []
    while cursor <= limit:
        if schedule_matches(schedule, cursor):
            matches.append(cursor)
        cursor += timedelta(minutes=1)
    return matches


def read_secret(name, default=""):
    file_value = os.environ.get(f"{name}_FILE")
    if file_value:
        return Path(file_value).read_text(encoding="utf-8").strip()
    return os.environ.get(name, default)


def _fsync_directory(path):
    directory_fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _validate_sqlite(connection, *, full=False):
    version = connection.execute("PRAGMA user_version").fetchone()[0]
    if version != SCHEMA_VERSION:
        raise RuntimeError(
            f"database schema {version} does not match supported schema {SCHEMA_VERSION}"
        )
    migration = connection.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0]
    if migration != version:
        raise RuntimeError("database migration history does not match its schema")
    pragma = "integrity_check" if full else "quick_check"
    result = connection.execute(f"PRAGMA {pragma}").fetchone()[0]
    if result != "ok":
        raise RuntimeError(f"database integrity check failed: {result}")
    if connection.execute("PRAGMA foreign_key_check").fetchone():
        raise RuntimeError("database foreign-key integrity check failed")


def _atomic_sqlite_copy(source, destination):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
    target = sqlite3.connect(temporary)
    os.chmod(temporary, 0o600)
    try:
        source.backup(target)
        _validate_sqlite(target, full=True)
        target.close()
        with temporary.open("rb") as copied_file:
            os.fsync(copied_file.fileno())
        os.replace(temporary, destination)
        _fsync_directory(destination.parent)
    finally:
        with contextlib.suppress(sqlite3.Error):
            target.close()
        temporary.unlink(missing_ok=True)


def backup_database(source_path, destination_path):
    source = sqlite3.connect(source_path, timeout=5)
    try:
        source.execute("PRAGMA busy_timeout = 5000")
        _atomic_sqlite_copy(source, destination_path)
    finally:
        source.close()


def restore_database(source_path, destination_path):
    source_path = Path(source_path)
    destination_path = Path(destination_path)
    if not source_path.is_file():
        raise FileNotFoundError(source_path)
    if source_path.resolve() == destination_path.resolve():
        raise ValueError("restore source and destination must differ")
    source = sqlite3.connect(source_path)
    try:
        _validate_sqlite(source, full=True)
        _atomic_sqlite_copy(source, destination_path)
    finally:
        source.close()
    for suffix in ("-wal", "-shm"):
        Path(f"{destination_path}{suffix}").unlink(missing_ok=True)
    _fsync_directory(destination_path.parent)


class ChatProxy:
    def __init__(
        self,
        webhook,
        data_dir,
        expectations_path,
        *,
        grace_minutes=15,
        retention_days=30,
        max_digest_chars=3500,
        now=utc_now,
        sender=None,
        jitter=None,
        max_queue_depth=10000,
        min_free_bytes=64 * 1024 * 1024,
    ):
        self.webhook = webhook
        self.data_dir = Path(data_dir)
        self.expectations_path = Path(expectations_path)
        self.database_path = self.data_dir / "chat-proxy.sqlite3"
        self.grace = timedelta(minutes=grace_minutes)
        self.retention_days = retention_days
        self.max_digest_chars = max_digest_chars
        self.now = now
        self.sender = sender or self._send_to_chat
        self.jitter = jitter or (lambda: random.uniform(0.8, 1.2))
        self.max_queue_depth = max_queue_depth
        self.min_free_bytes = min_free_bytes
        self.lock = threading.RLock()
        self.stopping = threading.Event()
        self.delivery_wake = threading.Event()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self._reject_legacy_state()
        self.expectations = self._load_expectations()
        self._initialize_database()
        self._sync_expectations()
        self.last_scheduler_run = self.now().astimezone(UTC)

    def _reject_legacy_state(self):
        legacy = [self.data_dir / "state.json", *self.data_dir.glob("success-*.jsonl")]
        if any(path.exists() and path.stat().st_size for path in legacy):
            raise RuntimeError("legacy proxy state exists; no automatic JSONL migration is supported")

    def _load_expectations(self):
        with self.expectations_path.open(encoding="utf-8") as source:
            expectations = json.load(source)
        for expectation in expectations:
            schedule = expectation["schedule"]
            if len(schedule.split()) != 6 or schedule.split()[0] != "0":
                raise ValueError(f"unsupported schedule for {expectation['id']}: {schedule}")
        return expectations

    def _connect(self):
        connection = sqlite3.connect(self.database_path, timeout=5, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 5000")
        connection.execute("PRAGMA synchronous = FULL")
        return connection

    @contextlib.contextmanager
    def _transaction(self):
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            yield connection
            connection.execute("COMMIT")
        except Exception:
            with contextlib.suppress(sqlite3.Error):
                connection.execute("ROLLBACK")
            raise
        finally:
            connection.close()

    def _initialize_database(self):
        connection = self._connect()
        try:
            os.chmod(self.database_path, 0o600)
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version > SCHEMA_VERSION:
                raise RuntimeError(f"database schema {version} is newer than supported {SCHEMA_VERSION}")
            connection.execute("PRAGMA journal_mode = WAL")
            if version == 0:
                connection.executescript(
                    """
                    BEGIN EXCLUSIVE;
                    CREATE TABLE schema_migrations (
                      version INTEGER PRIMARY KEY,
                      applied_at_ms INTEGER NOT NULL
                    );
                    INSERT INTO schema_migrations VALUES (1, CAST(strftime('%s','now') AS INTEGER) * 1000);
                    CREATE TABLE events (
                      event_id TEXT PRIMARY KEY,
                      schema_name TEXT NOT NULL,
                      source_id TEXT NOT NULL,
                      source_instance TEXT NOT NULL,
                      adapter TEXT NOT NULL,
                      provider_event_id TEXT,
                      provider_delivery_id TEXT,
                      provider_incident_key TEXT,
                      kind TEXT NOT NULL,
                      state TEXT NOT NULL,
                      severity TEXT NOT NULL,
                      subject_key TEXT NOT NULL,
                      subject_label TEXT NOT NULL,
                      summary TEXT NOT NULL,
                      details TEXT,
                      link TEXT,
                      observed_at_ms INTEGER,
                      received_at_ms INTEGER NOT NULL,
                      received_day TEXT NOT NULL,
                      heartbeat_expectation_id TEXT,
                      heartbeat_scheduled_for_ms INTEGER,
                      routing_action TEXT NOT NULL CHECK (routing_action IN ('immediate','digest','suppressed')),
                      routing_policy_version INTEGER NOT NULL,
                      routing_reason TEXT NOT NULL,
                      canonical_json TEXT NOT NULL,
                      created_at_ms INTEGER NOT NULL
                    );
                    CREATE INDEX events_digest_day ON events(received_day, received_at_ms) WHERE routing_action='digest';
                    CREATE TABLE dedupe_claims (
                      scope TEXT NOT NULL,
                      dedupe_key TEXT NOT NULL,
                      event_id TEXT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
                      claimed_at_ms INTEGER NOT NULL,
                      expires_at_ms INTEGER NOT NULL,
                      PRIMARY KEY(scope, dedupe_key)
                    );
                    CREATE INDEX dedupe_claims_expiry ON dedupe_claims(expires_at_ms);
                    CREATE TABLE digests (
                      digest_id TEXT PRIMARY KEY,
                      digest_day TEXT NOT NULL UNIQUE,
                      state TEXT NOT NULL CHECK (state IN ('queued','delivered','dead_letter')),
                      payload_text TEXT NOT NULL,
                      event_count INTEGER NOT NULL,
                      created_at_ms INTEGER NOT NULL,
                      delivered_at_ms INTEGER
                    );
                    CREATE TABLE digest_members (
                      digest_id TEXT NOT NULL REFERENCES digests(digest_id) ON DELETE CASCADE,
                      event_id TEXT NOT NULL,
                      ordinal INTEGER NOT NULL,
                      PRIMARY KEY(digest_id,event_id),
                      UNIQUE(digest_id,ordinal)
                    );
                    CREATE TABLE heartbeat_expectations (
                      expectation_id TEXT PRIMARY KEY,
                      label TEXT NOT NULL,
                      service TEXT NOT NULL,
                      schedule TEXT NOT NULL,
                      source TEXT NOT NULL,
                      subject TEXT NOT NULL,
                      config_hash TEXT NOT NULL,
                      updated_at_ms INTEGER NOT NULL
                    );
                    CREATE TABLE heartbeat_cursors (
                      expectation_id TEXT PRIMARY KEY REFERENCES heartbeat_expectations(expectation_id),
                      last_evaluated_for_ms INTEGER NOT NULL
                    );
                    CREATE TABLE heartbeat_episodes (
                      episode_id TEXT PRIMARY KEY,
                      expectation_id TEXT NOT NULL REFERENCES heartbeat_expectations(expectation_id),
                      state TEXT NOT NULL CHECK (state IN ('open','recovered')),
                      first_missed_for_ms INTEGER NOT NULL,
                      first_deadline_ms INTEGER NOT NULL,
                      last_missed_for_ms INTEGER NOT NULL,
                      missed_count INTEGER NOT NULL,
                      opened_at_ms INTEGER NOT NULL,
                      recovered_at_ms INTEGER,
                      recovery_state TEXT
                    );
                    CREATE UNIQUE INDEX one_open_episode ON heartbeat_episodes(expectation_id) WHERE state='open';
                    CREATE TABLE heartbeat_occurrences (
                      expectation_id TEXT NOT NULL REFERENCES heartbeat_expectations(expectation_id),
                      scheduled_for_ms INTEGER NOT NULL,
                      deadline_ms INTEGER NOT NULL,
                      state TEXT NOT NULL CHECK (state IN ('observed','missed')),
                      observation_event_id TEXT REFERENCES events(event_id) ON DELETE SET NULL,
                      episode_id TEXT REFERENCES heartbeat_episodes(episode_id),
                      evaluated_at_ms INTEGER NOT NULL,
                      PRIMARY KEY(expectation_id,scheduled_for_ms)
                    );
                    CREATE TABLE heartbeat_observations (
                      observation_id INTEGER PRIMARY KEY,
                      expectation_id TEXT NOT NULL REFERENCES heartbeat_expectations(expectation_id),
                      event_id TEXT REFERENCES events(event_id) ON DELETE SET NULL,
                      observed_at_ms INTEGER NOT NULL,
                      scheduled_for_ms INTEGER,
                      state TEXT NOT NULL,
                      UNIQUE(expectation_id,event_id)
                    );
                    CREATE TABLE heartbeat_notifications (
                      notification_id TEXT PRIMARY KEY,
                      episode_id TEXT NOT NULL REFERENCES heartbeat_episodes(episode_id),
                      stage TEXT NOT NULL CHECK (stage IN ('initial','1h','6h','24h','recovery')),
                      due_at_ms INTEGER NOT NULL,
                      state TEXT NOT NULL CHECK (state IN ('queued','delivered','dead_letter','cancelled')),
                      event_id TEXT REFERENCES events(event_id),
                      UNIQUE(episode_id,stage)
                    );
                    CREATE TABLE deliveries (
                      delivery_id TEXT PRIMARY KEY,
                      event_id TEXT REFERENCES events(event_id) ON DELETE CASCADE,
                      digest_id TEXT REFERENCES digests(digest_id) ON DELETE CASCADE,
                      notification_id TEXT REFERENCES heartbeat_notifications(notification_id),
                      purpose TEXT NOT NULL,
                      payload_json TEXT NOT NULL,
                      state TEXT NOT NULL CHECK (state IN ('pending','in_flight','retry_wait','delivered','dead_letter','cancelled')),
                      attempt_count INTEGER NOT NULL DEFAULT 0,
                      first_attempt_at_ms INTEGER,
                      next_attempt_at_ms INTEGER NOT NULL,
                      lease_token TEXT,
                      lease_until_ms INTEGER,
                      last_error_class TEXT,
                      last_http_status INTEGER,
                      delivered_at_ms INTEGER,
                      dead_lettered_at_ms INTEGER,
                      replay_of_delivery_id TEXT REFERENCES deliveries(delivery_id),
                      created_at_ms INTEGER NOT NULL,
                      CHECK ((event_id IS NOT NULL) != (digest_id IS NOT NULL))
                    );
                    CREATE INDEX deliveries_due ON deliveries(state,next_attempt_at_ms);
                    CREATE UNIQUE INDEX one_replay_per_delivery ON deliveries(replay_of_delivery_id) WHERE replay_of_delivery_id IS NOT NULL;
                    CREATE TABLE delivery_attempts (
                      delivery_id TEXT NOT NULL REFERENCES deliveries(delivery_id) ON DELETE CASCADE,
                      attempt_number INTEGER NOT NULL,
                      started_at_ms INTEGER NOT NULL,
                      finished_at_ms INTEGER,
                      outcome TEXT,
                      http_status INTEGER,
                      error_class TEXT,
                      next_attempt_at_ms INTEGER,
                      PRIMARY KEY(delivery_id,attempt_number)
                    );
                    CREATE TABLE dead_letters (
                      delivery_id TEXT PRIMARY KEY REFERENCES deliveries(delivery_id) ON DELETE CASCADE,
                      opened_at_ms INTEGER NOT NULL,
                      reason TEXT NOT NULL,
                      disposition TEXT NOT NULL CHECK (disposition IN ('unresolved','replayed','discarded')),
                      disposed_at_ms INTEGER,
                      disposed_by TEXT,
                      disposition_reason TEXT
                    );
                    CREATE TABLE operator_audit (
                      audit_id TEXT PRIMARY KEY,
                      action TEXT NOT NULL,
                      actor TEXT NOT NULL,
                      target_type TEXT NOT NULL,
                      target_id TEXT NOT NULL,
                      reason TEXT NOT NULL,
                      occurred_at_ms INTEGER NOT NULL
                    );
                    CREATE TABLE runtime_state (
                      key TEXT PRIMARY KEY,
                      value TEXT NOT NULL,
                      updated_at_ms INTEGER NOT NULL
                    );
                    PRAGMA user_version = 1;
                    COMMIT;
                    """
                )
            _validate_sqlite(connection)
        finally:
            connection.close()

    def release_inflight_leases(self, reason="shutdown"):
        current = self.now().astimezone(UTC)
        current_ms = to_milliseconds(current)
        with self._transaction() as connection:
            rows = connection.execute(
                "SELECT delivery_id,attempt_count FROM deliveries WHERE state='in_flight'"
            ).fetchall()
            for row in rows:
                connection.execute(
                    """UPDATE delivery_attempts SET finished_at_ms=?,outcome=?,next_attempt_at_ms=?
                    WHERE delivery_id=? AND attempt_number=? AND finished_at_ms IS NULL""",
                    (
                        current_ms,
                        reason,
                        current_ms,
                        row["delivery_id"],
                        row["attempt_count"],
                    ),
                )
            connection.execute(
                """UPDATE deliveries SET state='retry_wait',next_attempt_at_ms=?,
                lease_token=NULL,lease_until_ms=NULL WHERE state='in_flight'""",
                (current_ms,),
            )
            return len(rows)

    def _sync_expectations(self):
        now_ms = to_milliseconds(self.now())
        with self._transaction() as connection:
            for expectation in self.expectations:
                canonical = json.dumps(expectation, sort_keys=True, separators=(",", ":"))
                connection.execute(
                    """INSERT INTO heartbeat_expectations
                    (expectation_id,label,service,schedule,source,subject,config_hash,updated_at_ms)
                    VALUES (?,?,?,?,?,?,?,?)
                    ON CONFLICT(expectation_id) DO UPDATE SET
                      label=excluded.label,service=excluded.service,schedule=excluded.schedule,
                      source=excluded.source,subject=excluded.subject,
                      config_hash=excluded.config_hash,updated_at_ms=excluded.updated_at_ms""",
                    (
                        expectation["id"], expectation["label"], expectation["service"],
                        expectation["schedule"], expectation["source"], expectation["subject"],
                        hashlib.sha256(canonical.encode()).hexdigest(), now_ms,
                    ),
                )

    def _canonicalize_legacy(self, payload, received_at):
        text = payload.get("text") if isinstance(payload, dict) else None
        if not isinstance(text, str):
            raise ValueError("payload requires a string text field")
        sanitized_text = sanitize_chat_links(text)
        parsed = parse_message(sanitized_text)
        routing_action = "digest" if parsed["state"] == "ok" else "immediate"
        event = {
            "schema": "fcc.alert-event/v1",
            "event_id": str(uuid.uuid4()),
            "source": {"id": "oncall", "instance": parsed["source"], "adapter": "legacy-text/v1"},
            "provider": {"event_id": None, "delivery_id": None, "incident_key": None},
            "kind": "heartbeat" if self._matching_expectations(parsed) else "job",
            "state": parsed["state"],
            "severity": parsed["severity"],
            "subject": {"key": parsed["subject"], "label": parsed["subject"]},
            "summary": parsed["summary"],
            "details": parsed["details"],
            "link": parsed["link"],
            "link_label": parsed["link_label"],
            "observed_at": isoformat(received_at),
            "received_at": isoformat(received_at),
            "heartbeat": {"expectation_id": None, "scheduled_for": None},
            "routing": {
                "action": routing_action,
                "policy_version": 1,
                "reason": "routine-success" if routing_action == "digest" else "actionable-or-unknown",
            },
        }
        if parsed["state"] == "unknown":
            event["legacy_text"] = sanitized_text
        self._validate_event(event)
        fingerprint = hashlib.sha256(
            json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        return event, f"legacy:{fingerprint}"

    def _validate_event(self, event):
        fields = {
            "subject_key": event["subject"]["key"],
            "subject_label": event["subject"]["label"],
            "summary": event["summary"],
            "details": event.get("details") or "",
            "link": event.get("link") or "",
        }
        for name, value in fields.items():
            if not isinstance(value, str) or len(value) > EVENT_LIMITS[name]:
                raise ValueError(f"invalid {name}")
        if event["state"] not in SEVERITY_BY_STATE:
            raise ValueError("invalid event state")
        if event.get("link") and sanitize_link(event["link"]) != event["link"]:
            raise ValueError("invalid event link")

    def _matching_expectations(self, parsed):
        source = parsed.get("source") or parsed.get("source_instance")
        subject = parsed.get("subject") or parsed.get("subject_label")
        return [item for item in self.expectations if item["source"] == source and item["subject"] == subject]

    def _insert_event(self, connection, event, received_at):
        source = event["source"]
        provider = event["provider"]
        subject = event["subject"]
        routing = event["routing"]
        canonical_json = json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        connection.execute(
            """INSERT INTO events
            (event_id,schema_name,source_id,source_instance,adapter,provider_event_id,
             provider_delivery_id,provider_incident_key,kind,state,severity,subject_key,
             subject_label,summary,details,link,observed_at_ms,received_at_ms,received_day,
             heartbeat_expectation_id,heartbeat_scheduled_for_ms,routing_action,
             routing_policy_version,routing_reason,canonical_json,created_at_ms)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                event["event_id"], event["schema"], source["id"], source["instance"], source["adapter"],
                provider["event_id"], provider["delivery_id"], provider["incident_key"], event["kind"],
                event["state"], event["severity"], subject["key"], subject["label"], event["summary"],
                event.get("details"), event.get("link"), to_milliseconds(parse_timestamp(event["observed_at"])),
                to_milliseconds(received_at), received_at.date().isoformat(),
                event["heartbeat"]["expectation_id"], None, routing["action"], routing["policy_version"],
                routing["reason"], canonical_json, to_milliseconds(received_at),
            ),
        )

    def _enqueue_delivery(self, connection, *, event_id=None, digest_id=None, notification_id=None, purpose, payload, due_at, replay_of=None):
        delivery_id = str(uuid.uuid4())
        connection.execute(
            """INSERT INTO deliveries
            (delivery_id,event_id,digest_id,notification_id,purpose,payload_json,state,
             next_attempt_at_ms,replay_of_delivery_id,created_at_ms)
            VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (
                delivery_id, event_id, digest_id, notification_id, purpose,
                json.dumps(payload, ensure_ascii=False, separators=(",", ":")), "pending",
                to_milliseconds(due_at), replay_of, to_milliseconds(due_at),
            ),
        )
        return delivery_id

    def _record_observations(self, connection, event, received_at):
        parsed = {"source": event["source"]["instance"], "subject": event["subject"]["label"]}
        for expectation in self._matching_expectations(parsed):
            connection.execute(
                """INSERT OR IGNORE INTO heartbeat_observations
                (expectation_id,event_id,observed_at_ms,state) VALUES (?,?,?,?)""",
                (expectation["id"], event["event_id"], to_milliseconds(received_at), event["state"]),
            )

    def accept(self, payload, received_at=None):
        received_at = (received_at or self.now()).astimezone(UTC)
        try:
            event, dedupe_key = self._canonicalize_legacy(payload, received_at)
        except ValueError:
            return False, 400
        delivery_id = None
        try:
            if shutil.disk_usage(self.data_dir).free < self.min_free_bytes:
                raise StorageCapacityError("storage free-space floor reached")
            with self.lock, self._transaction() as connection:
                existing = connection.execute(
                    """SELECT event_id,expires_at_ms FROM dedupe_claims
                    WHERE scope='oncall-legacy' AND dedupe_key=?""",
                    (dedupe_key,),
                ).fetchone()
                if existing and existing["expires_at_ms"] > to_milliseconds(received_at):
                    return True, 202
                if existing:
                    connection.execute(
                        "DELETE FROM dedupe_claims WHERE scope='oncall-legacy' AND dedupe_key=?",
                        (dedupe_key,),
                    )
                if event["routing"]["action"] == "digest":
                    frozen = connection.execute(
                        "SELECT 1 FROM digests WHERE digest_day=?", (received_at.date().isoformat(),)
                    ).fetchone()
                    if frozen:
                        event["routing"] = {"action": "immediate", "policy_version": 1, "reason": "late-after-digest"}
                if event["routing"]["action"] == "immediate":
                    queue_depth = connection.execute(
                        """SELECT COUNT(*) FROM deliveries
                        WHERE state IN ('pending','in_flight','retry_wait')"""
                    ).fetchone()[0]
                    if queue_depth >= self.max_queue_depth:
                        raise QueueCapacityError("delivery queue capacity reached")
                self._insert_event(connection, event, received_at)
                connection.execute(
                    "INSERT INTO dedupe_claims VALUES (?,?,?,?,?)",
                    (
                        "oncall-legacy", dedupe_key, event["event_id"], to_milliseconds(received_at),
                        to_milliseconds(received_at + timedelta(minutes=5)),
                    ),
                )
                self._record_observations(connection, event, received_at)
                if event["routing"]["action"] == "immediate":
                    delivery_id = self._enqueue_delivery(
                        connection, event_id=event["event_id"], purpose="immediate",
                        payload={"text": render_event(event)}, due_at=received_at,
                    )
        except QueueCapacityError:
            LOG.error("event rejected because delivery queue capacity was reached")
            return False, 503
        except StorageCapacityError:
            LOG.error("event rejected because storage capacity is below the configured floor")
            return False, 503
        except (OSError, sqlite3.Error):
            LOG.exception("event could not be durably accepted")
            return False, 503
        if delivery_id:
            self.delivery_wake.set()
        return True, 202

    def _send_to_chat(self, payload):
        if not self.webhook:
            LOG.error("Google Chat destination is empty; message remains queued")
            return {"success": False, "error_class": "missing_destination", "transient": True}
        body = json.dumps(payload, ensure_ascii=False).encode()
        request = Request(
            self.webhook,
            data=body,
            headers={"Content-Type": "application/json; charset=UTF-8"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=15) as response:
                if 200 <= response.status < 300:
                    return {"success": True, "http_status": response.status}
                return {"success": False, "http_status": response.status, "transient": response.status in (408, 425, 429) or response.status >= 500, "error_class": "http"}
        except HTTPError as error:
            retry_after = error.headers.get("Retry-After") if error.headers else None
            return {
                "success": False,
                "http_status": error.code,
                "transient": error.code in (408, 425, 429) or error.code >= 500,
                "error_class": "http",
                "retry_after": retry_after,
            }
        except (URLError, TimeoutError, OSError) as error:
            return {"success": False, "transient": True, "error_class": type(error).__name__}

    def _normalize_send_result(self, result):
        if result is True:
            return {"success": True}
        if result is False or result is None:
            return {"success": False, "transient": True, "error_class": "downstream_failure"}
        if isinstance(result, dict) and "success" in result:
            return result
        return {"success": False, "transient": True, "error_class": "invalid_sender_result"}

    def _retry_after_time(self, value, current):
        if not value:
            return None
        try:
            return current + timedelta(seconds=max(0, int(value)))
        except (TypeError, ValueError):
            try:
                return parsedate_to_datetime(value).astimezone(UTC)
            except (TypeError, ValueError, OverflowError):
                return None

    def _claim_delivery(self, current, delivery_id=None):
        current_ms = to_milliseconds(current)
        with self._transaction() as connection:
            parameters = [current_ms, current_ms]
            where = "state IN ('pending','retry_wait') AND next_attempt_at_ms<=? OR (state='in_flight' AND lease_until_ms<=?)"
            if delivery_id:
                where = f"({where}) AND delivery_id=?"
                parameters.append(delivery_id)
            row = connection.execute(
                f"SELECT * FROM deliveries WHERE {where} ORDER BY next_attempt_at_ms LIMIT 1",
                parameters,
            ).fetchone()
            if not row:
                return None
            token = str(uuid.uuid4())
            attempt = row["attempt_count"] + 1
            first_ms = row["first_attempt_at_ms"] or current_ms
            connection.execute(
                """UPDATE deliveries SET state='in_flight',attempt_count=?,first_attempt_at_ms=?,
                lease_token=?,lease_until_ms=? WHERE delivery_id=?""",
                (attempt, first_ms, token, to_milliseconds(current + timedelta(minutes=2)), row["delivery_id"]),
            )
            connection.execute(
                "INSERT INTO delivery_attempts(delivery_id,attempt_number,started_at_ms) VALUES (?,?,?)",
                (row["delivery_id"], attempt, current_ms),
            )
            claimed = dict(row)
            claimed.update({"attempt_count": attempt, "first_attempt_at_ms": first_ms, "lease_token": token})
            return claimed

    def _finish_delivery(self, claim, result, current):
        current_ms = to_milliseconds(current)
        with self._transaction() as connection:
            row = connection.execute(
                "SELECT * FROM deliveries WHERE delivery_id=? AND lease_token=? AND state='in_flight'",
                (claim["delivery_id"], claim["lease_token"]),
            ).fetchone()
            if not row:
                return
            if result["success"]:
                connection.execute(
                    """UPDATE deliveries SET state='delivered',delivered_at_ms=?,lease_token=NULL,
                    lease_until_ms=NULL,last_error_class=NULL,last_http_status=? WHERE delivery_id=?""",
                    (current_ms, result.get("http_status"), claim["delivery_id"]),
                )
                outcome = "delivered"
                next_ms = None
                if row["digest_id"]:
                    connection.execute(
                        "UPDATE digests SET state='delivered',delivered_at_ms=? WHERE digest_id=?",
                        (current_ms, row["digest_id"]),
                    )
                if row["notification_id"]:
                    connection.execute(
                        "UPDATE heartbeat_notifications SET state='delivered' WHERE notification_id=?",
                        (row["notification_id"],),
                    )
            else:
                transient = result.get("transient", True)
                attempt = row["attempt_count"]
                if transient and attempt < len(RETRY_OFFSETS):
                    first = from_milliseconds(row["first_attempt_at_ms"])
                    target = first + timedelta(seconds=RETRY_OFFSETS[attempt] * self.jitter())
                    retry_after = self._retry_after_time(result.get("retry_after"), current)
                    if retry_after and retry_after > target:
                        target = retry_after
                    horizon = first + timedelta(seconds=RETRY_OFFSETS[-1])
                    target = min(target, horizon)
                    target = max(target, current + timedelta(seconds=1))
                    next_ms = to_milliseconds(target)
                    connection.execute(
                        """UPDATE deliveries SET state='retry_wait',next_attempt_at_ms=?,lease_token=NULL,
                        lease_until_ms=NULL,last_error_class=?,last_http_status=? WHERE delivery_id=?""",
                        (next_ms, result.get("error_class"), result.get("http_status"), claim["delivery_id"]),
                    )
                    outcome = "retry"
                else:
                    next_ms = None
                    reason = result.get("error_class") or "retry_exhausted"
                    connection.execute(
                        """UPDATE deliveries SET state='dead_letter',dead_lettered_at_ms=?,lease_token=NULL,
                        lease_until_ms=NULL,last_error_class=?,last_http_status=? WHERE delivery_id=?""",
                        (current_ms, reason, result.get("http_status"), claim["delivery_id"]),
                    )
                    connection.execute(
                        "INSERT OR IGNORE INTO dead_letters VALUES (?,?,?,'unresolved',NULL,NULL,NULL)",
                        (claim["delivery_id"], current_ms, reason),
                    )
                    if row["digest_id"]:
                        connection.execute("UPDATE digests SET state='dead_letter' WHERE digest_id=?", (row["digest_id"],))
                    if row["notification_id"]:
                        connection.execute("UPDATE heartbeat_notifications SET state='dead_letter' WHERE notification_id=?", (row["notification_id"],))
                    outcome = "dead_letter"
            connection.execute(
                """UPDATE delivery_attempts SET finished_at_ms=?,outcome=?,http_status=?,error_class=?,
                next_attempt_at_ms=? WHERE delivery_id=? AND attempt_number=?""",
                (
                    current_ms, outcome, result.get("http_status"), result.get("error_class"), next_ms,
                    claim["delivery_id"], row["attempt_count"],
                ),
            )

    def process_deliveries(self, current=None, *, delivery_id=None, limit=50):
        current = (current or self.now()).astimezone(UTC)
        processed = 0
        while processed < limit and not self.stopping.is_set():
            try:
                claim = self._claim_delivery(current, delivery_id=delivery_id)
            except (OSError, sqlite3.Error):
                LOG.exception("delivery could not be claimed; queued work remains durable")
                break
            if not claim:
                break
            try:
                result = self._normalize_send_result(self.sender(json.loads(claim["payload_json"])))
            except Exception as error:
                LOG.error("downstream sender raised %s", type(error).__name__)
                result = {"success": False, "transient": True, "error_class": type(error).__name__}
            try:
                self._finish_delivery(claim, result, current)
            except sqlite3.Error:
                LOG.exception("delivery outcome could not be persisted; lease will be recovered")
                break
            processed += 1
            if delivery_id:
                break
        return processed

    def delivery(self, delivery_id):
        with self._connect() as connection:
            row = connection.execute("SELECT * FROM deliveries WHERE delivery_id=?", (delivery_id,)).fetchone()
            return dict(row) if row else None

    def deliveries(self):
        with self._connect() as connection:
            return [dict(row) for row in connection.execute("SELECT * FROM deliveries ORDER BY created_at_ms,delivery_id")]

    def events(self):
        with self._connect() as connection:
            return [json.loads(row[0]) for row in connection.execute("SELECT canonical_json FROM events ORDER BY received_at_ms,event_id")]

    def replay_dead_letter(self, delivery_id, actor, reason, *, confirm=False):
        if not actor or not reason:
            raise ValueError("actor and reason are required")
        with self._transaction() as connection:
            row = connection.execute(
                """SELECT d.* FROM deliveries d JOIN dead_letters l USING(delivery_id)
                WHERE d.delivery_id=? AND d.state='dead_letter' AND l.disposition='unresolved'""",
                (delivery_id,),
            ).fetchone()
            if not row:
                raise ValueError("delivery is not an unresolved dead letter")
            if not confirm:
                return {"delivery_id": delivery_id, "would_replay": True}
            now = self.now().astimezone(UTC)
            replay_id = self._enqueue_delivery(
                connection, event_id=row["event_id"], digest_id=row["digest_id"],
                notification_id=row["notification_id"], purpose="dead_letter_replay",
                payload=json.loads(row["payload_json"]),
                due_at=now, replay_of=delivery_id,
            )
            now_ms = to_milliseconds(now)
            connection.execute(
                """UPDATE dead_letters SET disposition='replayed',disposed_at_ms=?,disposed_by=?,
                disposition_reason=? WHERE delivery_id=?""",
                (now_ms, actor, reason, delivery_id),
            )
            connection.execute(
                "INSERT INTO operator_audit VALUES (?,?,?,?,?,?,?)",
                (str(uuid.uuid4()), "replay", actor, "delivery", delivery_id, reason, now_ms),
            )
            self.delivery_wake.set()
            return {"delivery_id": replay_id, "replay_of": delivery_id}

    def discard_dead_letter(self, delivery_id, actor, reason, *, confirm=False):
        if not actor or not reason:
            raise ValueError("actor and reason are required")
        with self._transaction() as connection:
            row = connection.execute(
                """SELECT 1 FROM deliveries d JOIN dead_letters l USING(delivery_id)
                WHERE d.delivery_id=? AND d.state='dead_letter'
                AND l.disposition='unresolved'""",
                (delivery_id,),
            ).fetchone()
            if not row:
                raise ValueError("delivery is not an unresolved dead letter")
            if not confirm:
                return {"delivery_id": delivery_id, "would_discard": True}
            now_ms = to_milliseconds(self.now().astimezone(UTC))
            connection.execute(
                """UPDATE dead_letters SET disposition='discarded',disposed_at_ms=?,
                disposed_by=?,disposition_reason=? WHERE delivery_id=?""",
                (now_ms, actor, reason, delivery_id),
            )
            connection.execute(
                "INSERT INTO operator_audit VALUES (?,?,?,?,?,?,?)",
                (str(uuid.uuid4()), "discard", actor, "delivery", delivery_id, reason, now_ms),
            )
            return {"delivery_id": delivery_id, "discarded": True}

    def _records_for_day(self, day):
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT received_at_ms,source_instance,state,subject_label,summary,canonical_json
                FROM events WHERE received_day=? AND routing_action='digest' ORDER BY received_at_ms,event_id""",
                (day.isoformat(),),
            )
            return [
                {
                    "received_at": isoformat(from_milliseconds(row["received_at_ms"])),
                    "source": row["source_instance"],
                    "status": "ok" if row["state"] == "ok" else row["state"],
                    "subject": row["subject_label"],
                    "summary": row["summary"],
                }
                for row in rows
            ]

    def _digest_text(self, day, records):
        groups = {}
        for record in records:
            key = (record.get("source", "unknown"), record.get("subject", "unknown"))
            groups.setdefault(key, []).append(record.get("summary", "(empty)"))
        heading = f"✅ *daily-success-summary* · {day.isoformat()} UTC · {len(records)} successful oncall messages"
        lines = [heading]
        for (source, subject), summaries in sorted(groups.items()):
            lines.append(f"{source} / {subject}: {len(summaries)}")
            lines.extend(f"  {summary}" for summary in summaries)
        text = "\n".join(lines)
        if len(text) <= self.max_digest_chars:
            return text
        suffix = "\n… digest truncated; full records remain in durable storage"
        return text[: self.max_digest_chars - len(suffix)].rstrip() + suffix

    def _ensure_digest(self, day, current):
        with self._transaction() as connection:
            existing = connection.execute("SELECT digest_id FROM digests WHERE digest_day=?", (day.isoformat(),)).fetchone()
            if existing:
                return existing["digest_id"]
            rows = list(
                connection.execute(
                    """SELECT event_id,received_at_ms,source_instance,state,subject_label,summary
                    FROM events WHERE received_day=? AND routing_action='digest'
                    ORDER BY received_at_ms,event_id""",
                    (day.isoformat(),),
                )
            )
            if not rows:
                return None
            records = [
                {"source": row["source_instance"], "subject": row["subject_label"], "summary": row["summary"]}
                for row in rows
            ]
            digest_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"fcc-chat-digest:{day.isoformat()}"))
            text = self._digest_text(day, records)
            current_ms = to_milliseconds(current)
            connection.execute(
                "INSERT INTO digests VALUES (?,?, 'queued',?,?,?,NULL)",
                (digest_id, day.isoformat(), text, len(rows), current_ms),
            )
            for ordinal, row in enumerate(rows):
                connection.execute("INSERT INTO digest_members VALUES (?,?,?)", (digest_id, row["event_id"], ordinal))
            self._enqueue_delivery(
                connection, digest_id=digest_id, purpose="digest", payload={"text": text}, due_at=current,
            )
            return digest_id

    def send_digest(self, day):
        current = self.now().astimezone(UTC)
        with self._connect() as connection:
            existing = connection.execute(
                "SELECT digest_id,state FROM digests WHERE digest_day=?", (day.isoformat(),)
            ).fetchone()
        if existing and existing["state"] == "delivered":
            return False
        digest_id = existing["digest_id"] if existing else self._ensure_digest(day, current)
        if not digest_id:
            return False
        with self._connect() as connection:
            delivery = connection.execute("SELECT delivery_id FROM deliveries WHERE digest_id=?", (digest_id,)).fetchone()
        if delivery:
            self.process_deliveries(current, delivery_id=delivery["delivery_id"], limit=1)
        with self._connect() as connection:
            state = connection.execute("SELECT state FROM digests WHERE digest_id=?", (digest_id,)).fetchone()[0]
        return state == "delivered"

    def _system_event(self, connection, *, identity, state, subject, summary, text, current, notification_id):
        event_id = str(uuid.uuid5(uuid.NAMESPACE_URL, identity))
        event = {
            "schema": "fcc.alert-event/v1",
            "event_id": event_id,
            "source": {"id": "webhook-proxy", "instance": "webhook-proxy", "adapter": "internal/v1"},
            "provider": {"event_id": identity, "delivery_id": None, "incident_key": identity.rsplit(":", 1)[0]},
            "kind": "system",
            "state": state,
            "severity": SEVERITY_BY_STATE[state],
            "subject": {"key": subject, "label": subject},
            "summary": summary,
            "details": None,
            "link": None,
            "link_label": None,
            "observed_at": isoformat(current),
            "received_at": isoformat(current),
            "heartbeat": {"expectation_id": None, "scheduled_for": None},
            "routing": {"action": "immediate", "policy_version": 1, "reason": "heartbeat-episode"},
        }
        self._insert_event(connection, event, current)
        delivery_id = self._enqueue_delivery(
            connection, event_id=event_id, notification_id=notification_id,
            purpose="heartbeat_recovery" if state == "resolved" else "heartbeat_reminder",
            payload={"text": render_event(event)}, due_at=current,
        )
        return event_id, delivery_id

    def _enqueue_episode_notice(self, connection, expectation, episode, stage, current, recovery_state=None):
        notification_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{episode['episode_id']}:{stage}"))
        if connection.execute("SELECT 1 FROM heartbeat_notifications WHERE notification_id=?", (notification_id,)).fetchone():
            return
        if stage == "recovery":
            text = (
                f"✅ *webhook-proxy* · cron reporting resumed · {expectation['label']} reported again"
                + (f" with state {recovery_state}" if recovery_state and recovery_state != "ok" else "")
            )
            state = "resolved"
        else:
            occurrence = from_milliseconds(episode["first_missed_for_ms"])
            suffix = "" if stage == "initial" else f"; reminder {stage}, {episode['missed_count']} occurrence(s) missed"
            text = (
                f"🔴 *webhook-proxy* · missed cron · {expectation['label']} did not report "
                f"for expected tick {occurrence.strftime('%Y-%m-%d %H:%M UTC')}{suffix}"
            )
            state = "failed"
            if stage != "initial":
                connection.execute(
                    """UPDATE deliveries SET state='cancelled' WHERE notification_id IN
                    (SELECT notification_id FROM heartbeat_notifications WHERE episode_id=? AND state='queued')
                    AND state IN ('pending','retry_wait')""",
                    (episode["episode_id"],),
                )
                connection.execute(
                    "UPDATE heartbeat_notifications SET state='cancelled' WHERE episode_id=? AND state='queued'",
                    (episode["episode_id"],),
                )
        connection.execute(
            "INSERT INTO heartbeat_notifications VALUES (?,?,?,?,'queued',NULL)",
            (notification_id, episode["episode_id"], stage, to_milliseconds(current)),
        )
        event_id, _ = self._system_event(
            connection,
            identity=f"heartbeat:{episode['episode_id']}:{stage}",
            state=state,
            subject="cron reporting resumed" if stage == "recovery" else "missed cron",
            summary=text.split(" · ", 2)[-1],
            text=text,
            current=current,
            notification_id=notification_id,
        )
        connection.execute("UPDATE heartbeat_notifications SET event_id=? WHERE notification_id=?", (event_id, notification_id))

    def _latest_occurrence(self, expectation, cutoff):
        matches = occurrences_between(expectation["schedule"], cutoff - timedelta(days=8), cutoff)
        return matches[-1] if matches else cutoff

    def check_crons(self, current=None):
        current = (current or self.now()).astimezone(UTC)
        cutoff = current - self.grace
        with self.lock:
            for expectation in self.expectations:
                with self._transaction() as connection:
                    cursor = connection.execute(
                        "SELECT last_evaluated_for_ms FROM heartbeat_cursors WHERE expectation_id=?",
                        (expectation["id"],),
                    ).fetchone()
                    if not cursor:
                        latest = self._latest_occurrence(expectation, cutoff)
                        connection.execute(
                            "INSERT INTO heartbeat_cursors VALUES (?,?)",
                            (expectation["id"], to_milliseconds(latest)),
                        )
                        continue
                    open_episode = connection.execute(
                        "SELECT * FROM heartbeat_episodes WHERE expectation_id=? AND state='open'",
                        (expectation["id"],),
                    ).fetchone()
                    if open_episode:
                        recovery = connection.execute(
                            """SELECT state FROM heartbeat_observations WHERE expectation_id=?
                            AND observed_at_ms>? ORDER BY observed_at_ms LIMIT 1""",
                            (expectation["id"], open_episode["first_deadline_ms"]),
                        ).fetchone()
                        if recovery:
                            connection.execute(
                                "UPDATE heartbeat_episodes SET state='recovered',recovered_at_ms=?,recovery_state=? WHERE episode_id=?",
                                (to_milliseconds(current), recovery["state"], open_episode["episode_id"]),
                            )
                            connection.execute(
                                """UPDATE deliveries SET state='cancelled' WHERE notification_id IN
                                (SELECT notification_id FROM heartbeat_notifications WHERE episode_id=? AND state='queued')
                                AND state IN ('pending','retry_wait')""",
                                (open_episode["episode_id"],),
                            )
                            connection.execute(
                                "UPDATE heartbeat_notifications SET state='cancelled' WHERE episode_id=? AND state='queued'",
                                (open_episode["episode_id"],),
                            )
                            self._enqueue_episode_notice(connection, expectation, dict(open_episode), "recovery", current, recovery["state"])
                            open_episode = None
                    last = from_milliseconds(cursor["last_evaluated_for_ms"])
                    for occurrence in occurrences_between(expectation["schedule"], last, cutoff):
                        occurrence_ms = to_milliseconds(occurrence)
                        deadline_ms = to_milliseconds(occurrence + self.grace)
                        observation = connection.execute(
                            """SELECT observation_id,event_id FROM heartbeat_observations
                            WHERE expectation_id=? AND scheduled_for_ms IS NULL
                            AND observed_at_ms>=? AND observed_at_ms<=? ORDER BY observed_at_ms LIMIT 1""",
                            (expectation["id"], occurrence_ms, deadline_ms),
                        ).fetchone()
                        if observation:
                            connection.execute(
                                "UPDATE heartbeat_observations SET scheduled_for_ms=? WHERE observation_id=?",
                                (occurrence_ms, observation["observation_id"]),
                            )
                            connection.execute(
                                "INSERT OR IGNORE INTO heartbeat_occurrences VALUES (?,?,?,'observed',?,NULL,?)",
                                (expectation["id"], occurrence_ms, deadline_ms, observation["event_id"], to_milliseconds(current)),
                            )
                        else:
                            episode = connection.execute(
                                "SELECT * FROM heartbeat_episodes WHERE expectation_id=? AND state='open'",
                                (expectation["id"],),
                            ).fetchone()
                            if not episode:
                                episode_id = str(uuid.uuid4())
                                connection.execute(
                                    "INSERT INTO heartbeat_episodes VALUES (?,?,'open',?,?,?,?,?,NULL,NULL)",
                                    (episode_id, expectation["id"], occurrence_ms, deadline_ms, occurrence_ms, 1, to_milliseconds(current)),
                                )
                                episode = connection.execute("SELECT * FROM heartbeat_episodes WHERE episode_id=?", (episode_id,)).fetchone()
                                self._enqueue_episode_notice(connection, expectation, dict(episode), "initial", current)
                            else:
                                connection.execute(
                                    "UPDATE heartbeat_episodes SET last_missed_for_ms=?,missed_count=missed_count+1 WHERE episode_id=?",
                                    (occurrence_ms, episode["episode_id"]),
                                )
                            connection.execute(
                                "INSERT OR IGNORE INTO heartbeat_occurrences VALUES (?,?,?,'missed',NULL,?,?)",
                                (expectation["id"], occurrence_ms, deadline_ms, episode["episode_id"], to_milliseconds(current)),
                            )
                        connection.execute(
                            "UPDATE heartbeat_cursors SET last_evaluated_for_ms=? WHERE expectation_id=?",
                            (occurrence_ms, expectation["id"]),
                        )
                    episode = connection.execute(
                        "SELECT * FROM heartbeat_episodes WHERE expectation_id=? AND state='open'",
                        (expectation["id"],),
                    ).fetchone()
                    if episode:
                        episode = dict(episode)
                        for stage, offset in REMINDER_OFFSETS:
                            due = from_milliseconds(episode["first_deadline_ms"]) + timedelta(seconds=offset)
                            if current >= due:
                                self._enqueue_episode_notice(connection, expectation, episode, stage, current)
        self.delivery_wake.set()

    def _pending_digest_days(self, current):
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT DISTINCT received_day FROM events e WHERE routing_action='digest'
                AND received_day<? AND NOT EXISTS (SELECT 1 FROM digests d WHERE d.digest_day=e.received_day)
                ORDER BY received_day""",
                (current.date().isoformat(),),
            )
            return [date.fromisoformat(row[0]) for row in rows]

    def cleanup(self, current=None):
        current = (current or self.now()).astimezone(UTC)
        digest_cutoff = to_milliseconds(current - timedelta(days=self.retention_days))
        event_cutoff = to_milliseconds(current - timedelta(days=90))
        audit_cutoff = to_milliseconds(current - timedelta(days=365))
        with self._transaction() as connection:
            connection.execute("DELETE FROM dedupe_claims WHERE expires_at_ms<?", (to_milliseconds(current),))
            connection.execute(
                """DELETE FROM events WHERE received_at_ms<? AND routing_action='digest'
                AND EXISTS (
                  SELECT 1 FROM digest_members m JOIN digests d USING(digest_id)
                  WHERE m.event_id=events.event_id AND d.state='delivered'
                )
                AND NOT EXISTS (
                  SELECT 1 FROM deliveries d WHERE d.event_id=events.event_id
                  AND d.state IN ('pending','in_flight','retry_wait','dead_letter')
                )""",
                (digest_cutoff,),
            )
            connection.execute(
                "DELETE FROM digests WHERE delivered_at_ms IS NOT NULL AND delivered_at_ms<?",
                (event_cutoff,),
            )
            purgeable_episodes = connection.execute(
                """SELECT episode_id FROM heartbeat_episodes e
                WHERE state='recovered' AND recovered_at_ms<?
                AND NOT EXISTS (
                  SELECT 1 FROM heartbeat_notifications n
                  WHERE n.episode_id=e.episode_id
                  AND n.state IN ('queued','dead_letter')
                )""",
                (event_cutoff,),
            ).fetchall()
            for row in purgeable_episodes:
                episode_id = row["episode_id"]
                connection.execute(
                    """DELETE FROM deliveries WHERE notification_id IN
                    (SELECT notification_id FROM heartbeat_notifications WHERE episode_id=?)
                    AND state IN ('delivered','cancelled')""",
                    (episode_id,),
                )
                connection.execute(
                    "DELETE FROM heartbeat_notifications WHERE episode_id=?",
                    (episode_id,),
                )
                connection.execute(
                    "DELETE FROM heartbeat_occurrences WHERE episode_id=?",
                    (episode_id,),
                )
                connection.execute(
                    "DELETE FROM heartbeat_episodes WHERE episode_id=?",
                    (episode_id,),
                )
            connection.execute(
                "DELETE FROM heartbeat_occurrences WHERE evaluated_at_ms<? AND episode_id IS NULL",
                (event_cutoff,),
            )
            connection.execute(
                "DELETE FROM heartbeat_observations WHERE observed_at_ms<?",
                (event_cutoff,),
            )
            connection.execute(
                """DELETE FROM deliveries WHERE replay_of_delivery_id IS NOT NULL
                AND state IN ('delivered','cancelled')
                AND COALESCE(delivered_at_ms,created_at_ms)<?""",
                (event_cutoff,),
            )
            connection.execute(
                """DELETE FROM dead_letters WHERE disposition!='unresolved' AND disposed_at_ms<?
                AND NOT EXISTS (
                  SELECT 1 FROM deliveries replay
                  WHERE replay.replay_of_delivery_id=dead_letters.delivery_id
                )""",
                (event_cutoff,),
            )
            connection.execute(
                """DELETE FROM deliveries WHERE state='dead_letter' AND created_at_ms<?
                AND NOT EXISTS (
                  SELECT 1 FROM dead_letters
                  WHERE dead_letters.delivery_id=deliveries.delivery_id
                )""",
                (event_cutoff,),
            )
            connection.execute(
                """DELETE FROM events WHERE received_at_ms<? AND routing_action!='digest'
                AND NOT EXISTS (
                  SELECT 1 FROM deliveries d WHERE d.event_id=events.event_id
                  AND d.state IN ('pending','in_flight','retry_wait','dead_letter')
                )
                AND NOT EXISTS (
                  SELECT 1 FROM heartbeat_notifications n WHERE n.event_id=events.event_id
                )""",
                (event_cutoff,),
            )
            connection.execute("DELETE FROM operator_audit WHERE occurred_at_ms<?", (audit_cutoff,))

    def backup_to(self, destination):
        backup_database(self.database_path, destination)

    def readiness(self):
        try:
            if not self.webhook:
                return False
            if shutil.disk_usage(self.data_dir).free < self.min_free_bytes:
                return False
            connection = self._connect()
            try:
                _validate_sqlite(connection)
                connection.execute("BEGIN IMMEDIATE")
                connection.execute(
                    "INSERT OR REPLACE INTO runtime_state VALUES ('readiness-probe','ok',?)",
                    (to_milliseconds(self.now()),),
                )
                connection.execute("ROLLBACK")
                return True
            finally:
                connection.close()
        except (OSError, sqlite3.Error, RuntimeError):
            return False

    def status(self):
        current = self.now().astimezone(UTC)
        now_ms = to_milliseconds(current)
        with self._connect() as connection:
            queue = connection.execute(
                """SELECT COUNT(*) AS count,MIN(created_at_ms) AS oldest
                FROM deliveries WHERE state IN ('pending','in_flight','retry_wait')"""
            ).fetchone()
            dead = connection.execute(
                """SELECT COUNT(*) FROM dead_letters
                WHERE disposition='unresolved'"""
            ).fetchone()[0]
            retries = connection.execute("SELECT COUNT(*) FROM deliveries WHERE state='retry_wait'").fetchone()[0]
            overdue_digest = connection.execute(
                """SELECT MIN(e.received_at_ms) FROM events e
                WHERE e.routing_action='digest' AND e.received_day<?
                AND NOT EXISTS (
                  SELECT 1 FROM digest_members m JOIN digests d USING(digest_id)
                  WHERE m.event_id=e.event_id AND d.state='delivered'
                )""",
                (current.date().isoformat(),),
            ).fetchone()[0]
        ready = self.readiness()
        oldest_age = max(0, (now_ms - queue["oldest"]) // 1000) if queue["oldest"] is not None else 0
        digest_age = max(0, (now_ms - overdue_digest) // 1000) if overdue_digest is not None else 0
        scheduler_age = max(0, int((current - self.last_scheduler_run).total_seconds()))
        degraded = (
            dead > 0
            or queue["count"] >= self.max_queue_depth
            or oldest_age >= 3600
            or digest_age >= 3600
            or scheduler_age >= 120
        )
        return {
            "status": "not-ready" if not ready else "degraded" if degraded else "ready",
            "queued": queue["count"],
            "retries": retries,
            "dead_letters": dead,
            "oldest_queue_age_seconds": oldest_age,
            "oldest_overdue_digest_age_seconds": digest_age,
            "scheduler_age_seconds": scheduler_age,
            "database_bytes": self.database_path.stat().st_size,
            "disk_free_bytes": shutil.disk_usage(self.data_dir).free,
        }

    def scheduled_work(self, current=None):
        current = (current or self.now()).astimezone(UTC)
        self.check_crons(current)
        for day in self._pending_digest_days(current):
            self._ensure_digest(day, current)
        self.delivery_wake.set()
        self.cleanup(current)
        self.last_scheduler_run = current


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "fcc-chat-proxy/2"

    def setup(self):
        super().setup()
        self.connection.settimeout(self.server.request_timeout)

    def _json_response(self, status, payload):
        body = json.dumps(payload, separators=(",", ":")).encode() + b"\n"
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/livez", "/healthz"):
            self._json_response(200, {"status": "ok"})
            return
        if self.path == "/readyz":
            ready = self.server.proxy.readiness()
            self._json_response(200 if ready else 503, {"status": "ready" if ready else "not-ready"})
            return
        if self.path == "/statusz":
            try:
                status = self.server.proxy.status()
            except (OSError, sqlite3.Error, RuntimeError):
                LOG.exception("status check failed")
                self._json_response(503, {"status": "not-ready"})
                return
            self._json_response(200, status)
            return
        self.send_error(404)

    def do_POST(self):
        if self.path != "/hooks/chat":
            self.send_error(404)
            return
        content_type = self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
        if content_type != "application/json":
            self.send_error(415)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if length < 1 or length > self.server.max_request_bytes:
            self.send_error(413 if length > self.server.max_request_bytes else 400)
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except TimeoutError:
            self.send_error(408)
            return
        except OSError:
            LOG.warning("request body read failed")
            return
        except (UnicodeDecodeError, ValueError):
            self.send_error(400)
            return
        accepted, status = self.server.proxy.accept(payload)
        self._json_response(status, {"accepted": accepted})

    def log_message(self, message, *args):
        LOG.info("%s - %s", self.address_string(), message % args)


class ProxyServer(ThreadingHTTPServer):
    daemon_threads = False

    def __init__(self, address, proxy, max_request_bytes, request_timeout=10):
        self.proxy = proxy
        self.max_request_bytes = max_request_bytes
        self.request_timeout = request_timeout
        super().__init__(address, ProxyHandler)


def main():
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    proxy = ChatProxy(
        read_secret("GOOGLE_CHAT_WEBHOOK"),
        os.environ.get("CHAT_PROXY_DATA_DIR", "/data"),
        os.environ.get("CHAT_PROXY_EXPECTATIONS", "/app/cron-expectations.json"),
        grace_minutes=int(os.environ.get("CHAT_PROXY_GRACE_MINUTES", "15")),
        retention_days=int(os.environ.get("CHAT_PROXY_RETENTION_DAYS", "30")),
        max_queue_depth=int(os.environ.get("CHAT_PROXY_MAX_QUEUE_DEPTH", "10000")),
        min_free_bytes=int(os.environ.get("CHAT_PROXY_MIN_FREE_BYTES", str(64 * 1024 * 1024))),
    )
    server = ProxyServer(
        ("0.0.0.0", int(os.environ.get("PORT", "8080"))),
        proxy,
        int(os.environ.get("CHAT_PROXY_MAX_REQUEST_BYTES", "65536")),
        int(os.environ.get("CHAT_PROXY_REQUEST_TIMEOUT_SECONDS", "10")),
    )

    def scheduler():
        while not proxy.stopping.wait(30):
            try:
                proxy.scheduled_work()
            except Exception:
                LOG.exception("scheduled work failed")

    def delivery_worker():
        while not proxy.stopping.is_set():
            proxy.delivery_wake.wait(1)
            proxy.delivery_wake.clear()
            if proxy.stopping.is_set():
                break
            proxy.process_deliveries()

    scheduler_thread = threading.Thread(target=scheduler, name="scheduler", daemon=True)
    delivery_thread = threading.Thread(target=delivery_worker, name="delivery", daemon=True)
    scheduler_thread.start()
    delivery_thread.start()
    proxy.delivery_wake.set()

    def stop(_signum, _frame):
        proxy.stopping.set()
        proxy.delivery_wake.set()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    LOG.info("chat proxy listening on port %s", server.server_port)
    try:
        server.serve_forever()
    finally:
        proxy.stopping.set()
        proxy.delivery_wake.set()
        server.server_close()
        deadline = time.monotonic() + 20
        for worker in (scheduler_thread, delivery_thread):
            worker.join(timeout=max(0, deadline - time.monotonic()))
        if scheduler_thread.is_alive() or delivery_thread.is_alive():
            LOG.error("workers did not stop before the shutdown deadline; leases will expire normally")
        else:
            try:
                proxy.release_inflight_leases()
            except (OSError, sqlite3.Error):
                LOG.exception("in-flight delivery leases could not be released during shutdown")


if __name__ == "__main__":
    main()
