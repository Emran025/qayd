#!/usr/bin/env python3
"""Backport Flutter PR #193142's iOS Simulator VM-service log-reader fix.

Flutter 3.44.5 can launch an iOS simulator app before `simctl log stream`
starts consuming output, thereby missing the one-time Dart VM Service URL.
This script applies the upstream readiness handshake to the CI-only Flutter
SDK checkout and directly rebuilds the cached tool snapshot using the SDK's
already-resolved package configuration. It is strict and idempotent so SDK
source drift fails closed rather than changing unrelated Flutter code.
"""

from __future__ import annotations

import os
import shlex
import subprocess
from pathlib import Path


FLUTTER_ROOT = Path(os.environ["FLUTTER_ROOT"])
EXPECTED_FLUTTER_VERSION = os.environ.get("FLUTTER_VERSION", "3.44.5")
SOURCE = FLUTTER_ROOT / "packages/flutter_tools/lib/src/ios/simulators.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected one Flutter source match for {label}; found {count}.")
    return text.replace(old, new, 1)


def apply_source_backport(source: str) -> str:
    if (
        "await logReader._ready.future;" in source
        and "final _logReaders = <IOSApp?, _IOSSimulatorLogReader>{};" in source
        and "_IOSSimulatorLogReader getLogReader(" in source
    ):
        print("Flutter iOS simulator log-reader source fix is already present.")
        return source

    source = replace_once(
        source,
        """    ProtocolDiscovery? vmServiceDiscovery;
    if (debuggingOptions.debuggingEnabled) {
      vmServiceDiscovery = ProtocolDiscovery.vmService(
        getLogReader(app: package),
        ipv6: debuggingOptions.ipv6,
        hostPort: debuggingOptions.hostVmServicePort,
        devicePort: debuggingOptions.deviceVmServicePort,
        logger: globals.logger,
      );
    }
""",
        """    ProtocolDiscovery? vmServiceDiscovery;
    if (debuggingOptions.debuggingEnabled) {
      final _IOSSimulatorLogReader logReader = getLogReader(app: package);
      vmServiceDiscovery = ProtocolDiscovery.vmService(
        logReader,
        ipv6: debuggingOptions.ipv6,
        hostPort: debuggingOptions.hostVmServicePort,
        devicePort: debuggingOptions.deviceVmServicePort,
        logger: globals.logger,
      );
      // Do not launch until `simctl log stream` is ready, or its first-line
      // handshake can race with and miss the VM Service URL emitted at startup.
      const warningDelay = Duration(seconds: 30);
      final timer = Timer(warningDelay, () {
        globals.printError(
          'The iOS simulator log stream did not start after ${warningDelay.inSeconds} seconds. '
          'This is taking much longer than expected...',
        );
      });
      await logReader._ready.future;
      timer.cancel();
    }
""",
        "startApp VM-service discovery",
    )

    source = replace_once(
        source,
        """  late final _linesController = StreamController<String>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
""",
        """  late final _linesController = StreamController<String>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );

  /// Completes when the simulator log stream is ready to deliver events.
  var _ready = Completer<void>();
""",
        "log-reader readiness completer",
    )

    source = replace_once(
        source,
        """  final _logReaders = <IOSApp?, DeviceLogReader>{};
""",
        """  final _logReaders = <IOSApp?, _IOSSimulatorLogReader>{};
""",
        "iOS simulator log-reader cache type",
    )

    source = replace_once(
        source,
        """  DeviceLogReader getLogReader({covariant IOSApp? app, bool includePastLogs = false}) {
""",
        """  _IOSSimulatorLogReader getLogReader({covariant IOSApp? app, bool includePastLogs = false}) {
""",
        "iOS simulator log-reader return type",
    )

    source = replace_once(
        source,
        """  Future<void> _start() async {
    // Unified logging iOS 11 and greater (introduced in iOS 10).
""",
        """  Future<void> _start() async {
    // Each listen starts a new log process; capture this cycle's completer so
    // a late exit from an older process cannot complete the new cycle.
    _ready = Completer<void>();
    final Completer<void> ready = _ready;
    // Unified logging iOS 11 and greater (introduced in iOS 10).
""",
        "log-reader listen initialization",
    )

    source = replace_once(
        source,
        """      _deviceProcess?.stdout.transform(utf8LineDecoder).listen(_onUnifiedLoggingLine);
""",
        """      _deviceProcess?.stdout.transform(utf8LineDecoder).listen((String line) {
        if (!ready.isCompleted) {
          ready.complete();
        }
        _onUnifiedLoggingLine(line);
      });
""",
        "unified log first-line readiness",
    )

    source = replace_once(
        source,
        """      _deviceProcess?.exitCode.whenComplete(() {
        if (_linesController.hasListener) {
""",
        """      _deviceProcess?.exitCode.whenComplete(() {
        if (!ready.isCompleted) {
          ready.complete();
        }
        if (_linesController.hasListener) {
""",
        "log-process exit readiness",
    )
    return source


def rebuild_flutter_tool_snapshot() -> None:
    version_file = FLUTTER_ROOT / "version"
    if version_file.is_file():
        actual_version = version_file.read_text().strip()
        if actual_version != EXPECTED_FLUTTER_VERSION:
            raise SystemExit(
                f"Expected pinned Flutter {EXPECTED_FLUTTER_VERSION}, found {actual_version!r}."
            )

    revision = subprocess.run(
        ["git", "-C", str(FLUTTER_ROOT), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    tool_args = os.environ.get("FLUTTER_TOOL_ARGS", "")
    compile_key = f"{revision}:{tool_args}"

    cache = FLUTTER_ROOT / "bin/cache"
    snapshot = cache / "flutter_tools.snapshot"
    stamp = cache / "flutter_tools.stamp"
    snapshot.unlink(missing_ok=True)
    stamp.unlink(missing_ok=True)

    tools_dir = FLUTTER_ROOT / "packages/flutter_tools"
    dart = FLUTTER_ROOT / "bin/cache/dart-sdk/bin/dart"
    package_config = tools_dir / ".dart_tool/package_config.json"
    entrypoint = tools_dir / "bin/flutter_tools.dart"
    for required in (dart, package_config, entrypoint):
        if not required.is_file():
            raise SystemExit(f"Missing Flutter tool bootstrap input: {required}")

    command = [
        str(dart),
        "--verbosity=error",
        *shlex.split(tool_args),
        f"--snapshot={snapshot}",
        "--snapshot-kind=app-jit",
        f"--packages={package_config}",
        "--no-enable-mirrors",
        str(entrypoint),
    ]
    print("Rebuilding the pinned Flutter tool snapshot directly from resolved SDK packages.")
    subprocess.run(command, cwd=FLUTTER_ROOT, check=True)
    if not snapshot.is_file():
        raise SystemExit("Flutter tool snapshot compilation completed without creating a snapshot.")
    stamp.write_text(compile_key)
    print(f"Rebuilt the Flutter tool snapshot from Flutter {EXPECTED_FLUTTER_VERSION} source.")


source = SOURCE.read_text()
patched_source = apply_source_backport(source)
if patched_source != source:
    SOURCE.write_text(patched_source)
    print(f"Applied Flutter PR #193142 iOS simulator log-reader fix to {SOURCE}.")
rebuild_flutter_tool_snapshot()
