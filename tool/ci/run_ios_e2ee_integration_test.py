#!/usr/bin/env python3
"""Run the iOS E2EE integration test and diagnose a stalled VM Service attach.

The Flutter test remains mandatory. If its iOS simulator app launches but the
VM Service URL is not observed, collect bounded host/simulator diagnostics and
fail instead of waiting for GitHub's generic step timeout.
"""

from __future__ import annotations

import os
import re
import select
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit


WAIT_MARKER = b"Waiting for VM Service port to be available"
VM_SERVICE_MARKERS = (
    b"VM Service URL on device:",
    b"Dart VM Service is listening on",
    b"The Dart VM Service is listening on",
)
DEFAULT_WAIT_TIMEOUT_SECONDS = 8 * 60
DEFAULT_TEST_TIMEOUT_SECONDS = 25 * 60
DIAGNOSTIC_OUTPUT_LIMIT = 40_000
VM_SERVICE_URI_RE = re.compile(
    rb"(?:VM Service URL on device:|Dart VM Service is listening on)\s*(https?://[^\s]+)"
)


def _probe_vm_service_uri(uri: str) -> str:
    try:
        parsed = urlsplit(uri)
        host = parsed.hostname
        port = parsed.port
    except ValueError as error:
        return f"[iOS VM Service host probe] invalid service URI: {error}"

    if host is None or port is None:
        return "[iOS VM Service host probe] discovered URI has no host/port."

    try:
        with socket.create_connection((host, port), timeout=1.0):
            return (
                "[iOS VM Service host probe] TCP connection succeeded to "
                f"{host}:{port}."
            )
    except OSError as error:
        return (
            "[iOS VM Service host probe] TCP connection failed to "
            f"{host}:{port}: {type(error).__name__}: {error}"
        )


def _run_diagnostic(
    title: str,
    command: list[str],
    *,
    timeout_seconds: int = 25,
) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        return f"[{title}] command timed out after {timeout_seconds}s\n{output}"
    except OSError as error:
        return f"[{title}] command could not run: {error}\n"

    output = (result.stdout or "") + (result.stderr or "")
    if len(output) > DIAGNOSTIC_OUTPUT_LIMIT:
        output = "[output truncated to final 40 KB]\n" + output[-DIAGNOSTIC_OUTPUT_LIMIT:]
    return f"[{title}] exit={result.returncode}\n{output}\n"


def _recent_crash_reports(simulator_id: str, app_bundle_id: str) -> str:
    simulator_logs = (
        Path.home()
        / "Library"
        / "Developer"
        / "CoreSimulator"
        / "Devices"
        / simulator_id
        / "data"
        / "Library"
        / "Logs"
    )
    roots = (
        Path.home() / "Library" / "Logs" / "DiagnosticReports",
        Path.home() / "Library" / "Logs" / "CrashReporter",
        simulator_logs / "CrashReporter",
        simulator_logs / "DiagnosticReports",
    )
    candidates: dict[Path, float] = {}
    errors: list[str] = []
    for root in roots:
        if not root.is_dir():
            continue
        command = [
            "find",
            str(root),
            "-type",
            "f",
            "-mmin",
            "-30",
            "(",
            "-iname",
            "*Runner*",
            "-o",
            "-iname",
            f"*{app_bundle_id}*",
            "-o",
            "-iname",
            "*ReportCrash*",
            ")",
            "-print",
        ]
        try:
            result = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            errors.append(f"find timed out for {root}")
            continue
        except OSError as error:
            errors.append(f"find could not run for {root}: {error}")
            continue
        if result.returncode != 0 and result.stderr.strip():
            errors.append(f"find failed for {root}: {result.stderr.strip()[:1000]}")
        for raw_path in result.stdout.splitlines():
            report = Path(raw_path)
            if report.suffix.lower() not in {".ips", ".crash", ".spin", ".hang", ".diag"}:
                continue
            try:
                candidates[report] = report.stat().st_mtime
            except OSError:
                continue

    if not candidates:
        details = "\n".join(errors)
        suffix = f"\n{details}" if details else ""
        return (
            "[recent Runner/Qayd crash reports] no matching files from the last "
            f"30 minutes.{suffix}"
        )

    output = ["[recent Runner/Qayd crash reports; newest first]"]
    for report, _ in sorted(
        candidates.items(), key=lambda item: item[1], reverse=True
    )[:5]:
        try:
            content = report.read_bytes()[:8_000].decode("utf-8", errors="replace")
        except OSError as error:
            output.append(f"{report}: could not read report: {error}")
            continue
        output.append(f"[crash report] {report}\n{content}")
    joined = "\n".join(output)
    if len(joined) > DIAGNOSTIC_OUTPUT_LIMIT:
        joined = (
            "[crash reports truncated to final 40 KB]\n"
            + joined[-DIAGNOSTIC_OUTPUT_LIMIT:]
        )
    return joined


