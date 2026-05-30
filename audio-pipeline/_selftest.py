"""Offline self-test for the Penlo pipeline.

Mocks the Anthropic client and the HTTP layer so every state path can be
exercised deterministically without real API keys or network access.

Run:  python _selftest.py
"""

from __future__ import annotations

import json
import tempfile
import time
from pathlib import Path

import requests as real_requests

import pipeline as P
from pipeline import Config, SyncResult

FAILURES: list[str] = []


def check(name: str, condition: bool, extra: str = "") -> None:
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {name}" + (f" — {extra}" if extra else ""))
    if not condition:
        FAILURES.append(name)


# ---------------------------------------------------------------------------
# Test doubles
# ---------------------------------------------------------------------------

class _Block:
    def __init__(self, text: str) -> None:
        self.type = "text"
        self.text = text


class _Resp:
    def __init__(self, text: str) -> None:
        self.content = [_Block(text)]


class _Messages:
    def __init__(self, text: str) -> None:
        self._text = text

    def create(self, **_kwargs):
        return _Resp(self._text)


class FakeClient:
    """Stands in for anthropic.Anthropic; returns a fixed text body."""

    def __init__(self, text: str) -> None:
        self.messages = _Messages(text)


class FakeResponse:
    def __init__(self, status_code: int, text: str = "ok") -> None:
        self.status_code = status_code
        self.text = text


class FakeRequests:
    """Replaces the `requests` module inside pipeline; .post is swappable."""

    exceptions = real_requests.exceptions
    _post_fn = staticmethod(lambda *a, **k: FakeResponse(200))

    @classmethod
    def post(cls, *args, **kwargs):
        return cls._post_fn(*args, **kwargs)


VALID_JSON = json.dumps(
    {
        "facts": [
            {
                "subject": "Sarah Chen",
                "predicate": "is working on",
                "object": "API rate limiter",
                "confidence": 0.82,
            }
        ],
        "people": [
            {"name": "Sarah Chen", "email": None, "phone": None, "notes": "Owns rate limiter"}
        ],
        "topicSummary": ["API rate limiter"],
    }
)

BAD_CONFIDENCE_JSON = json.dumps(
    {
        "facts": [
            {"subject": "X", "predicate": "is", "object": "y", "confidence": 0.99}
        ],
        "people": [],
        "topicSummary": [],
    }
)

FENCED_JSON = f"```json\n{VALID_JSON}\n```"


# ---------------------------------------------------------------------------
# Sandbox harness
# ---------------------------------------------------------------------------

def make_sandbox() -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="penlo_test_"))
    for name in ("transcripts", "output", "processed", "failed", "queue"):
        (tmp / name).mkdir()
    P.TRANSCRIPTS_DIR = tmp / "transcripts"
    P.OUTPUT_DIR = tmp / "output"
    P.PROCESSED_DIR = tmp / "processed"
    P.FAILED_DIR = tmp / "failed"
    P.QUEUE_DIR = tmp / "queue"
    P.ALL_DIRS = (P.TRANSCRIPTS_DIR, P.OUTPUT_DIR, P.PROCESSED_DIR, P.FAILED_DIR, P.QUEUE_DIR)
    return tmp


def make_config(llm_text: str, sync_enabled: bool = True) -> Config:
    return Config(
        client=FakeClient(llm_text),
        penlo_api_key="pb_live_testkey",
        user_email="tester@penlo.ai",
        sync_enabled=sync_enabled,
    )


def write_transcript(name: str, body: str = "Sarah Chen is working on the rate limiter.") -> Path:
    path = P.TRANSCRIPTS_DIR / name
    path.write_text(body, encoding="utf-8")
    return path


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_capture_time() -> None:
    print("\n== Milestone 2: capture-time resolution ==")
    iso = P.get_actual_capture_time("20260529_143000_meeting.txt")
    check("structured filename parsed to UTC", iso == "2026-05-29T14:30:00+00:00", iso)

    sandbox_file = P.TRANSCRIPTS_DIR / "no_prefix_here.txt"
    sandbox_file.write_text("hi", encoding="utf-8")
    iso2 = P.get_actual_capture_time(sandbox_file)
    check("fallback to mtime yields UTC ISO", iso2.endswith("+00:00"), iso2)
    sandbox_file.unlink()


def test_fence_stripping() -> None:
    print("\n== Helper: markdown fence stripping ==")
    cleaned = P.strip_markdown_fences(FENCED_JSON)
    ok = json.loads(cleaned)["facts"][0]["subject"] == "Sarah Chen"
    check("```json fences stripped + parses", ok)


