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
from urllib.request import Request, urlopen

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
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 1)
            self.assertEqual(connection.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0], 1)
            self.assertEqual(connection.execute("PRAGMA journal_mode").fetchone()[0], "wal")
            self.assertEqual(connection.execute("PRAGMA foreign_keys").fetchone()[0], 1)
            self.assertEqual(connection.execute("PRAGMA busy_timeout").fetchone()[0], 5000)
            self.assertEqual(connection.execute("PRAGMA quick_check").fetchone()[0], "ok")
        self.assertEqual(self.proxy.database_path.stat().st_mode & 0o777, 0o600)
        restarted = ChatProxy("", self.temporary.name, EXPECTATIONS, sender=lambda _payload: True)
        self.assertEqual(len(restarted.events()), 1)

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

    def test_secret_file_takes_precedence(self):
        secret = Path(self.temporary.name) / "secret"
        secret.write_text("from-file\n", encoding="utf-8")
        with patch.dict("os.environ", {"TOKEN": "from-env", "TOKEN_FILE": str(secret)}):
            self.assertEqual(read_secret("TOKEN"), "from-file")


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.sent = []
        self.proxy = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            sender=lambda payload: self.sent.append(payload) or True,
            jitter=lambda: 1,
        )
        self.server = ProxyServer(("127.0.0.1", 0), self.proxy, 1024)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

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