def capture_diagnostics(simulator_id: str, app_bundle_id: str, cause: str) -> None:
    path = Path("artifacts/ios-e2ee-diagnostics.log")
    path.parent.mkdir(parents=True, exist_ok=True)
    commands: list[tuple[str, list[str]]] = [
        ("host OS", ["sw_vers"]),
        ("selected Xcode", ["xcodebuild", "-version"]),
        (
            "available simulator devices",
            ["xcrun", "simctl", "list", "devices", "available"],
        ),
        (
            "app installation",
            [
                "xcrun",
                "simctl",
                "get_app_container",
                simulator_id,
                app_bundle_id,
                "app",
            ],
        ),
        (
            "simulator launch services",
            ["xcrun", "simctl", "spawn", simulator_id, "launchctl", "list"],
        ),
        (
            "recent simulator and app unified logs",
            [
                "xcrun",
                "simctl",
                "spawn",
                simulator_id,
                "log",
                "show",
                "--last",
                "20m",
                "--style",
                "compact",
                "--predicate",
                (
                    f'process == "Runner" OR process == "{app_bundle_id}" '
                    'OR process == "ReportCrash" '
                    f'OR ((process == "runningboardd" OR process == "SpringBoard") '
                    f'AND (eventMessage CONTAINS[c] "{app_bundle_id}" '
                    'OR eventMessage CONTAINS[c] "Runner"))'
                ),
            ],
        ),
        ("host TCP listeners", ["lsof", "-nP", "-iTCP"]),
        ("host process table", ["ps", "-axo", "pid,ppid,etime,state,command"]),
    ]

    output = [
        "iOS E2EE simulator diagnostics",
        f"Cause: {cause}",
        f"UTC captured at: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}",
        f"Simulator UDID: {simulator_id}",
        f"App bundle ID: {app_bundle_id}",
        "",
    ]
    for title, command in commands:
        result = _run_diagnostic(title, command)
        if title == "simulator launch services":
            lines = result.splitlines()
            matching = [
                line
                for line in lines
                if app_bundle_id in line or "Runner" in line or "Flutter" in line
            ]
            result = "\n".join(lines[:1] + matching[-120:]) + "\n"
        elif title == "host TCP listeners":
            lines = result.splitlines()
            matching = [line for line in lines if "LISTEN" in line or line.startswith("[")]
            result = "\n".join(matching[-160:]) + "\n"
        elif title == "host process table":
            lines = result.splitlines()
            terms = (
                "Runner",
                "flutter_tester",
                "xcodebuild",
                "SWBBuildService",
                "simctl",
                "dart",
            )
            matching = [
                line
                for line in lines
                if line.startswith("[") or any(term in line for term in terms)
            ]
            result = "\n".join(matching[-160:]) + "\n"
        elif title == "recent simulator and app unified logs":
            result = "\n".join(result.splitlines()[-260:]) + "\n"
        output.append(result)

    output.append(_recent_crash_reports(simulator_id, app_bundle_id))
    content = "\n".join(output)
    path.write_text(content)
    print(content, flush=True)
    print(f"iOS diagnostics saved to {path}", flush=True)


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def main() -> int:
    simulator_id = os.environ.get("SIMULATOR_ID", "").strip()
    app_bundle_id = os.environ.get("APP_BUNDLE_ID", "com.accsystem.qayd").strip()
    timeout_seconds = int(
        os.environ.get(
            "IOS_VM_SERVICE_WAIT_TIMEOUT_SECONDS",
            str(DEFAULT_WAIT_TIMEOUT_SECONDS),
        )
    )
    test_timeout_seconds = int(
        os.environ.get(
            "IOS_INTEGRATION_TEST_TIMEOUT_SECONDS",
            str(DEFAULT_TEST_TIMEOUT_SECONDS),
        )
    )
    if not simulator_id:
        print("SIMULATOR_ID is required for the iOS integration test.", file=sys.stderr)
        return 2
    if timeout_seconds < 60:
        print("VM Service watchdog must be at least 60 seconds.", file=sys.stderr)
        return 2
    if test_timeout_seconds < timeout_seconds:
        print(
            "Integration test timeout must exceed the VM Service wait timeout.",
            file=sys.stderr,
        )
        return 2

    command = [
        "flutter",
        "test",
        "--verbose",
        # integration_test's golden comparator listens on DDS's extension-
        # specific VM Service stream. Direct VM Service mode rejects that
        # custom stream id and fails while loading the test, so keep DDS on.
        "--no-pub",
        "integration_test/e2ee_crypto_integration_test.dart",
        "--reporter",
        "expanded",
        "-d",
        simulator_id,
    ]
    print(
        "Running the required iOS E2EE integration test:",
        " ".join(command),
        flush=True,
    )
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
        start_new_session=True,
    )
    assert process.stdout is not None
    file_descriptor = process.stdout.fileno()
    log_buffer = bytearray()
    service_wait_started: float | None = None
    diagnostics_captured = False
    test_started = time.monotonic()
    artifact_log = Path("artifacts/ios-e2ee-integration.log")
    artifact_log.parent.mkdir(parents=True, exist_ok=True)

    with artifact_log.open("wb") as captured_log:
        while True:
            if process.poll() is not None:
                readable, _, _ = select.select([file_descriptor], [], [], 0)
                if not readable:
                    break
            readable, _, _ = select.select([file_descriptor], [], [], 1)
            if readable:
                chunk = os.read(file_descriptor, 8192)
                if not chunk:
                    break
                captured_log.write(chunk)
                captured_log.flush()
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
                log_buffer.extend(chunk)
                if len(log_buffer) > 64_000:
                    del log_buffer[:-32_000]
                if WAIT_MARKER in log_buffer and service_wait_started is None:
                    service_wait_started = time.monotonic()
                    marker_position = log_buffer.rfind(WAIT_MARKER)
                    del log_buffer[: marker_position + len(WAIT_MARKER)]
                    print(
                        f"\nVM Service attach watchdog started ({timeout_seconds}s).",
                        flush=True,
                    )
                if service_wait_started is not None and any(
                    marker in log_buffer for marker in VM_SERVICE_MARKERS
                ):
                    uri_match = VM_SERVICE_URI_RE.search(log_buffer)
                    if uri_match is not None:
                        probe_result = _probe_vm_service_uri(
                            uri_match.group(1).decode("ascii", errors="replace")
                        )
                        print(probe_result, flush=True)
                        captured_log.write((probe_result + "\n").encode())
                        captured_log.flush()
                    service_wait_started = None
                    log_buffer.clear()

            if (
                service_wait_started is not None
                and time.monotonic() - service_wait_started >= timeout_seconds
            ):
                cause = (
                    "Flutter launched the app but did not observe the VM Service URL "
                    f"within {timeout_seconds} seconds."
                )
                print(f"\n{cause} Collecting diagnostics before failing.", flush=True)
                capture_diagnostics(simulator_id, app_bundle_id, cause)
                diagnostics_captured = True
                _terminate_process_group(process)
                return 124

            if time.monotonic() - test_started >= test_timeout_seconds:
                cause = (
                    "The required Flutter integration test exceeded its "
                    f"{test_timeout_seconds}-second limit."
                )
                print(f"\n{cause} Collecting diagnostics before failing.", flush=True)
                capture_diagnostics(simulator_id, app_bundle_id, cause)
                diagnostics_captured = True
                _terminate_process_group(process)
                return 124

        return_code = process.wait()

    if return_code != 0 and not diagnostics_captured:
        capture_diagnostics(
            simulator_id,
            app_bundle_id,
            f"The required Flutter integration test exited with status {return_code}.",
        )
    return return_code


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