def test_success_sync() -> None:
    print("\n== M3/M4: success -> SYNCED (200) ==")
    cfg = make_config(VALID_JSON)
    FakeRequests._post_fn = staticmethod(lambda *a, **k: FakeResponse(200))
    t = write_transcript("20260529_090000_sync_ok.txt")
    status = P.process_single_file(cfg, t)
    stem = "20260529_090000_sync_ok"
    check("status == SYNCED", status == "SYNCED", status)
    check("output payload written", (P.OUTPUT_DIR / f"{stem}_payload.json").exists())
    check("transcript moved to processed/", (P.PROCESSED_DIR / f"{stem}.txt").exists())
    check("queue empty", not (P.QUEUE_DIR / f"{stem}_payload.json").exists())
    # Verify capturedAt used the filename time, not "now".
    payload = json.loads((P.OUTPUT_DIR / f"{stem}_payload.json").read_text())
    check(
        "fact capturedAt == filename time",
        payload["facts"][0]["capturedAt"] == "2026-05-29T09:00:00+00:00",
        payload["facts"][0]["capturedAt"],
    )
    check("userEmail injected from env", payload["userEmail"] == "tester@penlo.ai")
    check("schemaVersion is 1.1", payload["schemaVersion"] == "1.1")


def test_server_error_queue() -> None:
    print("\n== M4: server 500 -> QUEUED ==")
    cfg = make_config(VALID_JSON)
    FakeRequests._post_fn = staticmethod(lambda *a, **k: FakeResponse(500, "boom"))
    t = write_transcript("server_err.txt")
    status = P.process_single_file(cfg, t)
    check("status == QUEUED", status == "QUEUED", status)
    check("payload buffered in queue/", (P.QUEUE_DIR / "server_err_payload.json").exists())
    check("transcript archived to processed/", (P.PROCESSED_DIR / "server_err.txt").exists())


def test_network_error_queue() -> None:
    print("\n== M4: network error -> QUEUED ==")
    cfg = make_config(VALID_JSON)

    def boom(*a, **k):
        raise real_requests.exceptions.ConnectionError("offline")

    FakeRequests._post_fn = staticmethod(boom)
    t = write_transcript("net_err.txt")
    status = P.process_single_file(cfg, t)
    check("status == QUEUED", status == "QUEUED", status)
    check("payload buffered in queue/", (P.QUEUE_DIR / "net_err_payload.json").exists())


def test_auth_failure_queue() -> None:
    print("\n== M3: auth 401 -> QUEUED (critical) ==")
    cfg = make_config(VALID_JSON)
    FakeRequests._post_fn = staticmethod(lambda *a, **k: FakeResponse(401, "bad key"))
    t = write_transcript("auth_err.txt")
    status = P.process_single_file(cfg, t)
    check("status == QUEUED", status == "QUEUED", status)
    check("payload buffered in queue/", (P.QUEUE_DIR / "auth_err_payload.json").exists())


def test_rate_limit_backoff_then_success() -> None:
    print("\n== M3: 429 backoff then 200 -> SYNCED (no real sleeping) ==")
    cfg = make_config(VALID_JSON)
    calls = {"n": 0}

    def flaky(*a, **k):
        calls["n"] += 1
        return FakeResponse(429) if calls["n"] == 1 else FakeResponse(200)

    FakeRequests._post_fn = staticmethod(flaky)
    orig_sleep = P.time.sleep
    P.time.sleep = lambda *_a, **_k: None  # neutralize backoff sleeps
    try:
        t = write_transcript("rate_then_ok.txt")
        status = P.process_single_file(cfg, t)
    finally:
        P.time.sleep = orig_sleep
    check("status == SYNCED after backoff", status == "SYNCED", status)
    check("retried at least twice", calls["n"] >= 2, f"calls={calls['n']}")


def test_rate_limit_exhausted_queue() -> None:
    print("\n== M3: persistent 429 exhausts schedule -> QUEUED ==")
    cfg = make_config(VALID_JSON)
    FakeRequests._post_fn = staticmethod(lambda *a, **k: FakeResponse(429))
    orig_sleep = P.time.sleep
    P.time.sleep = lambda *_a, **_k: None
    try:
        t = write_transcript("always_429.txt")
        status = P.process_single_file(cfg, t)
    finally:
        P.time.sleep = orig_sleep
    check("status == QUEUED", status == "QUEUED", status)
    check("payload buffered in queue/", (P.QUEUE_DIR / "always_429_payload.json").exists())


