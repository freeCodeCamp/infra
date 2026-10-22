import json
import tempfile
import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from chat_proxy import ChatProxy, ProxyServer, occurrences_between, parse_message, schedule_matches

UTC = timezone.utc
HERE = Path(__file__).resolve().parent
EXPECTATIONS = HERE / "cron-expectations.json"
STACK = HERE.parent / "stack-oncall.yml"


class ChatProxyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.sent = []

        def sender(payload):
            self.sent.append(payload)
            return True

        self.proxy = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            sender=sender,
        )

    def test_parses_standard_message_and_drops_link_from_summary(self):
        text = (
            "✅ *dispatch* · freeCodeCamp/news deploy-eng.yml · dispatch accepted · "
            "<https://example.test|runs>"
        )
        parsed = parse_message(text)
        self.assertEqual(parsed["status"], "ok")
        self.assertEqual(parsed["source"], "dispatch")
        self.assertEqual(parsed["subject"], "freeCodeCamp/news deploy-eng.yml")
        self.assertEqual(parsed["summary"], "dispatch accepted")

    def test_success_is_stored_without_forwarding(self):
        accepted, status = self.proxy.accept(
            {"text": "✅ *watchdog* · news English · feed healthy · <https://example.test|feed>"},
            datetime(2026, 10, 1, 12, 50, tzinfo=UTC),
        )
        self.assertTrue(accepted)
        self.assertEqual(status, 202)
        self.assertEqual(self.sent, [])
        records = self.proxy._records_for_day(date(2026, 10, 1))
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["summary"], "feed healthy")

    def test_warn_fail_and_unknown_are_forwarded(self):
        messages = [
            "⚠️ *dispatch* · target · warning",
            "🔴 *watchdog* · news English · failed",
            "plain unknown notice",
        ]
        for text in messages:
            self.proxy.accept({"text": text})
        self.assertEqual([item["text"] for item in self.sent], messages)

    def test_success_storage_failure_forwards_immediately(self):
        payload = {"text": "✅ *watchdog* · news English · feed healthy"}
        with self.assertLogs("chat-proxy", level="ERROR"):
            with patch.object(self.proxy, "_append_success", side_effect=OSError("read-only")):
                accepted, status = self.proxy.accept(payload)
        self.assertTrue(accepted)
        self.assertEqual(status, 202)
        self.assertEqual(self.sent, [payload])

    def test_non_text_payload_is_rejected(self):
        self.assertEqual(self.proxy.accept({"text": 42}), (False, 400))
        self.assertEqual(self.sent, [])

    def test_downstream_failure_does_not_fail_producer(self):
        self.proxy.sender = lambda _payload: False
        accepted, status = self.proxy.accept({"text": "🔴 *watchdog* · news English · failed"})
        self.assertTrue(accepted)
        self.assertEqual(status, 202)

    def test_digest_groups_records_and_omits_links(self):
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
        self.assertIn("feed healthy", text)
        self.assertNotIn("secret.test", text)
        self.assertFalse(self.proxy.send_digest(date(2026, 10, 1)))

    def test_empty_day_sends_no_digest(self):
        self.assertFalse(self.proxy.send_digest(date(2026, 10, 1)))
        self.assertEqual(self.sent, [])

    def test_digest_is_bounded(self):
        self.proxy.max_digest_chars = 160
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        self.proxy.accept(
            {"text": "✅ *watchdog* · news English · " + "healthy " * 40},
            moment,
        )
        self.assertTrue(self.proxy.send_digest(date(2026, 10, 1)))
        self.assertLessEqual(len(self.sent[-1]["text"]), 160)
        self.assertIn("digest truncated", self.sent[-1]["text"])

    def test_completed_digest_is_not_repeated_after_restart(self):
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        self.proxy.accept({"text": "✅ *watchdog* · news English · feed healthy"}, moment)
        self.assertTrue(self.proxy.send_digest(date(2026, 10, 1)))
        restarted = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            sender=lambda payload: self.sent.append(payload) or True,
        )
        self.assertFalse(restarted.send_digest(date(2026, 10, 1)))
        self.assertEqual(len(self.sent), 1)

    def test_scheduled_work_retries_an_older_undigested_day(self):
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        self.proxy.accept({"text": "✅ *watchdog* · news English · feed healthy"}, moment)
        self.proxy.scheduled_work(datetime(2026, 10, 3, 0, 1, tzinfo=UTC))
        self.assertEqual(len(self.sent), 1)
        self.assertIn("2026-10-01 UTC", self.sent[0]["text"])

    def test_failed_digest_is_retained_for_retry(self):
        moment = datetime(2026, 10, 1, 12, 50, tzinfo=UTC)
        self.proxy.accept({"text": "✅ *watchdog* · news English · feed healthy"}, moment)
        self.proxy.sender = lambda _payload: False
        self.assertFalse(self.proxy.send_digest(date(2026, 10, 1)))
        self.assertNotIn("2026-10-01", self.proxy.state["digested_dates"])
        self.assertEqual(len(self.proxy._records_for_day(date(2026, 10, 1))), 1)

    def test_late_digest_does_not_forget_newer_deliveries(self):
        self.proxy.state["digested_dates"] = [
            date(2026, 10, day).isoformat() for day in range(2, 9)
        ]
        self.proxy._success_path(date(2026, 10, 1)).write_text(
            json.dumps(
                {
                    "source": "watchdog",
                    "subject": "news English",
                    "summary": "feed healthy",
                }
            )
            + "\n",
            encoding="utf-8",
        )
        self.assertTrue(self.proxy.send_digest(date(2026, 10, 1)))
        self.assertIn("2026-10-02", self.proxy.state["digested_dates"])
        self.assertIn("2026-10-08", self.proxy.state["digested_dates"])

    def test_cleanup_keeps_seven_days(self):
        for offset in range(1, 9):
            day = date(2026, 10, 9) - timedelta(days=offset)
            self.proxy._success_path(day).write_text("{}\n", encoding="utf-8")
        self.proxy.cleanup(datetime(2026, 10, 9, tzinfo=UTC))
        self.assertFalse(self.proxy._success_path(date(2026, 10, 1)).exists())
        self.assertTrue(self.proxy._success_path(date(2026, 10, 2)).exists())

    def test_cron_initialization_does_not_alert_for_history(self):
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.assertEqual(self.sent, [])
        self.assertTrue(
            all("last_checked" in state for state in self.proxy.state["cron"].values())
        )

    def test_observed_tick_suppresses_alert_then_next_miss_alerts_once(self):
        self.proxy.expectations = [
            item for item in self.proxy.expectations if item["id"] == "watchdog-news"
        ]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.accept(
            {"text": "✅ *watchdog* · news English · feed healthy"},
            datetime(2026, 10, 1, 11, 51, tzinfo=UTC),
        )
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.assertEqual(self.sent, [])
        self.proxy.check_crons(datetime(2026, 10, 1, 13, 6, tzinfo=UTC))
        self.assertEqual(len(self.sent), 1)
        self.assertIn("expected tick 2026-10-01 12:50 UTC", self.sent[0]["text"])
        self.proxy.check_crons(datetime(2026, 10, 1, 13, 10, tzinfo=UTC))
        self.assertEqual(len(self.sent), 1)

    def test_multiple_observations_match_multiple_pending_occurrences(self):
        self.proxy.expectations = [
            item for item in self.proxy.expectations if item["id"] == "watchdog-news"
        ]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        for hour in (11, 12):
            self.proxy.accept(
                {"text": "✅ *watchdog* · news English · feed healthy"},
                datetime(2026, 10, 1, hour, 51, tzinfo=UTC),
            )
        self.proxy.check_crons(datetime(2026, 10, 1, 13, 6, tzinfo=UTC))
        self.assertEqual(self.sent, [])

    def test_failure_also_counts_as_observed_tick(self):
        self.proxy.expectations = [
            item for item in self.proxy.expectations if item["id"] == "watchdog-news"
        ]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.accept(
            {"text": "🔴 *watchdog* · news English · feed unreadable"},
            datetime(2026, 10, 1, 11, 51, tzinfo=UTC),
        )
        self.assertEqual(len(self.sent), 1)
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.assertEqual(len(self.sent), 1)

    def test_failed_missed_tick_delivery_is_retried(self):
        self.proxy.expectations = [
            item for item in self.proxy.expectations if item["id"] == "watchdog-news"
        ]
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        attempts = []
        self.proxy.sender = lambda payload: attempts.append(payload) and False
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        self.proxy.sender = lambda payload: attempts.append(payload) or True
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 7, tzinfo=UTC))
        self.assertEqual(len(attempts), 2)
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 8, tzinfo=UTC))
        self.assertEqual(len(attempts), 2)

    def test_cron_state_survives_restart(self):
        self.proxy.check_crons(datetime(2026, 10, 1, 11, 6, tzinfo=UTC))
        self.proxy.check_crons(datetime(2026, 10, 1, 12, 6, tzinfo=UTC))
        alerts = len(self.sent)
        restarted = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            sender=lambda payload: self.sent.append(payload) or True,
        )
        restarted.check_crons(datetime(2026, 10, 1, 12, 10, tzinfo=UTC))
        self.assertEqual(len(self.sent), alerts)


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.sent = []
        proxy = ChatProxy(
            "https://chat.invalid/secret",
            self.temporary.name,
            EXPECTATIONS,
            sender=lambda payload: self.sent.append(payload) or True,
        )
        self.server = ProxyServer(("127.0.0.1", 0), proxy, 1024)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def post_raw(self, body):
        request = Request(
            self.base_url + "/hooks/chat",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        return urlopen(request, timeout=2)

    def post(self, payload):
        return self.post_raw(json.dumps(payload).encode())

    def test_health_endpoint(self):
        with urlopen(self.base_url + "/healthz", timeout=2) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(json.load(response), {"status": "ok"})

    def test_http_success_is_accepted_and_buffered(self):
        with self.post({"text": "✅ *watchdog* · news English · feed healthy"}) as response:
            self.assertEqual(response.status, 202)
        self.assertEqual(self.sent, [])

    def test_http_warning_is_accepted_and_forwarded(self):
        payload = {"text": "⚠️ *dispatch* · target · warning"}
        with self.post(payload) as response:
            self.assertEqual(response.status, 202)
        self.assertEqual(self.sent, [payload])

    def test_http_rejects_payload_without_text(self):
        with self.assertRaises(HTTPError) as error:
            self.post({"other": "value"})
        self.assertEqual(error.exception.code, 400)

    def test_http_rejects_malformed_json(self):
        with self.assertRaises(HTTPError) as error:
            self.post_raw(b"not-json")
        self.assertEqual(error.exception.code, 400)

    def test_http_rejects_oversized_payload(self):
        with self.assertRaises(HTTPError) as error:
            self.post_raw(b"x" * 1025)
        self.assertEqual(error.exception.code, 413)


class ScheduleTests(unittest.TestCase):
    def test_schedule_matching(self):
        self.assertTrue(
            schedule_matches("0 30 1 * * 3,6", datetime(2026, 9, 30, 1, 30, tzinfo=UTC))
        )
        self.assertFalse(
            schedule_matches("0 30 1 * * 3,6", datetime(2026, 10, 1, 1, 30, tzinfo=UTC))
        )
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
            self.assertEqual(
                service_schedules.get(expectation["service"]),
                expectation["schedule"],
                expectation["id"],
            )


if __name__ == "__main__":
    unittest.main()
