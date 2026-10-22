#!/usr/bin/env python3
"""Buffer routine oncall messages and forward actionable Google Chat alerts."""

from __future__ import annotations

import json
import logging
import os
import re
import signal
import threading
import time
from datetime import date, datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

LOG = logging.getLogger("chat-proxy")
UTC = timezone.utc
STATUS_BY_ICON = {"✅": "ok", "⚠️": "warn", "🔴": "fail"}
LINK_SUFFIX = re.compile(r"\s*·\s*<[^>]+\|[^>]+>\s*$")


def utc_now():
    return datetime.now(UTC)


def isoformat(value):
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)


def parse_message(text):
    icon = next((candidate for candidate in STATUS_BY_ICON if text.startswith(candidate)), None)
    status = STATUS_BY_ICON.get(icon, "unknown")
    first_line = text.splitlines()[0] if text else ""
    content = first_line[len(icon) :].strip() if icon else first_line.strip()
    parts = content.split(" · ", 2)
    source = parts[0].strip("* ") if parts else "unknown"
    subject = parts[1].strip() if len(parts) > 1 else "unknown"
    summary = parts[2].strip() if len(parts) > 2 else first_line.strip()
    summary = LINK_SUFFIX.sub("", summary)
    return {
        "status": status,
        "source": source or "unknown",
        "subject": subject or "unknown",
        "summary": summary or "(empty)",
    }


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
        raise ValueError(f"v1 supports six-field schedules with second 0, got {schedule!r}")
    cursor = start.astimezone(UTC).replace(second=0, microsecond=0) + timedelta(minutes=1)
    limit = end.astimezone(UTC)
    matches = []
    while cursor <= limit:
        if schedule_matches(schedule, cursor):
            matches.append(cursor)
        cursor += timedelta(minutes=1)
    return matches


