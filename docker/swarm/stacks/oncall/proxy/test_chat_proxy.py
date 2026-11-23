import hashlib
import hmac
import http.client
import json
import shutil
import socket
import sqlite3
import tempfile
import threading
import time
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen as _urlopen


def urlopen(request, *, timeout):
    # Test URLs are constructed from the local test server only.
    return _urlopen(request, timeout=timeout)  # nosec B310

from chat_proxy import (
    ChatProxy,
    ProxyServer,
    occurrences_between,
    parse_message,
    read_secret,
    render_event,
    restore_database,
    schedule_matches,
)

UTC = timezone.utc
HERE = Path(__file__).resolve().parent
EXPECTATIONS = HERE / "cron-expectations.json"
STACK = HERE.parent / "stack-oncall.yml"
GRAFANA_VALUES = HERE.parents[4] / "k3s/ops-o11y/apps/grafana/values-mgmt.yaml"
GITHUB_SECRET = "github-current-secret"
GITHUB_PREVIOUS_SECRET = "github-previous-secret"
GRAFANA_SECRET = "grafana-current-secret"
GRAFANA_PREVIOUS_SECRET = "grafana-previous-secret"


def github_payload(**overrides):
    payload = {
        "schema": "fcc.github-actions-event/v1",
        "status": "fail",
        "source": "housekeeping",
        "subject": "Wed 21 Oct",
        "summary": "ANOMALY: nginx unavailable",
        "details": "pxy-1\n  inactive",
        "link": "https://github.com/freeCodeCamp/infra/actions/runs/123?token=redacted",
        "link_label": "run",
        "repository": "freeCodeCamp/infra",
        "run_id": "123",
        "run_attempt": "1",
        "notification_key": "housekeeping-summary",
    }
    payload.update(overrides)
    return payload


def github_signature(body, timestamp, secret=GITHUB_SECRET):
    digest = hmac.new(
        secret.encode(),
        timestamp.encode() + b"." + body,
        hashlib.sha256,
    ).hexdigest()
    return "sha256=" + digest


def grafana_payload(
    *,
    status="firing",
    alertname="HighLoad",
    fingerprint="0123456789abcdef",
    starts_at="2026-10-02T00:00:00Z",
    ends_at="0001-01-01T00:00:00Z",
    annotations=None,
    labels=None,
    **overrides,
):
    labels = {
        "alertname": alertname,
        "instance": "mgmt-01",
        **(labels or {}),
    }
    annotations = {
        "summary": "Load is above the threshold",
        **(annotations or {}),
    }
    alert = {
        "status": status,
        "labels": labels,
        "annotations": annotations,
        "startsAt": starts_at,
        "endsAt": ends_at,
        "generatorURL": "https://grafana.example.test/alerting/rules/abc?token=secret",
        "fingerprint": fingerprint,
        "silenceURL": "https://grafana.example.test/silence?matcher=secret",
        "dashboardURL": "https://grafana.example.test/d/ops?orgId=1",
        "panelURL": "https://grafana.example.test/d/ops?viewPanel=2",
        "ruleUID": "rule-abc",
        "values": {"A": 2.0},
        "valueString": "[ var='A' value=2 ]",
        "orgId": 1,
    }
    payload = {
        "receiver": "ops-chat",
        "status": status,
        "alerts": [alert],
        "groupLabels": {"alertname": alertname},
        "commonLabels": {"alertname": alertname},
        "commonAnnotations": annotations,
        "externalURL": "https://grafana.example.test/",
        "appVersion": "13.2.1",
        "version": "1",
        "groupKey": f'{{}}:{{alertname="{alertname}"}}',
        "truncatedAlerts": 0,
        "orgId": 1,
        "title": f"[{status.upper()}:1] {alertname}",
        "state": "alerting" if status == "firing" else "ok",
        "message": "provider-formatted message is not retained",
    }
    payload.update(overrides)
    return payload


def grafana_signature(body, timestamp, secret=GRAFANA_SECRET):
    return hmac.new(
        secret.encode(),
        timestamp.encode() + b":" + body,
        hashlib.sha256,
    ).hexdigest()


class ChatProxyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.current = datetime(2026, 10, 2, 0, 1, tzinfo=UTC)
        self.sent = []

        def sender(payload):
            self.sent.append(payload)
            return True

        self.proxy = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            now=lambda: self.current,
            sender=sender,
            jitter=lambda: 1,
            github_secrets=(GITHUB_SECRET, GITHUB_PREVIOUS_SECRET),
            grafana_secrets=(GRAFANA_SECRET, GRAFANA_PREVIOUS_SECRET),
        )

    def scalar(self, sql, parameters=()):
        with self.proxy._connect() as connection:
            return connection.execute(sql, parameters).fetchone()[0]

    def test_parses_standard_message_into_canonical_fields(self):
        text = (
            "✅ *dispatch* · freeCodeCamp/news deploy-eng.yml · dispatch accepted · "
            "<https://example.test/run?secret=yes|runs>\ndetail"
        )
        parsed = parse_message(text)
        self.assertEqual(parsed["status"], "ok")
        self.assertEqual(parsed["state"], "ok")
        self.assertEqual(parsed["source"], "dispatch")
        self.assertEqual(parsed["subject"], "freeCodeCamp/news deploy-eng.yml")
        self.assertEqual(parsed["summary"], "dispatch accepted")
        self.assertEqual(parsed["link"], "https://example.test/run")
        self.assertEqual(parsed["details"], "detail")

    def test_legacy_mapping_matrix_and_durable_actions(self):
        cases = (
            ("✅ *watchdog* · news English · healthy", "ok", "digest"),
            ("⚠️ *dispatch* · target · warning", "warning", "immediate"),
            ("🔴 *watchdog* · news English · failed", "failed", "immediate"),
            ("plain unknown notice", "unknown", "immediate"),
        )
        for offset, (text, state, route) in enumerate(cases):
            with self.subTest(state=state):
                moment = self.current + timedelta(minutes=offset * 6)
                accepted, status = self.proxy.accept({"text": text}, moment)
                self.assertTrue(accepted)
                self.assertEqual(status, 202)
                event = self.proxy.events()[-1]
                self.assertEqual(event["schema"], "fcc.alert-event/v1")
                self.assertEqual(event["source"]["id"], "oncall")
                self.assertEqual(event["state"], state)
                self.assertEqual(event["routing"]["action"], route)
        self.assertEqual(len(self.proxy.events()), 4)
        self.assertEqual(len(self.proxy.deliveries()), 3)

    def test_central_renderer_is_deterministic_and_sanitizes_link_query(self):
        event, _ = self.proxy._canonicalize_legacy(
            {
                "text": (
                    "⚠️ *dispatch* · target · warning · "
                    "<https://example.test/run?token=secret|runs>"
                )
            },
            self.current,
        )
        expected = "⚠️ *dispatch* · target · warning · <https://example.test/run|runs>"
        self.assertEqual(render_event(event), expected)
        self.assertEqual(render_event(event), expected)
        self.assertNotIn("legacy_text", event)
        self.assertNotIn("token=secret", json.dumps(event))

    def test_unknown_legacy_text_sanitizes_chat_link_queries_and_userinfo(self):
        event, _ = self.proxy._canonicalize_legacy(
            {
                "text": (
                    "notice <https://example.test/run?token=secret|run> "
                    "<https://user:password@example.test/private|private>"
                )
            },
            self.current,
        )
        self.assertEqual(render_event(event), "notice <https://example.test/run|run> private")
        serialized = json.dumps(event)
        self.assertNotIn("token=secret", serialized)
        self.assertNotIn("password", serialized)

    def test_success_is_durable_without_immediate_delivery(self):
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        accepted, status = self.proxy.accept(
            {"text": "✅ *watchdog* · news English · feed healthy"}, moment
        )
        self.assertEqual((accepted, status), (True, 202))
        self.assertEqual(self.sent, [])
        self.assertEqual(len(self.proxy._records_for_day(date(2026, 10, 1))), 1)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_observations"), 1)

    def test_immediate_event_is_committed_before_sender_runs(self):
        observed = []

        def sender(payload):
            observed.append((payload, self.scalar("SELECT COUNT(*) FROM events"), self.scalar("SELECT COUNT(*) FROM deliveries")))
            return True

        self.proxy.sender = sender
        self.proxy.accept({"text": "🔴 *watchdog* · news English · failed"}, self.current)
        self.proxy.process_deliveries(self.current)
        self.assertEqual(observed[0][1:], (1, 1))
        self.assertEqual(self.proxy.deliveries()[0]["state"], "delivered")

    def test_storage_failure_returns_503_without_chat_bypass(self):
        with patch.object(self.proxy, "_transaction", side_effect=sqlite3.OperationalError("full")):
            with self.assertLogs("chat-proxy", level="ERROR"):
                accepted, status = self.proxy.accept({"text": "🔴 *watchdog* · news English · failed"})
        self.assertEqual((accepted, status), (False, 503))
        self.assertEqual(self.sent, [])
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM events"), 0)

    def test_post_commit_claim_failure_still_returns_202(self):
        with patch.object(
            self.proxy,
            "_claim_delivery",
            side_effect=sqlite3.OperationalError("locked"),
        ):
            result = self.proxy.accept(
                {"text": "🔴 *source* · claim unavailable · failed"},
                self.current,
            )
            with self.assertLogs("chat-proxy", level="ERROR"):
                self.proxy.process_deliveries(self.current)
        self.assertEqual(result, (True, 202))
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM events"), 1)
        self.assertEqual(self.scalar("SELECT state FROM deliveries"), "pending")

    def test_exact_legacy_retry_is_deduplicated_within_window(self):
        payload = {"text": "⚠️ *dispatch* · target · warning"}
        self.proxy.accept(payload, self.current)
        self.proxy.accept(payload, self.current + timedelta(seconds=20))
        self.proxy.process_deliveries(self.current)
        self.assertEqual(len(self.proxy.events()), 1)
        self.assertEqual(len(self.proxy.deliveries()), 1)
        self.assertEqual(len(self.sent), 1)

    def test_same_legacy_message_outside_window_is_distinct(self):
        payload = {"text": "⚠️ *dispatch* · target · warning"}
        self.proxy.accept(payload, self.current)
        self.proxy.accept(payload, self.current + timedelta(minutes=6))
        self.assertEqual(len(self.proxy.events()), 2)

    def test_non_text_and_oversized_canonical_fields_are_rejected(self):
        self.assertEqual(self.proxy.accept({"text": 42}), (False, 400))
        self.assertEqual(self.proxy.accept({"text": "✅ *source* · subject · " + "x" * 501}), (False, 400))
        self.assertEqual(self.proxy.events(), [])

    def test_database_schema_pragmas_and_restart_durability(self):
        self.proxy.accept({"text": "✅ *watchdog* · news English · feed healthy"}, self.current)
        with self.proxy._connect() as connection:
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 2)
            self.assertEqual(connection.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0], 2)
            self.assertEqual(connection.execute("PRAGMA journal_mode").fetchone()[0], "wal")
            self.assertEqual(connection.execute("PRAGMA foreign_keys").fetchone()[0], 1)
            self.assertEqual(connection.execute("PRAGMA busy_timeout").fetchone()[0], 5000)
            self.assertEqual(connection.execute("PRAGMA quick_check").fetchone()[0], "ok")
        self.assertEqual(self.proxy.database_path.stat().st_mode & 0o777, 0o600)
        restarted = ChatProxy("", self.temporary.name, EXPECTATIONS, sender=lambda _payload: True)
        self.assertEqual(len(restarted.events()), 1)

    def test_schema_one_database_migrates_to_schema_two(self):
        with self.proxy._connect() as connection:
            connection.execute("DROP TABLE ingress_failures")
            connection.execute("DELETE FROM schema_migrations WHERE version=2")
            connection.execute("PRAGMA user_version=1")
        migrated = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            github_secrets=(GITHUB_SECRET,),
        )
        with migrated._connect() as connection:
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 2)
            self.assertEqual(connection.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0], 2)
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM ingress_failures").fetchone()[0], 0)

    def test_corrupt_database_fails_closed_at_startup(self):
        other = tempfile.TemporaryDirectory()
        self.addCleanup(other.cleanup)
        Path(other.name, "chat-proxy.sqlite3").write_bytes(b"not a sqlite database")
        with self.assertRaises(sqlite3.DatabaseError):
            ChatProxy("", other.name, EXPECTATIONS)

    def test_newer_schema_fails_closed(self):
        other = tempfile.TemporaryDirectory()
        self.addCleanup(other.cleanup)
        database = Path(other.name) / "chat-proxy.sqlite3"
        with sqlite3.connect(database) as connection:
            connection.execute("PRAGMA user_version=99")
        with self.assertRaisesRegex(RuntimeError, "newer"):
            ChatProxy("", other.name, EXPECTATIONS)

    def test_nonempty_legacy_state_fails_closed_even_with_empty_database_file(self):
        other = tempfile.TemporaryDirectory()
        self.addCleanup(other.cleanup)
        Path(other.name, "state.json").write_text("{}\n", encoding="utf-8")
        Path(other.name, "chat-proxy.sqlite3").touch()
        with self.assertRaisesRegex(RuntimeError, "legacy proxy state"):
            ChatProxy("", other.name, EXPECTATIONS)

    def test_real_lock_contention_waits_then_accepts(self):
        blocker = sqlite3.connect(self.proxy.database_path, isolation_level=None)
        blocker.execute("BEGIN IMMEDIATE")
        result = []
        thread = threading.Thread(
            target=lambda: result.append(
                self.proxy.accept({"text": "✅ *source* · locked · healthy"}, self.current)
            )
        )
        thread.start()
        time.sleep(0.1)
        self.assertTrue(thread.is_alive())
        blocker.execute("ROLLBACK")
        blocker.close()
        thread.join(2)
        self.assertEqual(result, [(True, 202)])

    def test_sqlite_full_returns_503_and_preserves_integrity(self):
        self.proxy.min_free_bytes = 0
        original_connect = self.proxy._connect

        def capacity_limited_connect():
            connection = original_connect()
            pages = connection.execute("PRAGMA page_count").fetchone()[0]
            connection.execute(f"PRAGMA max_page_count={pages}")
            return connection

        self.proxy._connect = capacity_limited_connect
        result = (True, 202)
        with self.assertLogs("chat-proxy", level="ERROR"):
            for index in range(200):
                result = self.proxy.accept(
                    {"text": f"✅ *source* · full-{index} · " + "x" * 450},
                    self.current + timedelta(seconds=index),
                )
                if result == (False, 503):
                    break
        self.assertEqual(result, (False, 503))
        with self.proxy._connect() as connection:
            self.assertEqual(connection.execute("PRAGMA quick_check").fetchone()[0], "ok")

    def test_transient_failure_stays_queued_and_producer_gets_202(self):
        self.proxy.sender = lambda _payload: False
        accepted, status = self.proxy.accept({"text": "🔴 *watchdog* · news English · failed"}, self.current)
        self.assertEqual((accepted, status), (True, 202))
        self.proxy.process_deliveries(self.current)
        delivery = self.proxy.deliveries()[0]
        self.assertEqual(delivery["state"], "retry_wait")
        self.assertEqual(delivery["attempt_count"], 1)
        self.assertEqual(delivery["next_attempt_at_ms"], int((self.current + timedelta(seconds=30)).timestamp() * 1000))

    def test_terminal_failure_dead_letters_immediately(self):
        self.proxy.sender = lambda _payload: {
            "success": False,
            "transient": False,
            "http_status": 401,
            "error_class": "http",
        }
        self.proxy.accept({"text": "🔴 *watchdog* · news English · failed"}, self.current)
        self.proxy.process_deliveries(self.current)
        delivery = self.proxy.deliveries()[0]
        self.assertEqual(delivery["state"], "dead_letter")
        self.assertEqual(delivery["attempt_count"], 1)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM dead_letters"), 1)

    def test_nine_transient_attempts_dead_letter_over_24_hours(self):
        self.proxy.sender = lambda _payload: False
        self.proxy.accept({"text": "🔴 *watchdog* · news English · failed"}, self.current)
        self.proxy.process_deliveries(self.current)
        for seconds in (30, 120, 600, 1800, 7200, 21600, 43200, 86400):
            self.proxy.process_deliveries(self.current + timedelta(seconds=seconds))
        delivery = self.proxy.deliveries()[0]
        self.assertEqual(delivery["attempt_count"], 9)
        self.assertEqual(delivery["state"], "dead_letter")
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM delivery_attempts"), 9)

    def test_ambiguous_post_send_persistence_failure_recovers_expired_lease(self):
        original_finish = self.proxy._finish_delivery
        with patch.object(
            self.proxy,
            "_finish_delivery",
            side_effect=sqlite3.OperationalError("crash boundary"),
        ):
            accepted, status = self.proxy.accept(
                {"text": "🔴 *watchdog* · news English · failed"}, self.current
            )
            with self.assertLogs("chat-proxy", level="ERROR"):
                self.proxy.process_deliveries(self.current)
        self.assertEqual((accepted, status), (True, 202))
        delivery = self.proxy.deliveries()[0]
        self.assertEqual(delivery["state"], "in_flight")
        self.proxy._finish_delivery = original_finish
        self.proxy.process_deliveries(self.current + timedelta(minutes=2))
        self.assertEqual(self.proxy.deliveries()[0]["state"], "delivered")
        self.assertEqual(len(self.sent), 2)

    def test_clean_shutdown_releases_inflight_delivery_lease(self):
        self.proxy.stopping.set()
        self.proxy.accept({"text": "🔴 *source* · interrupted · failed"}, self.current)
        self.proxy.stopping.clear()
        claim = self.proxy._claim_delivery(self.current)
        self.assertIsNotNone(claim)
        self.assertEqual(self.proxy.delivery(claim["delivery_id"])["state"], "in_flight")
        self.assertEqual(self.proxy.release_inflight_leases(), 1)
        recovered = self.proxy.delivery(claim["delivery_id"])
        self.assertEqual(recovered["state"], "retry_wait")
        self.assertIsNone(recovered["lease_token"])
        self.assertEqual(
            self.scalar("SELECT outcome FROM delivery_attempts WHERE delivery_id=?", (claim["delivery_id"],)),
            "shutdown",
        )

    def test_dead_letter_replay_requires_confirmation_and_is_audited(self):
        self.proxy.sender = lambda _payload: {"success": False, "transient": False, "error_class": "bad_request"}
        self.proxy.accept({"text": "🔴 *watchdog* · news English · failed"}, self.current)
        self.proxy.process_deliveries(self.current)
        original = self.proxy.deliveries()[0]["delivery_id"]
        preview = self.proxy.replay_dead_letter(original, "infra-team", "fixed destination")
        self.assertTrue(preview["would_replay"])
        self.assertEqual(len(self.proxy.deliveries()), 1)
        replay = self.proxy.replay_dead_letter(original, "infra-team", "fixed destination", confirm=True)
        self.assertEqual(replay["replay_of"], original)
        self.assertEqual(len(self.proxy.deliveries()), 2)
        self.assertEqual(self.proxy.status()["dead_letters"], 0)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM operator_audit"), 1)
        with self.assertRaises(ValueError):
            self.proxy.replay_dead_letter(original, "infra-team", "again", confirm=True)

    def test_dead_letter_discard_requires_confirmation_and_is_audited(self):
        self.proxy.sender = lambda _payload: {
            "success": False,
            "transient": False,
            "error_class": "invalid",
        }
        self.proxy.accept({"text": "🔴 *source* · invalid event · failed"}, self.current)
        self.proxy.process_deliveries(self.current)
        delivery_id = self.proxy.deliveries()[0]["delivery_id"]
        preview = self.proxy.discard_dead_letter(
            delivery_id,
            "infra-team",
            "confirmed invalid payload",
        )
        self.assertTrue(preview["would_discard"])
        result = self.proxy.discard_dead_letter(
            delivery_id,
            "infra-team",
            "confirmed invalid payload",
            confirm=True,
        )
        self.assertTrue(result["discarded"])
        self.assertEqual(self.proxy.status()["dead_letters"], 0)
        self.assertEqual(self.scalar("SELECT action FROM operator_audit"), "discard")
        with self.assertRaises(ValueError):
            self.proxy.discard_dead_letter(
                delivery_id,
                "infra-team",
                "discard twice",
                confirm=True,
            )

    def test_disposed_dead_letter_expires_after_replay_retention(self):
        old = self.current - timedelta(days=100)
        self.proxy.sender = lambda _payload: {
            "success": False,
            "transient": False,
            "error_class": "terminal",
        }
        self.proxy.accept({"text": "🔴 *source* · old dead letter · failed"}, old)
        self.proxy.process_deliveries(old)
        original = self.proxy.deliveries()[0]["delivery_id"]
        replay = self.proxy.replay_dead_letter(
            original,
            "infra-team",
            "destination repaired",
            confirm=True,
        )
        self.proxy.sender = lambda _payload: True
        self.proxy.process_deliveries(self.current, delivery_id=replay["delivery_id"])
        self.proxy.cleanup(self.current + timedelta(days=100))
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM dead_letters"), 0)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM deliveries"), 0)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM events"), 0)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM operator_audit"), 1)

    def test_digest_groups_records_omits_links_and_is_idempotent(self):
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        self.proxy.accept(
            {"text": "✅ *watchdog* · news English · feed healthy · <https://secret.test/a|feed>"},
            moment,
        )
        self.proxy.accept(
            {"text": "✅ *watchdog* · news English · quiet hours, check skipped"},
            moment + timedelta(hours=1),
        )
        self.assertTrue(self.proxy.send_digest(date(2026, 10, 1)))
        text = self.sent[-1]["text"]
        self.assertIn("2 successful oncall messages", text)
        self.assertIn("watchdog / news English: 2", text)
        self.assertNotIn("secret.test", text)
        self.assertFalse(self.proxy.send_digest(date(2026, 10, 1)))
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM digests"), 1)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM digest_members"), 2)

    def test_failed_digest_delivery_retains_members_and_retries(self):
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        self.proxy.accept({"text": "✅ *watchdog* · news English · feed healthy"}, moment)
        self.proxy.sender = lambda _payload: False
        self.assertFalse(self.proxy.send_digest(date(2026, 10, 1)))
        self.assertEqual(self.scalar("SELECT state FROM digests"), "queued")
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM digest_members"), 1)
        delivery = self.proxy.deliveries()[0]
        self.proxy.sender = lambda payload: self.sent.append(payload) or True
        due = datetime.fromtimestamp(delivery["next_attempt_at_ms"] / 1000, UTC)
        self.proxy.process_deliveries(due)
        self.assertEqual(self.scalar("SELECT state FROM digests"), "delivered")

    def test_late_success_after_frozen_digest_is_immediate(self):
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        self.proxy.accept({"text": "✅ *watchdog* · news English · first"}, moment)
        self.assertTrue(self.proxy.send_digest(date(2026, 10, 1)))
        late = moment + timedelta(hours=2)
        self.proxy.accept({"text": "✅ *watchdog* · news English · late"}, late)
        self.proxy.process_deliveries(late)
        event = self.proxy.events()[-1]
        self.assertEqual(event["routing"]["reason"], "late-after-digest")
        self.assertEqual(self.sent[-1]["text"], "✅ *watchdog* · news English · late")

    def test_digest_is_bounded(self):
        self.proxy.max_digest_chars = 160
        self.proxy.accept(
            {"text": "✅ *watchdog* · news English · " + "healthy " * 40},
            datetime(2026, 10, 1, 12, 50, tzinfo=UTC),
        )
        self.assertTrue(self.proxy.send_digest(date(2026, 10, 1)))
        self.assertLessEqual(len(self.sent[-1]["text"]), 160)
        self.assertIn("digest truncated", self.sent[-1]["text"])

    def test_cleanup_preserves_pending_digest_immediate_and_dead_letters(self):
        old = self.current - timedelta(days=100)
        self.proxy.accept({"text": "✅ *source* · old digest · healthy"}, old)
        digest_id = self.proxy.events()[0]["event_id"]
        self.proxy.sender = lambda _payload: False
        self.proxy.accept({"text": "🔴 *watchdog* · old pending · failed"}, old + timedelta(minutes=6))
        pending_id = self.proxy.events()[1]["event_id"]
        self.proxy.sender = lambda _payload: {"success": False, "transient": False, "error_class": "terminal"}
        self.proxy.accept({"text": "🔴 *watchdog* · old dead · failed"}, old + timedelta(minutes=12))
        self.proxy.cleanup(self.current)
        ids = {event["event_id"] for event in self.proxy.events()}
        self.assertIn(digest_id, ids)
        self.assertIn(pending_id, ids)
        self.assertEqual(len(ids), 3)

    def test_active_digest_delivery_does_not_block_unrelated_retention(self):
        delivered_day = (self.current - timedelta(days=40)).date()
        active_day = (self.current - timedelta(days=10)).date()
        self.proxy.accept(
            {"text": "✅ *source* · expired delivered digest · healthy"},
            datetime.combine(delivered_day, datetime.min.time(), UTC) + timedelta(hours=1),
        )
        self.proxy.send_digest(delivered_day)
        self.proxy.accept(
            {"text": "✅ *source* · active digest · healthy"},
            datetime.combine(active_day, datetime.min.time(), UTC) + timedelta(hours=1),
        )
        self.proxy.sender = lambda _payload: False
        self.proxy.send_digest(active_day)
        self.proxy.cleanup(self.current)
        subjects = {event["subject"]["label"] for event in self.proxy.events()}
        self.assertNotIn("expired delivered digest", subjects)
        self.assertIn("active digest", subjects)

    def test_backup_is_consistent_readable_and_atomically_replaced(self):
        self.proxy.accept({"text": "✅ *watchdog* · news English · healthy"}, self.current)
        destination = Path(self.temporary.name) / "backups" / "proxy.sqlite3"
        destination.parent.mkdir()
        destination.write_bytes(b"previous backup")
        with patch("chat_proxy.os.replace", side_effect=OSError("interrupted")):
            with self.assertRaises(OSError):
                self.proxy.backup_to(destination)
        self.assertEqual(destination.read_bytes(), b"previous backup")
        self.assertEqual(list(destination.parent.glob(".*.tmp")), [])
        self.proxy.backup_to(destination)
        self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
        with sqlite3.connect(destination) as connection:
            self.assertEqual(connection.execute("PRAGMA quick_check").fetchone()[0], "ok")
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0], 1)

    def test_restore_replaces_database_from_validated_backup(self):
        first = self.current - timedelta(hours=1)
        self.proxy.accept({"text": "✅ *source* · retained · healthy"}, first)
        backup = Path(self.temporary.name) / "backups" / "proxy.sqlite3"
        self.proxy.backup_to(backup)
        self.proxy.accept({"text": "✅ *source* · discarded · healthy"}, self.current)
        restore_database(backup, self.proxy.database_path)
        restored = ChatProxy(
            "",
            self.temporary.name,
            EXPECTATIONS,
            now=lambda: self.current,
            sender=lambda _payload: True,
        )
        summaries = [event["summary"] for event in restored.events()]
        self.assertEqual(summaries, ["healthy"])
        self.assertEqual(restored.events()[0]["subject"]["label"], "retained")

    def test_cron_initialization_does_not_alert_for_history(self):
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.assertEqual(self.sent, [])
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_cursors"), 4)

    def test_observed_tick_suppresses_miss_and_failure_counts_as_observed(self):
        self.proxy.expectations = [item for item in self.proxy.expectations if item["id"] == "watchdog-news"]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.accept(
            {"text": "🔴 *watchdog* · news English · feed unreadable"},
            datetime(2026, 10, 1, 11, 51, tzinfo=UTC),
        )
        immediate_count = len(self.sent)
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.assertEqual(len(self.sent), immediate_count)
        self.assertEqual(self.scalar("SELECT state FROM heartbeat_occurrences"), "observed")

    def test_consecutive_misses_form_one_episode_and_escalate(self):
        self.proxy.expectations = [item for item in self.proxy.expectations if item["id"] == "watchdog-news"]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        first = datetime(2026, 10, 1, 12, 6, tzinfo=UTC)
        self.proxy.check_crons(first)
        self.proxy.process_deliveries(first)
        self.assertEqual(len(self.sent), 1)
        for offset in (1, 6, 24, 30):
            moment = first + timedelta(hours=offset)
            self.proxy.check_crons(moment)
            self.proxy.process_deliveries(moment)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_episodes"), 1)
        self.assertEqual(self.scalar("SELECT missed_count FROM heartbeat_episodes"), 31)
        stages = self.scalar("SELECT COUNT(*) FROM heartbeat_notifications WHERE stage!='recovery'")
        self.assertEqual(stages, 4)
        self.assertEqual(len(self.sent), 4)

    def test_late_heartbeat_recovers_episode_opened_after_it_arrived(self):
        self.proxy.expectations = [item for item in self.proxy.expectations if item["id"] == "watchdog-news"]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.accept(
            {"text": "✅ *watchdog* · news English · late but reporting"},
            datetime(2026, 10, 1, 12, 5, 30, tzinfo=UTC),
        )
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.proxy.process_deliveries(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.assertEqual(self.scalar("SELECT state FROM heartbeat_episodes"), "open")
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 7, tzinfo=UTC))
        self.proxy.process_deliveries(datetime(2026, 10, 1, 12, 7, tzinfo=UTC))
        self.assertEqual(self.scalar("SELECT state FROM heartbeat_episodes"), "recovered")
        recovery = [payload["text"] for payload in self.sent if "reporting resumed" in payload["text"]]
        self.assertEqual(len(recovery), 1)

    def test_heartbeat_recovery_closes_episode_once(self):
        self.proxy.expectations = [item for item in self.proxy.expectations if item["id"] == "watchdog-news"]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.proxy.accept(
            {"text": "⚠️ *watchdog* · news English · scheduler ran with warning"},
            datetime(2026, 10, 1, 12, 51, tzinfo=UTC),
        )
        self.proxy.check_crons(datetime(2026, 10, 1, 13, 6, tzinfo=UTC))
        self.proxy.process_deliveries(datetime(2026, 10, 1, 13, 6, tzinfo=UTC))
        self.assertEqual(self.scalar("SELECT state FROM heartbeat_episodes"), "recovered")
        recovery = [payload["text"] for payload in self.sent if "reporting resumed" in payload["text"]]
        self.assertEqual(len(recovery), 1)
        self.assertIn("state warning", recovery[0])
        self.proxy.check_crons(datetime(2026, 10, 1, 13, 10, tzinfo=UTC))
        self.assertEqual(len([payload for payload in self.sent if "reporting resumed" in payload["text"]]), 1)

    def test_recovered_heartbeat_history_expires_after_ninety_days(self):
        self.proxy.expectations = [item for item in self.proxy.expectations if item["id"] == "watchdog-news"]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.proxy.accept(
            {"text": "✅ *watchdog* · news English · healthy"},
            datetime(2026, 10, 1, 12, 51, tzinfo=UTC),
        )
        self.proxy.check_crons(datetime(2026, 10, 1, 13, 6, tzinfo=UTC))
        self.proxy.process_deliveries(datetime(2026, 10, 1, 13, 6, tzinfo=UTC))
        self.proxy.cleanup(datetime(2027, 1, 10, tzinfo=UTC))
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_episodes"), 0)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_occurrences"), 0)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_observations"), 0)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_notifications"), 0)

    def test_cron_delivery_does_not_block_event_acceptance(self):
        self.proxy.expectations = [item for item in self.proxy.expectations if item["id"] == "watchdog-news"]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        sender_started = threading.Event()
        release_sender = threading.Event()

        def blocking_sender(_payload):
            sender_started.set()
            release_sender.wait(2)
            return True

        self.proxy.sender = blocking_sender
        delivery_time = datetime(2026, 10, 1, 12, 6, tzinfo=UTC)
        self.proxy.check_crons(delivery_time)
        delivery_thread = threading.Thread(
            target=self.proxy.process_deliveries,
            args=(delivery_time,),
        )
        delivery_thread.start()
        self.assertTrue(sender_started.wait(1))
        result = []
        accept_thread = threading.Thread(
            target=lambda: result.append(
                self.proxy.accept(
                    {"text": "✅ *source* · unrelated · healthy"},
                    datetime(2026, 10, 1, 12, 7, tzinfo=UTC),
                )
            )
        )
        accept_thread.start()
        accept_thread.join(0.5)
        try:
            self.assertFalse(accept_thread.is_alive())
            self.assertEqual(result, [(True, 202)])
        finally:
            release_sender.set()
            accept_thread.join(2)
            delivery_thread.join(2)

    def test_cron_episode_survives_restart(self):
        self.proxy.expectations = [item for item in self.proxy.expectations if item["id"] == "watchdog-news"]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        restarted = ChatProxy(
            "", self.temporary.name, EXPECTATIONS,
            now=lambda: self.current, sender=lambda payload: self.sent.append(payload) or True,
            jitter=lambda: 1,
        )
        restarted.expectations = [item for item in restarted.expectations if item["id"] == "watchdog-news"]
        restarted.check_crons(datetime(2026, 10, 1, 12, 10, tzinfo=UTC))
        restarted.process_deliveries(datetime(2026, 10, 1, 12, 10, tzinfo=UTC))
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM heartbeat_episodes"), 1)
        self.assertEqual(len([payload for payload in self.sent if "missed cron" in payload["text"]]), 1)

    def test_concurrent_unique_accepts_are_all_durable(self):
        barrier = threading.Barrier(9)
        results = []

        def receive(index):
            barrier.wait()
            results.append(
                self.proxy.accept(
                    {"text": f"✅ *source* · subject-{index} · healthy"},
                    self.current + timedelta(seconds=index),
                )
            )

        threads = [threading.Thread(target=receive, args=(index,)) for index in range(8)]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join()
        self.assertEqual(results, [(True, 202)] * 8)
        self.assertEqual(len(self.proxy.events()), 8)

    def test_readiness_status_and_queue_capacity(self):
        self.assertTrue(self.proxy.readiness())
        status = self.proxy.status()
        self.assertEqual(status["status"], "ready")
        self.assertEqual(status["queued"], 0)
        self.assertEqual(status["retries"], 0)
        self.assertEqual(status["dead_letters"], 0)
        self.assertGreater(status["disk_free_bytes"], 0)
        self.assertEqual(status["scheduler_age_seconds"], 0)
        self.assertEqual(status["oldest_overdue_digest_age_seconds"], 0)

        self.proxy.max_queue_depth = 1
        self.proxy.sender = lambda _payload: False
        self.assertEqual(
            self.proxy.accept({"text": "🔴 *source* · first · failed"}, self.current),
            (True, 202),
        )
        duplicate = self.proxy.accept(
            {"text": "🔴 *source* · first · failed"},
            self.current + timedelta(seconds=20),
        )
        self.assertEqual(duplicate, (True, 202))
        routine = self.proxy.accept(
            {"text": "✅ *watchdog* · news English · healthy"},
            self.current + timedelta(minutes=1),
        )
        self.assertEqual(routine, (True, 202))
        with self.assertLogs("chat-proxy", level="ERROR"):
            result = self.proxy.accept(
                {"text": "🔴 *source* · second · failed"},
                self.current + timedelta(minutes=6),
            )
        self.assertEqual(result, (False, 503))
        self.assertEqual(len(self.proxy.events()), 2)

    def test_missing_destination_fails_readiness_but_keeps_acceptance_durable(self):
        self.proxy.webhook = ""
        self.assertFalse(self.proxy.readiness())
        self.assertEqual(
            self.proxy.accept({"text": "🔴 *source* · destination missing · failed"}),
            (True, 202),
        )
        self.assertEqual(self.scalar("SELECT state FROM deliveries"), "pending")

    def test_low_disk_floor_rejects_acceptance(self):
        disk_usage = shutil.disk_usage(self.temporary.name)
        with patch(
            "chat_proxy.shutil.disk_usage",
            return_value=type(disk_usage)(disk_usage.total, disk_usage.used, 0),
        ):
            self.assertFalse(self.proxy.readiness())
            with self.assertLogs("chat-proxy", level="ERROR"):
                self.assertEqual(
                    self.proxy.accept({"text": "✅ *source* · low disk · healthy"}),
                    (False, 503),
                )
        self.assertEqual(self.proxy.events(), [])

    def test_status_reports_stale_scheduler_and_overdue_digest(self):
        self.proxy.last_scheduler_run = self.current - timedelta(seconds=121)
        status = self.proxy.status()
        self.assertEqual(status["status"], "degraded")
        self.assertEqual(status["scheduler_age_seconds"], 121)
        self.proxy.last_scheduler_run = self.current
        self.proxy.accept(
            {"text": "✅ *source* · yesterday · healthy"},
            self.current - timedelta(hours=2),
        )
        status = self.proxy.status()
        self.assertEqual(status["status"], "degraded")
        self.assertEqual(status["oldest_overdue_digest_age_seconds"], 7200)

    def test_github_failure_maps_to_sanitized_immediate_event(self):
        accepted, status = self.proxy.accept_github(github_payload(), self.current)
        self.assertEqual((accepted, status), (True, 202))
        event = self.proxy.events()[0]
        self.assertEqual(event["source"], {
            "id": "github-actions",
            "instance": "housekeeping",
            "adapter": "github-actions/v1",
        })
        self.assertEqual(event["state"], "failed")
        self.assertEqual(event["kind"], "job")
        self.assertEqual(event["observed_at"], "2026-10-02T00:01:00Z")
        self.assertEqual(event["routing"]["action"], "immediate")
        self.assertEqual(
            event["provider"]["event_id"],
            '["freecodecamp/infra","123","1","housekeeping-summary"]',
        )
        self.assertEqual(event["link"], "https://github.com/freeCodeCamp/infra/actions/runs/123")
        self.assertNotIn("token=redacted", json.dumps(event))
        self.proxy.process_deliveries(self.current)
        self.assertIn("🔴 *housekeeping* · Wed 21 Oct · ANOMALY", self.sent[0]["text"])

    def test_github_success_enters_digest_without_immediate_delivery(self):
        payload = github_payload(
            status="ok",
            summary="OK: all stages passed",
            details="",
            notification_key="housekeeping-success",
        )
        self.assertEqual(self.proxy.accept_github(payload, self.current), (True, 202))
        self.assertEqual(self.proxy.events()[0]["routing"]["action"], "digest")
        self.assertEqual(self.proxy.deliveries(), [])
        self.assertEqual(self.sent, [])

    def test_github_run_identity_deduplicates_retries_but_not_attempts_or_keys(self):
        payload = github_payload()
        self.assertEqual(self.proxy.accept_github(payload, self.current), (True, 202))
        self.assertEqual(
            self.proxy.accept_github(payload, self.current + timedelta(seconds=2)),
            (True, 202),
        )
        self.assertEqual(
            self.proxy.accept_github(
                {**payload, "summary": "changed retry body"},
                self.current + timedelta(seconds=5),
            ),
            (False, 409),
        )
        self.proxy.accept_github({**payload, "run_attempt": "2"}, self.current + timedelta(seconds=10))
        self.proxy.accept_github(
            {**payload, "notification_key": "nginx-anomaly"},
            self.current + timedelta(seconds=15),
        )
        self.assertEqual(len(self.proxy.events()), 3)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM dedupe_claims WHERE scope='github-actions'"), 3)

    def test_github_dedupe_claim_survives_thirty_day_digest_retention(self):
        old = self.current - timedelta(days=40)
        payload = github_payload(status="ok", details=None)
        self.proxy.accept_github(payload, old, old)
        self.proxy.send_digest(old.date())
        self.proxy.cleanup(self.current)
        self.assertEqual(self.proxy.events(), [])
        self.assertEqual(
            self.scalar("SELECT COUNT(*) FROM dedupe_claims WHERE scope='github-actions'"),
            1,
        )
        self.assertEqual(self.proxy.accept_github(payload, self.current, old), (True, 202))
        self.assertEqual(self.proxy.events(), [])
        after_expiry = old + timedelta(days=91)
        self.assertEqual(
            self.proxy.accept_github(payload, after_expiry, after_expiry),
            (True, 202),
        )
        self.assertEqual(len(self.proxy.events()), 1)

    def test_concurrent_github_retries_create_one_event(self):
        barrier = threading.Barrier(9)
        results = []

        def accept_retry():
            barrier.wait()
            results.append(self.proxy.accept_github(github_payload(), self.current))

        threads = [threading.Thread(target=accept_retry) for _ in range(8)]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join()
        self.assertEqual(results, [(True, 202)] * 8)
        self.assertEqual(len(self.proxy.events()), 1)
        self.assertEqual(len(self.proxy.deliveries()), 1)

    def test_github_adapter_rejects_invalid_contracts(self):
        cases = (
            {"schema": "fcc.github-actions-event/v2"},
            {"status": "unknown"},
            {"repository": "not-a-repository"},
            {"run_id": "0"},
            {"run_attempt": "nope"},
            {"notification_key": "spaces are invalid"},
            {"extra_field": "not allowed"},
            {"link": "http://example.test/run"},
            {"link": "https://:443/run"},
            {"link": "https://example.test:bad/run"},
            {"link": "https://example.test/run with-space"},
            {"summary": "x" * 501},
            {"details": "x" * 8193},
        )
        for override in cases:
            with self.subTest(override=override):
                self.assertEqual(
                    self.proxy.accept_github(github_payload(**override), self.current),
                    (False, 422),
                )
        self.assertEqual(self.proxy.events(), [])

    def test_github_adapter_sanitizes_text_urls_and_chat_markup(self):
        payload = github_payload(
            source="<housekeeping>",
            subject="summary\nsubject",
            summary=(
                "failed http://insecure.test/path?password=secret "
                "https://example.test/path?token=secret"
            ),
            details="<host> HTTPS://example.test/detail?key=secret",
        )
        self.proxy.accept_github(payload, self.current)
        event = self.proxy.events()[0]
        serialized = json.dumps(event)
        self.assertEqual(event["source"]["instance"], "housekeeping")
        self.assertEqual(event["subject"]["label"], "summary subject")
        self.assertNotIn("token=secret", serialized)
        self.assertNotIn("password=secret", serialized)
        self.assertNotIn("key=secret", serialized)
        self.assertNotIn("<host>", serialized)

    def test_grafana_firing_maps_to_sanitized_immediate_event(self):
        payload = grafana_payload(
            annotations={
                "summary": "Load high https://status.test/detail?token=secret",
                "description": "Investigate <host>",
            }
        )
        self.assertEqual(self.proxy.accept_grafana(payload, self.current), (True, 202))
        event = self.proxy.events()[0]
        self.assertEqual(event["source"], {
            "id": "grafana",
            "instance": "ops-o11y",
            "adapter": "grafana/v1",
        })
        self.assertEqual(event["kind"], "alert")
        self.assertEqual(event["state"], "firing")
        self.assertEqual(event["severity"], "critical")
        self.assertEqual(event["routing"]["action"], "immediate")
        self.assertEqual(event["observed_at"], "2026-10-02T00:00:00Z")
        self.assertEqual(event["link"], "https://grafana.example.test/d/ops")
        serialized = json.dumps(event)
        self.assertNotIn("token=secret", serialized)
        self.assertNotIn("provider-formatted", serialized)
        self.assertNotIn("<host>", serialized)
        self.assertEqual(len(self.proxy.deliveries()), 1)

    def test_grafana_state_mapping_includes_nodata_error_test_and_resolution(self):
        cases = (
            (
                grafana_payload(
                    alertname="DatasourceNoData",
                    labels={"rulename": "Fleet health"},
                ),
                "no_data",
                "alert",
            ),
            (
                grafana_payload(
                    alertname="DatasourceError",
                    fingerprint="1123456789abcdef",
                    labels={"rulename": "Metrics query"},
                ),
                "error",
                "alert",
            ),
            (
                grafana_payload(
                    alertname="TestAlert",
                    fingerprint="2123456789abcdef",
                    labels={"instance": "Grafana"},
                    annotations={"summary": "Notification test"},
                ),
                "test",
                "test",
            ),
            (
                grafana_payload(
                    status="resolved",
                    fingerprint="3123456789abcdef",
                    ends_at="2026-10-02T00:00:30Z",
                ),
                "resolved",
                "alert",
            ),
        )
        for index, (payload, state, kind) in enumerate(cases):
            with self.subTest(state=state):
                accepted = self.proxy.accept_grafana(
                    payload, self.current + timedelta(seconds=index)
                )
                self.assertEqual(accepted, (True, 202))
                event = self.proxy.events()[-1]
                self.assertEqual(event["state"], state)
                self.assertEqual(event["kind"], kind)
                self.assertEqual(event["routing"]["action"], "immediate")

    def test_grafana_group_membership_and_four_hour_coalescing(self):
        payload = grafana_payload()
        self.assertEqual(self.proxy.accept_grafana(payload, self.current), (True, 202))
        self.assertEqual(
            self.proxy.accept_grafana(payload, self.current + timedelta(hours=3)),
            (True, 202),
        )
        self.assertEqual(len(self.proxy.events()), 1)
        self.assertEqual(
            self.proxy.accept_grafana(payload, self.current + timedelta(hours=4)),
            (True, 202),
        )
        self.assertEqual(len(self.proxy.events()), 2)

        changed_group = json.loads(json.dumps(payload))
        second = json.loads(json.dumps(changed_group["alerts"][0]))
        second["fingerprint"] = "4123456789abcdef"
        second["labels"]["instance"] = "mgmt-02"
        changed_group["alerts"].append(second)
        self.assertEqual(
            self.proxy.accept_grafana(changed_group, self.current + timedelta(hours=4, seconds=1)),
            (True, 202),
        )
        self.assertEqual(len(self.proxy.events()), 3)
        self.assertIn("2 alert(s) firing", self.proxy.events()[-1]["summary"])

    def test_grafana_resolution_is_distinct_from_active_occurrence(self):
        firing = grafana_payload()
        resolved = grafana_payload(
            status="resolved",
            ends_at="2026-10-02T00:02:00Z",
        )
        self.proxy.accept_grafana(firing, self.current)
        self.proxy.accept_grafana(resolved, self.current + timedelta(minutes=1))
        self.proxy.accept_grafana(resolved, self.current + timedelta(days=30))
        self.assertEqual([event["state"] for event in self.proxy.events()], ["firing", "resolved"])

    def test_grafana_adapter_rejects_invalid_contracts(self):
        cases = []
        for mutation in (
            lambda value: value.update({"version": "2"}),
            lambda value: value.update({"unknown": "field"}),
            lambda value: value.update({"status": "pending"}),
            lambda value: value.update({"state": "ok"}),
            lambda value: value.update({"alerts": []}),
            lambda value: value["alerts"][0].update({"fingerprint": "invalid"}),
            lambda value: value["alerts"][0].update({"startsAt": "not-a-time"}),
            lambda value: value["alerts"][0].update({"values": {"A": True}}),
            lambda value: value["alerts"][0].update({"values": {"A": float("inf")}}),
            lambda value: value["commonLabels"].update({"bad": 1}),
        ):
            payload = grafana_payload()
            mutation(payload)
            cases.append(payload)
        for payload in cases:
            with self.subTest(payload=payload):
                self.assertEqual(
                    self.proxy.accept_grafana(payload, self.current),
                    (False, 422),
                )
        self.assertEqual(self.proxy.events(), [])

    def test_grafana_signature_supports_rotation_timestamp_and_exact_body(self):
        self.assertEqual(
            grafana_signature(b'{"status":"firing"}', "1790899260"),
            "f9c37504920d48a1c6d7e1441dcc178319aca1641d8c545ef00d3f619abee006",
        )
        body = json.dumps(grafana_payload(), separators=(",", ":")).encode()
        timestamp = str(int(self.current.timestamp()))
        for secret in (GRAFANA_SECRET, GRAFANA_PREVIOUS_SECRET):
            with self.subTest(secret=secret):
                self.assertEqual(
                    self.proxy.verify_grafana_signature(
                        body,
                        timestamp,
                        grafana_signature(body, timestamp, secret),
                        self.current,
                    ),
                    (True, 202, "ok"),
                )
        self.assertEqual(
            self.proxy.verify_grafana_signature(
                body + b" ",
                timestamp,
                grafana_signature(body, timestamp),
                self.current,
            ),
            (False, 401, "invalid_signature"),
        )
        stale = str(int((self.current - timedelta(seconds=301)).timestamp()))
        self.assertEqual(
            self.proxy.verify_grafana_signature(
                body,
                stale,
                grafana_signature(body, stale),
                self.current,
            ),
            (False, 401, "stale_timestamp"),
        )

    def test_github_signature_supports_rotation_and_exact_body(self):
        body = json.dumps(github_payload(), separators=(",", ":")).encode()
        timestamp = str(int(self.current.timestamp()))
        for secret in (GITHUB_SECRET, GITHUB_PREVIOUS_SECRET):
            with self.subTest(secret=secret):
                self.assertEqual(
                    self.proxy.verify_github_signature(
                        body,
                        timestamp,
                        github_signature(body, timestamp, secret),
                        self.current,
                    ),
                    (True, 202, "ok"),
                )
        changed = body + b" "
        self.assertEqual(
            self.proxy.verify_github_signature(
                changed,
                timestamp,
                github_signature(body, timestamp),
                self.current,
            ),
            (False, 401, "invalid_signature"),
        )
        for seconds in (-300, 300):
            boundary = str(int((self.current + timedelta(seconds=seconds)).timestamp()))
            self.assertEqual(
                self.proxy.verify_github_signature(
                    body,
                    boundary,
                    github_signature(body, boundary),
                    self.current,
                ),
                (True, 202, "ok"),
            )
        for seconds in (-301, 301):
            stale = str(int((self.current + timedelta(seconds=seconds)).timestamp()))
            self.assertEqual(
                self.proxy.verify_github_signature(
                    body,
                    stale,
                    github_signature(body, stale),
                    self.current,
                ),
                (False, 401, "stale_timestamp"),
            )
        uppercase = github_signature(body, timestamp).upper()
        self.assertEqual(
            self.proxy.verify_github_signature(body, timestamp, uppercase, self.current),
            (False, 401, "missing_or_malformed"),
        )

    def test_github_rotation_rejects_duplicate_or_excess_secrets(self):
        with self.assertRaisesRegex(ValueError, "distinct current/previous"):
            ChatProxy(
                "https://chat.invalid/secret",
                self.temporary.name,
                EXPECTATIONS,
                github_secrets=(GITHUB_SECRET, GITHUB_SECRET),
            )
        with self.assertRaisesRegex(ValueError, "distinct current/previous"):
            ChatProxy(
                "https://chat.invalid/secret",
                self.temporary.name,
                EXPECTATIONS,
                github_secrets=("one", "two", "three"),
            )

    def test_grafana_rotation_and_readiness_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "distinct current/previous"):
            ChatProxy(
                "https://chat.invalid/secret",
                self.temporary.name,
                EXPECTATIONS,
                grafana_secrets=(GRAFANA_SECRET, GRAFANA_SECRET),
            )
        self.proxy.grafana_required = True
        self.proxy.grafana_secrets = ()
        self.assertFalse(self.proxy.readiness())
        self.proxy.grafana_secrets = (GRAFANA_SECRET,)
        self.assertTrue(self.proxy.readiness())

    def test_github_requirement_affects_readiness(self):
        self.proxy.github_required = True
        self.proxy.github_secrets = ()
        self.assertFalse(self.proxy.readiness())
        self.proxy.github_secrets = (GITHUB_SECRET,)
        self.assertTrue(self.proxy.readiness())

    def test_ingress_failure_metadata_expires_without_raw_payloads(self):
        self.proxy.record_ingress_failure(
            "github-actions",
            "auth",
            "invalid_signature",
            self.current - timedelta(days=31),
        )
        self.proxy.record_ingress_failure(
            "github-actions",
            "adapter",
            "invalid_payload",
            self.current - timedelta(days=15),
        )
        with self.proxy._connect() as connection:
            columns = {
                row[1] for row in connection.execute("PRAGMA table_info(ingress_failures)")
            }
        self.assertNotIn("payload", columns)
        self.proxy.cleanup(self.current)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM ingress_failures"), 0)

    def test_ingress_failure_metadata_is_capacity_bounded(self):
        with patch("chat_proxy.MAX_INGRESS_FAILURES", 3):
            for index in range(5):
                self.proxy.record_ingress_failure(
                    "github-actions",
                    "auth",
                    f"failure-{index}",
                    self.current + timedelta(seconds=index),
                )
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM ingress_failures"), 3)
        with self.proxy._connect() as connection:
            reasons = [row[0] for row in connection.execute(
                "SELECT reason FROM ingress_failures ORDER BY failure_id"
            )]
        self.assertEqual(reasons, ["failure-2", "failure-3", "failure-4"])

    def test_secret_file_takes_precedence(self):
        secret = Path(self.temporary.name) / "secret"
        secret.write_text("from-file\n", encoding="utf-8")
        with patch.dict("os.environ", {"TOKEN": "from-env", "TOKEN_FILE": str(secret)}):
            self.assertEqual(read_secret("TOKEN"), "from-file")
        secret.write_text(" surrounding-space \n", encoding="utf-8")
        with patch.dict("os.environ", {"TOKEN_FILE": str(secret)}):
            with self.assertRaisesRegex(ValueError, "surrounding whitespace"):
                read_secret("TOKEN")


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.sent = []
        self.current = datetime(2026, 10, 2, 0, 1, tzinfo=UTC)
        self.proxy = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            now=lambda: self.current,
            sender=lambda payload: self.sent.append(payload) or True,
            jitter=lambda: 1,
            github_secrets=(GITHUB_SECRET, GITHUB_PREVIOUS_SECRET),
            grafana_secrets=(GRAFANA_SECRET, GRAFANA_PREVIOUS_SECRET),
        )
        self.server = ProxyServer(("127.0.0.1", 0), self.proxy, 1024)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def scalar(self, sql, parameters=()):
        with self.proxy._connect() as connection:
            return connection.execute(sql, parameters).fetchone()[0]

    def post_raw(self, body, content_type="application/json"):
        request = Request(
            self.base_url + "/hooks/chat",
            data=body,
            headers={"Content-Type": content_type},
            method="POST",
        )
        return urlopen(request, timeout=2)

    def post(self, payload):
        return self.post_raw(json.dumps(payload).encode())

    def post_github(self, payload=None, *, body=None, secret=GITHUB_SECRET, timestamp=None, content_type="application/json"):
        body = body if body is not None else json.dumps(payload, separators=(",", ":")).encode()
        timestamp = timestamp or str(int(self.current.timestamp()))
        request = Request(
            self.base_url + "/v1/events/github-actions",
            data=body,
            headers={
                "Content-Type": content_type,
                "X-FCC-Timestamp": timestamp,
                "X-FCC-Signature": github_signature(body, timestamp, secret),
            },
            method="POST",
        )
        return urlopen(request, timeout=2)

    def post_grafana(
        self,
        payload=None,
        *,
        body=None,
        secret=GRAFANA_SECRET,
        timestamp=None,
        content_type="application/json",
    ):
        body = body if body is not None else json.dumps(payload, separators=(",", ":")).encode()
        timestamp = timestamp or str(int(self.current.timestamp()))
        request = Request(
            self.base_url + "/v1/events/grafana",
            data=body,
            headers={
                "Content-Type": content_type,
                "X-Grafana-Alerting-Timestamp": timestamp,
                "X-Grafana-Alerting-Signature": grafana_signature(
                    body, timestamp, secret
                ),
            },
            method="POST",
        )
        return urlopen(request, timeout=2)

    def test_liveness_readiness_and_health_alias(self):
        for path, expected in (("/livez", {"status": "ok"}), ("/healthz", {"status": "ok"}), ("/readyz", {"status": "ready"})):
            with self.subTest(path=path):
                with urlopen(self.base_url + path, timeout=2) as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(json.load(response), expected)

    def test_status_endpoint_contains_counts_but_no_content_or_paths(self):
        with urlopen(self.base_url + "/statusz", timeout=2) as response:
            status = json.load(response)
        self.assertEqual(status["status"], "ready")
        self.assertEqual(status["queued"], 0)
        self.assertNotIn("database_path", status)
        self.assertNotIn("events", status)

    def test_status_failure_returns_bounded_503(self):
        with patch.object(self.proxy, "status", side_effect=sqlite3.DatabaseError("corrupt")):
            with self.assertLogs("chat-proxy", level="ERROR"):
                with self.assertRaises(HTTPError) as error:
                    urlopen(self.base_url + "/statusz", timeout=2)
        self.assertEqual(error.exception.code, 503)
        self.assertEqual(json.load(error.exception), {"status": "not-ready"})

    def test_readiness_failure_returns_bounded_503(self):
        with patch.object(self.proxy, "readiness", return_value=False):
            with self.assertRaises(HTTPError) as error:
                urlopen(self.base_url + "/readyz", timeout=2)
        self.assertEqual(error.exception.code, 503)
        self.assertEqual(json.load(error.exception), {"status": "not-ready"})

    def test_http_success_is_accepted_and_buffered(self):
        with self.post({"text": "✅ *watchdog* · news English · feed healthy"}) as response:
            self.assertEqual(response.status, 202)
            self.assertEqual(json.load(response), {"accepted": True})
        self.assertEqual(self.sent, [])

    def test_http_warning_is_committed_and_delivered(self):
        payload = {"text": "⚠️ *dispatch* · target · warning"}
        with self.post(payload) as response:
            self.assertEqual(response.status, 202)
        self.assertEqual(self.sent, [])
        self.proxy.process_deliveries()
        self.assertEqual(self.sent, [payload])
        self.assertEqual(len(self.proxy.events()), 1)

    def test_github_http_route_authenticates_accepts_and_deduplicates(self):
        payload = github_payload()
        for secret in (GITHUB_SECRET, GITHUB_PREVIOUS_SECRET):
            with self.subTest(secret=secret):
                with self.post_github(payload, secret=secret) as response:
                    self.assertEqual(response.status, 202)
                    self.assertEqual(json.load(response), {"accepted": True})
        self.assertEqual(len(self.proxy.events()), 1)
        self.assertEqual(len(self.proxy.deliveries()), 1)
        self.proxy.process_deliveries(self.current)
        self.assertEqual(len(self.sent), 1)

    def test_grafana_http_route_authenticates_accepts_and_deduplicates(self):
        self.server.max_request_bytes = 65536
        payload = grafana_payload()
        for secret in (GRAFANA_SECRET, GRAFANA_PREVIOUS_SECRET):
            with self.subTest(secret=secret):
                with self.post_grafana(payload, secret=secret) as response:
                    self.assertEqual(response.status, 202)
                    self.assertEqual(json.load(response), {"accepted": True})
        self.assertEqual(len(self.proxy.events()), 1)
        self.assertEqual(len(self.proxy.deliveries()), 1)

    def test_grafana_http_route_rejects_bad_auth_and_malformed_payload(self):
        self.server.max_request_bytes = 65536
        body = b"not-json-with-sensitive-content"
        timestamp = str(int(self.current.timestamp()))
        request = Request(
            self.base_url + "/v1/events/grafana",
            data=body,
            headers={
                "Content-Type": "application/json",
                "X-Grafana-Alerting-Timestamp": timestamp,
                "X-Grafana-Alerting-Signature": grafana_signature(
                    body, timestamp, "wrong-source-secret"
                ),
            },
            method="POST",
        )
        with self.assertRaises(HTTPError) as auth_error:
            urlopen(request, timeout=2)
        self.assertEqual(auth_error.exception.code, 401)
        with self.assertRaises(HTTPError) as payload_error:
            self.post_grafana({**grafana_payload(), "version": "2"})
        self.assertEqual(payload_error.exception.code, 422)
        with self.proxy._connect() as connection:
            rows = connection.execute(
                "SELECT source_id,category,reason FROM ingress_failures ORDER BY failure_id"
            ).fetchall()
        self.assertEqual(
            [tuple(row) for row in rows],
            [
                ("grafana", "auth", "invalid_signature"),
                ("grafana", "adapter", "invalid_payload"),
            ],
        )

    def test_external_credentials_cannot_impersonate_another_source(self):
        self.server.max_request_bytes = 65536
        github_body = json.dumps(github_payload(), separators=(",", ":")).encode()
        grafana_body = json.dumps(grafana_payload(), separators=(",", ":")).encode()
        timestamp = str(int(self.current.timestamp()))
        requests = (
            Request(
                self.base_url + "/v1/events/github-actions",
                data=github_body,
                headers={
                    "Content-Type": "application/json",
                    "X-FCC-Timestamp": timestamp,
                    "X-FCC-Signature": "sha256=" + grafana_signature(
                        github_body, timestamp
                    ),
                },
                method="POST",
            ),
            Request(
                self.base_url + "/v1/events/grafana",
                data=grafana_body,
                headers={
                    "Content-Type": "application/json",
                    "X-Grafana-Alerting-Timestamp": timestamp,
                    "X-Grafana-Alerting-Signature": hmac.new(
                        GITHUB_SECRET.encode(),
                        timestamp.encode() + b":" + grafana_body,
                        hashlib.sha256,
                    ).hexdigest(),
                },
                method="POST",
            ),
        )
        for request in requests:
            with self.assertRaises(HTTPError) as error:
                urlopen(request, timeout=2)
            self.assertEqual(error.exception.code, 401)
        self.assertEqual(self.proxy.events(), [])

    def test_github_http_route_rejects_bad_auth_before_json_parsing(self):
        body = b"not-json-with-sensitive-content"
        timestamp = str(int(self.current.timestamp()))
        request = Request(
            self.base_url + "/v1/events/github-actions",
            data=body,
            headers={
                "Content-Type": "application/json",
                "X-FCC-Timestamp": timestamp,
                "X-FCC-Signature": github_signature(body, timestamp, "wrong-source-secret"),
            },
            method="POST",
        )
        with self.assertRaises(HTTPError) as error:
            urlopen(request, timeout=2)
        self.assertEqual(error.exception.code, 401)
        self.assertEqual(json.load(error.exception), {"accepted": False})
        self.assertEqual(self.proxy.events(), [])
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM ingress_failures WHERE category='auth'"), 1)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM ingress_failures WHERE category='adapter'"), 0)

    def test_github_http_route_rejects_stale_and_missing_signatures(self):
        body = json.dumps(github_payload(), separators=(",", ":")).encode()
        stale = str(int((self.current - timedelta(minutes=6)).timestamp()))
        with self.assertRaises(HTTPError) as stale_error:
            self.post_github(body=body, timestamp=stale)
        self.assertEqual(stale_error.exception.code, 401)
        request = Request(
            self.base_url + "/v1/events/github-actions",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(HTTPError) as missing_error:
            urlopen(request, timeout=2)
        self.assertEqual(missing_error.exception.code, 401)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM ingress_failures WHERE category='auth'"), 2)

    def test_github_http_route_records_only_sanitized_adapter_failure(self):
        body = b"not-json"
        with self.assertRaises(HTTPError) as error:
            self.post_github(body=body)
        self.assertEqual(error.exception.code, 400)
        with self.proxy._connect() as connection:
            row = connection.execute(
                "SELECT source_id,category,reason FROM ingress_failures"
            ).fetchone()
        self.assertEqual(tuple(row), ("github-actions", "adapter", "invalid_json"))

    def test_github_http_route_rejects_duplicate_keys_and_nonfinite_numbers(self):
        for body in (
            b'{"schema":"fcc.github-actions-event/v1","schema":"duplicate"}',
            b'{"value":NaN}',
            b'{"value":1e999}',
            b'\xff',
        ):
            with self.subTest(body=body):
                with self.assertRaises(HTTPError) as error:
                    self.post_github(body=body)
                self.assertEqual(error.exception.code, 400)
        self.assertEqual(
            self.scalar("SELECT COUNT(*) FROM ingress_failures WHERE category='adapter'"),
            1,
        )

    def test_github_http_route_rejects_excessive_json_nesting(self):
        self.server.max_request_bytes = 32768
        body = b"[" * 10000 + b"]" * 10000
        with self.assertRaises(HTTPError) as error:
            self.post_github(body=body)
        self.assertEqual(error.exception.code, 400)

    def test_github_http_route_returns_conflict_for_changed_duplicate(self):
        payload = github_payload()
        with self.post_github(payload) as response:
            self.assertEqual(response.status, 202)
        with self.assertRaises(HTTPError) as error:
            self.post_github({**payload, "summary": "different semantic event"})
        self.assertEqual(error.exception.code, 409)
        self.assertEqual(json.load(error.exception), {"accepted": False})
        self.assertEqual(len(self.proxy.events()), 1)

    def test_github_http_route_rejects_ambiguous_framing_and_duplicate_auth_headers(self):
        body = json.dumps(github_payload(), separators=(",", ":")).encode()
        timestamp = str(int(self.current.timestamp()))
        signature = github_signature(body, timestamp)

        def raw_request(extra_headers):
            connection = http.client.HTTPConnection(
                "127.0.0.1", self.server.server_port, timeout=2
            )
            connection.putrequest("POST", "/v1/events/github-actions")
            connection.putheader("Content-Type", "application/json")
            for name, value in extra_headers:
                connection.putheader(name, value)
            connection.endheaders(body)
            response = connection.getresponse()
            status = response.status
            response.read()
            connection.close()
            return status

        common = [
            ("Content-Length", str(len(body))),
            ("X-FCC-Timestamp", timestamp),
            ("X-FCC-Signature", signature),
        ]
        self.assertEqual(
            raw_request(common + [("Content-Length", str(len(body)))]),
            400,
        )
        self.assertEqual(raw_request(common + [("Transfer-Encoding", "chunked")]), 400)
        self.assertEqual(
            raw_request(common + [("X-FCC-Signature", signature)]),
            401,
        )
        request = Request(
            self.base_url + "/v1/events/github-actions",
            data=body,
            headers={
                "Content-Type": "application/json",
                "Content-Encoding": "gzip",
                "X-FCC-Timestamp": timestamp,
                "X-FCC-Signature": signature,
            },
            method="POST",
        )
        with self.assertRaises(HTTPError) as encoding_error:
            urlopen(request, timeout=2)
        self.assertEqual(encoding_error.exception.code, 415)

    def test_github_http_route_is_unavailable_without_source_secret(self):
        self.proxy.github_secrets = ()
        body = json.dumps(github_payload(), separators=(",", ":")).encode()
        with self.assertRaises(HTTPError) as error:
            self.post_github(body=body)
        self.assertEqual(error.exception.code, 503)
        self.assertEqual(json.load(error.exception), {"accepted": False})

    def test_http_logs_redact_query_and_unknown_path_content(self):
        secret = "credential-must-not-appear"
        with self.assertLogs("chat-proxy", level="INFO") as captured:
            for path in (
                f"/v1/events/github-actions?token={secret}",
                f"/{secret}",
            ):
                with self.assertRaises(HTTPError) as error:
                    urlopen(self.base_url + path, timeout=2)
                self.assertEqual(error.exception.code, 404)
        rendered = "\n".join(captured.output)
        self.assertNotIn(secret, rendered)
        self.assertNotIn("token=", rendered)

    def test_internal_and_external_listeners_isolate_routes_and_health(self):
        internal = ProxyServer(
            ("127.0.0.1", 0),
            self.proxy,
            1024,
            allowed_post_paths=("/hooks/chat",),
        )
        external = ProxyServer(
            ("127.0.0.1", 0),
            self.proxy,
            1024,
            allowed_post_paths=("/v1/events/github-actions", "/v1/events/grafana"),
            expose_health=False,
        )
        threads = [
            threading.Thread(target=server.serve_forever, daemon=True)
            for server in (internal, external)
        ]
        for thread in threads:
            thread.start()
        try:
            internal_url = f"http://127.0.0.1:{internal.server_port}"
            external_url = f"http://127.0.0.1:{external.server_port}"
            internal_github = Request(
                internal_url + "/v1/events/github-actions",
                data=b"{}",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            internal_grafana = Request(
                internal_url + "/v1/events/grafana",
                data=b"{}",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            external_legacy = Request(
                external_url + "/hooks/chat",
                data=b"{}",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            for request in (
                internal_github,
                internal_grafana,
                external_legacy,
                external_url + "/readyz",
            ):
                with self.assertRaises(HTTPError) as error:
                    urlopen(request, timeout=2)
                self.assertEqual(error.exception.code, 404)
        finally:
            for server in (internal, external):
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join(2)

    def test_stalled_request_body_times_out(self):
        self.server.request_timeout = 0.1
        with socket.create_connection(("127.0.0.1", self.server.server_port), timeout=2) as client:
            client.sendall(
                b"POST /hooks/chat HTTP/1.1\r\n"
                b"Host: localhost\r\n"
                b"Content-Type: application/json\r\n"
                b"Content-Length: 10\r\n\r\n"
            )
            response = client.recv(4096)
        self.assertIn(b" 408 ", response)

    def test_http_validation(self):
        cases = (
            (b"not-json", "application/json", 400),
            (json.dumps({"other": "value"}).encode(), "application/json", 400),
            (b"{}", "text/plain", 415),
            (b"x" * 1025, "application/json", 413),
        )
        for body, content_type, status in cases:
            with self.subTest(status=status):
                with self.assertRaises(HTTPError) as error:
                    self.post_raw(body, content_type)
                self.assertEqual(error.exception.code, status)

    def test_http_storage_failure_returns_503(self):
        with patch.object(self.proxy, "_transaction", side_effect=sqlite3.OperationalError("full")):
            with self.assertLogs("chat-proxy", level="ERROR"):
                with self.assertRaises(HTTPError) as error:
                    self.post({"text": "🔴 *watchdog* · news English · failed"})
        self.assertEqual(error.exception.code, 503)
        self.assertEqual(json.load(error.exception), {"accepted": False})


class GrafanaConfigTests(unittest.TestCase):
    def test_grafana_uses_native_hmac_webhook_and_preserves_page_email(self):
        values = GRAFANA_VALUES.read_text(encoding="utf-8")
        self.assertIn("type: webhook", values)
        self.assertIn("url: $DEVOPS_ALERTS_GRAFANA_URL", values)
        self.assertIn("secret: $DEVOPS_ALERTS_GRAFANA_HMAC", values)
        self.assertIn("header: X-Grafana-Alerting-Signature", values)
        self.assertIn("timestampHeader: X-Grafana-Alerting-Timestamp", values)
        self.assertNotIn("type: googlechat", values)
        self.assertIn("receiver: ops-email", values)
        self.assertIn('[severity, "=", page]', values)
        self.assertIn("continue: true", values)


class ScheduleTests(unittest.TestCase):
    def test_schedule_matching(self):
        self.assertTrue(schedule_matches("0 30 1 * * 3,6", datetime(2026, 9, 30, 1, 30, tzinfo=UTC)))
        self.assertFalse(schedule_matches("0 30 1 * * 3,6", datetime(2026, 10, 1, 1, 30, tzinfo=UTC)))
        occurrences = occurrences_between(
            "0 5 */3 * * *",
            datetime(2026, 10, 1, 0, 5, tzinfo=UTC),
            datetime(2026, 10, 1, 9, 5, tzinfo=UTC),
        )
        self.assertEqual([item.hour for item in occurrences], [3, 6, 9])

    def test_expectation_schedules_match_stack_source_of_truth(self):
        service_schedules = {}
        current_service = None
        for line in STACK.read_text(encoding="utf-8").splitlines():
            if line.startswith("  ") and not line.startswith("    ") and line.endswith(":"):
                current_service = line.strip().removesuffix(":")
            marker = '"swarm.cronjob.schedule='
            if current_service and marker in line and not line.lstrip().startswith("#"):
                service_schedules[current_service] = line.split(marker, 1)[1].split('"', 1)[0]
        expectations = json.loads(EXPECTATIONS.read_text(encoding="utf-8"))
        expected_services = {
            "svc-dispatch-news-eng",
            "svc-dispatch-housekeeping",
            "svc-watchdog-news",
            "svc-update",
        }
        self.assertEqual({item["service"] for item in expectations}, expected_services)
        for expectation in expectations:
            self.assertEqual(service_schedules.get(expectation["service"]), expectation["schedule"], expectation["id"])


if __name__ == "__main__":
    unittest.main()