def test_validation_failure() -> None:
    print("\n== M4: invalid confidence -> FAILED + error log ==")
    cfg = make_config(BAD_CONFIDENCE_JSON)
    t = write_transcript("bad_conf.txt")
    status = P.process_single_file(cfg, t)
    check("status == FAILED", status == "FAILED", status)
    check("transcript moved to failed/", (P.FAILED_DIR / "bad_conf.txt").exists())
    check("error log written", (P.FAILED_DIR / "bad_conf.error.txt").exists())
    check("no output payload", not (P.OUTPUT_DIR / "bad_conf_payload.json").exists())
    log = (P.FAILED_DIR / "bad_conf.error.txt").read_text()
    check("error log mentions ValidationError", "ValidationError" in log)


def test_extraction_failure() -> None:
    print("\n== M4: non-JSON model output -> FAILED ==")
    cfg = make_config("I am not JSON at all, sorry!")
    t = write_transcript("bad_json.txt")
    status = P.process_single_file(cfg, t)
    check("status == FAILED", status == "FAILED", status)
    check("error log written", (P.FAILED_DIR / "bad_json.error.txt").exists())


def test_no_sync_mode() -> None:
    print("\n== M3: --no-sync mode -> QUEUED without network ==")
    cfg = make_config(VALID_JSON, sync_enabled=False)

    def must_not_call(*a, **k):
        raise AssertionError("network called in --no-sync mode!")

    FakeRequests._post_fn = staticmethod(must_not_call)
    t = write_transcript("local_only.txt")
    status = P.process_single_file(cfg, t)
    check("status == QUEUED", status == "QUEUED", status)
    check("payload buffered in queue/", (P.QUEUE_DIR / "local_only_payload.json").exists())


def test_retry_queue_drain() -> None:
    print("\n== M4: retry_queue drains buffered payloads ==")
    cfg = make_config(VALID_JSON)
    # Seed the queue with a payload directly.
    P.write_queue(json.loads(VALID_JSON), "seeded")
    check("seed exists", (P.QUEUE_DIR / "seeded_payload.json").exists())
    FakeRequests._post_fn = staticmethod(lambda *a, **k: FakeResponse(200))
    P.retry_queue(cfg)
    check("queue drained after 200", not (P.QUEUE_DIR / "seeded_payload.json").exists())


def test_file_stability() -> None:
    print("\n== M1 helper: wait_for_file_stable ==")
    f = P.TRANSCRIPTS_DIR / "stable.txt"
    f.write_text("done", encoding="utf-8")
    ok = P.wait_for_file_stable(f, stable_checks=2, interval=0.05, timeout=2.0)
    check("stable file detected", ok)
    f.unlink()


def test_watcher_integration() -> None:
    print("\n== M1: live watchdog observer processes a dropped file ==")
    cfg = make_config(VALID_JSON)
    FakeRequests._post_fn = staticmethod(lambda *a, **k: FakeResponse(200))

    observer = P.Observer()
    handler = P.TranscriptHandler(cfg)
    observer.schedule(handler, path=str(P.TRANSCRIPTS_DIR), recursive=False)
    observer.start()
    try:
        time.sleep(0.3)
        # Atomic-ish create so on_created fires after content is present.
        target = P.TRANSCRIPTS_DIR / "20260529_120000_watched.txt"
        target.write_text("Sarah Chen owns the dashboard.", encoding="utf-8")
        # Give the observer + stability poll time to run.
        deadline = time.time() + 8
        out = P.OUTPUT_DIR / "20260529_120000_watched_payload.json"
        while time.time() < deadline and not out.exists():
            time.sleep(0.2)
    finally:
        observer.stop()
        observer.join()
    check("watcher produced output payload", out.exists())
    check(
        "watched transcript archived to processed/",
        (P.PROCESSED_DIR / "20260529_120000_watched.txt").exists(),
    )


def main() -> int:
    make_sandbox()
    P.requests = FakeRequests  # Patch network layer inside the pipeline module.

    test_capture_time()
    test_fence_stripping()
    test_success_sync()
    test_server_error_queue()
    test_network_error_queue()
    test_auth_failure_queue()
    test_rate_limit_backoff_then_success()
    test_rate_limit_exhausted_queue()
    test_validation_failure()
    test_extraction_failure()
    test_no_sync_mode()
    test_retry_queue_drain()
    test_file_stability()
    test_watcher_integration()

    print("\n" + "=" * 60)
    if FAILURES:
        print(f"RESULT: {len(FAILURES)} FAILURE(S): {FAILURES}")
        return 1
    print("RESULT: ALL TESTS PASSED ✅")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