class ChatProxy:
    def __init__(
        self,
        webhook,
        data_dir,
        expectations_path,
        *,
        grace_minutes=15,
        retention_days=7,
        max_digest_chars=3500,
        now=utc_now,
        sender=None,
    ):
        self.webhook = webhook
        self.data_dir = Path(data_dir)
        self.expectations_path = Path(expectations_path)
        self.grace = timedelta(minutes=grace_minutes)
        self.retention_days = retention_days
        self.max_digest_chars = max_digest_chars
        self.now = now
        self.sender = sender or self._send_to_chat
        self.lock = threading.RLock()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.state_path = self.data_dir / "state.json"
        self.expectations = self._load_expectations()
        self.state = self._load_state()
        self.digest_attempts = {}

    def _load_expectations(self):
        with self.expectations_path.open(encoding="utf-8") as source:
            expectations = json.load(source)
        for expectation in expectations:
            schedule = expectation["schedule"]
            if len(schedule.split()) != 6 or schedule.split()[0] != "0":
                raise ValueError(f"unsupported schedule for {expectation['id']}: {schedule}")
        return expectations

    def _load_state(self):
        try:
            with self.state_path.open(encoding="utf-8") as source:
                state = json.load(source)
        except FileNotFoundError:
            state = {}
        except (OSError, ValueError):
            LOG.exception("state file is unreadable; starting with empty state")
            state = {}
        state.setdefault("cron", {})
        state.setdefault("digested_dates", [])
        return state

    def _save_state(self):
        temporary = self.state_path.with_suffix(".tmp")
        with temporary.open("w", encoding="utf-8") as target:
            json.dump(self.state, target, sort_keys=True)
            target.write("\n")
            target.flush()
            os.fsync(target.fileno())
        temporary.replace(self.state_path)

    def _success_path(self, day):
        return self.data_dir / f"success-{day.isoformat()}.jsonl"

    def _append_success(self, record):
        path = self._success_path(parse_timestamp(record["received_at"]).date())
        with path.open("a", encoding="utf-8") as target:
            target.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
            target.flush()
            os.fsync(target.fileno())

    def _send_to_chat(self, payload):
        if not self.webhook:
            LOG.error("GOOGLE_CHAT_WEBHOOK is empty; message not delivered")
            return False
        body = json.dumps(payload, ensure_ascii=False).encode()
        request = Request(
            self.webhook,
            data=body,
            headers={"Content-Type": "application/json; charset=UTF-8"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=30) as response:
                accepted = 200 <= response.status < 300
                if not accepted:
                    LOG.error("Google Chat rejected a message with HTTP %s", response.status)
                return accepted
        except HTTPError as error:
            LOG.error("Google Chat rejected a message with HTTP %s", error.code)
        except (URLError, TimeoutError, OSError) as error:
            LOG.error("Google Chat delivery failed: %s", type(error).__name__)
        return False

    def _matching_expectations(self, parsed):
        return [
            expectation
            for expectation in self.expectations
            if expectation["source"] == parsed["source"]
            and expectation["subject"] == parsed["subject"]
        ]

    def _observe(self, parsed, received_at):
        changed = False
        for expectation in self._matching_expectations(parsed):
            cron_state = self.state["cron"].setdefault(expectation["id"], {})
            observations = cron_state.setdefault("observations", [])
            observations.append(isoformat(received_at))
            cron_state["observations"] = observations[-2048:]
            changed = True
        if changed:
            self._save_state()

    def accept(self, payload, received_at=None):
        received_at = (received_at or self.now()).astimezone(UTC)
        text = payload.get("text") if isinstance(payload, dict) else None
        if not isinstance(text, str):
            return False, 400
        parsed = parse_message(text)
        record = {"received_at": isoformat(received_at), "text": text, **parsed}
        with self.lock:
            try:
                self._observe(parsed, received_at)
            except OSError:
                LOG.exception("cron observation state could not be persisted")
            if parsed["status"] == "ok":
                try:
                    self._append_success(record)
                    return True, 202
                except OSError:
                    LOG.exception("success storage failed; forwarding message immediately")
            self.sender(payload)
        return True, 202

    def _records_for_day(self, day):
        path = self._success_path(day)
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except FileNotFoundError:
            return []
        records = []
        for line in lines:
            try:
                records.append(json.loads(line))
            except ValueError:
                LOG.error("ignored malformed success record in %s", path.name)
        return records

    def _digest_text(self, day, records):
        groups = {}
        for record in records:
            key = (record.get("source", "unknown"), record.get("subject", "unknown"))
            groups.setdefault(key, []).append(record.get("summary", "(empty)"))
        heading = (
            f"✅ *daily-success-summary* · {day.isoformat()} UTC · "
            f"{len(records)} successful oncall messages"
        )
        lines = [heading]
        for (source, subject), summaries in sorted(groups.items()):
            lines.append(f"{source} / {subject}: {len(summaries)}")
            lines.extend(f"  {summary}" for summary in summaries)
        text = "\n".join(lines)
        if len(text) <= self.max_digest_chars:
            return text
        suffix = "\n… digest truncated; full records remain in the seven-day archive"
        return text[: self.max_digest_chars - len(suffix)].rstrip() + suffix

    def send_digest(self, day):
        day_key = day.isoformat()
        with self.lock:
            if day_key in self.state["digested_dates"]:
                return False
            records = self._records_for_day(day)
            if not records:
                return False
            if not self.sender({"text": self._digest_text(day, records)}):
                return False
            self.state["digested_dates"].append(day_key)
            self.state["digested_dates"] = sorted(set(self.state["digested_dates"]))
            self._save_state()
            return True

    def _initialize_cron(self, expectation, cutoff):
        search_start = cutoff - timedelta(days=8)
        occurrences = occurrences_between(expectation["schedule"], search_start, cutoff)
        cron_state = self.state["cron"].setdefault(expectation["id"], {})
        cron_state["last_checked"] = isoformat(occurrences[-1] if occurrences else cutoff)

    def check_crons(self, current=None):
        current = (current or self.now()).astimezone(UTC)
        cutoff = current - self.grace
        with self.lock:
            state_changed = False
            for expectation in self.expectations:
                cron_state = self.state["cron"].setdefault(expectation["id"], {})
                if "last_checked" not in cron_state:
                    self._initialize_cron(expectation, cutoff)
                    state_changed = True
                    continue
                last_checked = parse_timestamp(cron_state["last_checked"])
                observation_values = cron_state.get("observations", [])
                if cron_state.get("last_observed"):
                    observation_values.append(cron_state.pop("last_observed"))
                observations = sorted(parse_timestamp(value) for value in observation_values)
                for occurrence in occurrences_between(expectation["schedule"], last_checked, cutoff):
                    deadline = occurrence + self.grace
                    seen = any(occurrence <= observed <= deadline for observed in observations)
                    if not seen:
                        text = (
                            f"🔴 *webhook-proxy* · missed cron · {expectation['label']} did not report "
                            f"for expected tick {occurrence.strftime('%Y-%m-%d %H:%M UTC')}"
                        )
                        if not self.sender({"text": text}):
                            cron_state["observations"] = [isoformat(value) for value in observations]
                            if state_changed:
                                self._save_state()
                            return
                    observations = [observed for observed in observations if observed > deadline]
                    cron_state["observations"] = [isoformat(value) for value in observations]
                    cron_state["last_checked"] = isoformat(occurrence)
                    state_changed = True
            if state_changed:
                self._save_state()

    def cleanup(self, current=None):
        current = (current or self.now()).astimezone(UTC)
        oldest = current.date() - timedelta(days=self.retention_days)
        with self.lock:
            for path in self.data_dir.glob("success-*.jsonl"):
                try:
                    day = datetime.strptime(path.stem.removeprefix("success-"), "%Y-%m-%d").date()
                except ValueError:
                    continue
                if day < oldest:
                    path.unlink(missing_ok=True)
            retained_dates = [
                value
                for value in self.state["digested_dates"]
                if date.fromisoformat(value) >= oldest
            ]
            if retained_dates != self.state["digested_dates"]:
                self.state["digested_dates"] = retained_dates
                self._save_state()

    def _pending_digest_days(self, current):
        days = []
        for path in self.data_dir.glob("success-*.jsonl"):
            try:
                day = datetime.strptime(path.stem.removeprefix("success-"), "%Y-%m-%d").date()
            except ValueError:
                continue
            if day < current.date() and day.isoformat() not in self.state["digested_dates"]:
                days.append(day)
        return sorted(days)

    def scheduled_work(self, current=None):
        current = (current or self.now()).astimezone(UTC)
        self.check_crons(current)
        for day in self._pending_digest_days(current):
            last_attempt = self.digest_attempts.get(day)
            if last_attempt and current - last_attempt < timedelta(minutes=5):
                continue
            self.digest_attempts[day] = current
            if not self.send_digest(day):
                break
        self.cleanup(current)


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "fcc-chat-proxy/1"

    def do_GET(self):
        if self.path != "/healthz":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}\n')

    def do_POST(self):
        if self.path != "/hooks/chat":
            self.send_error(404)
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
        except (UnicodeDecodeError, ValueError):
            self.send_error(400)
            return
        _, status = self.server.proxy.accept(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"accepted":true}\n' if status < 300 else b'{"accepted":false}\n')

    def log_message(self, message, *args):
        LOG.info("%s - %s", self.address_string(), message % args)


class ProxyServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, proxy, max_request_bytes):
        self.proxy = proxy
        self.max_request_bytes = max_request_bytes
        super().__init__(address, ProxyHandler)


def main():
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    proxy = ChatProxy(
        os.environ.get("GOOGLE_CHAT_WEBHOOK", ""),
        os.environ.get("CHAT_PROXY_DATA_DIR", "/data"),
        os.environ.get("CHAT_PROXY_EXPECTATIONS", "/app/cron-expectations.json"),
        grace_minutes=int(os.environ.get("CHAT_PROXY_GRACE_MINUTES", "15")),
        retention_days=int(os.environ.get("CHAT_PROXY_RETENTION_DAYS", "7")),
    )
    server = ProxyServer(
        ("0.0.0.0", int(os.environ.get("PORT", "8080"))),
        proxy,
        int(os.environ.get("CHAT_PROXY_MAX_REQUEST_BYTES", "65536")),
    )
    stopping = threading.Event()

    def scheduler():
        while not stopping.wait(30):
            try:
                proxy.scheduled_work()
            except Exception:
                LOG.exception("scheduled work failed")

    worker = threading.Thread(target=scheduler, name="scheduler", daemon=True)
    worker.start()

    def stop(_signum, _frame):
        stopping.set()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    LOG.info("chat proxy listening on port %s", server.server_port)
    try:
        server.serve_forever()
    finally:
        stopping.set()
        server.server_close()


if __name__ == "__main__":
    main()
