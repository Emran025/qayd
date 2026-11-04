#!/usr/bin/env python3
"""Backport Flutter PR #193142's iOS Simulator VM-service log-reader fix.

Flutter 3.44.5 can launch an iOS simulator app before `simctl log stream`
starts consuming output, thereby missing the one-time Dart VM Service URL.
This script applies the upstream readiness handshake to the CI-only Flutter
SDK checkout, then rebuilds Flutter's cached tool snapshot. It is intentionally
strict and idempotent so SDK drift fails closed instead of changing unrelated
Flutter source silently.
"""

from __future__ import annotations

import json
import os
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
    if "await logReader._ready.future;" in source:
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
    cache = FLUTTER_ROOT / "bin/cache"
    (cache / "flutter_tools.snapshot").unlink(missing_ok=True)
    (cache / "flutter_tools.stamp").unlink(missing_ok=True)

    flutter = FLUTTER_ROOT / "bin/flutter"
    result = subprocess.run(
        [str(flutter), "--version", "--machine"],
        cwd=FLUTTER_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    version_info = json.loads(result.stdout)
    actual_version = version_info.get("frameworkVersion")
    if actual_version != EXPECTED_FLUTTER_VERSION:
        raise SystemExit(
            f"Expected pinned Flutter {EXPECTED_FLUTTER_VERSION}, found {actual_version!r}."
        )
    print(f"Rebuilt Flutter tool snapshot with Flutter {actual_version}.")


source = SOURCE.read_text()
patched_source = apply_source_backport(source)
if patched_source != source:
    SOURCE.write_text(patched_source)
    print(f"Applied Flutter PR #193142 iOS simulator log-reader fix to {SOURCE}.")
rebuild_flutter_tool_snapshot()
