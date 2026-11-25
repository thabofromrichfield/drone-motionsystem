#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The safety gate is platform-independent; isolate the enum from Android imports.
printf 'package drone.test.core\nenum class UavLinkState { IDLE, REGISTERING, NO_KEY, KEY_REJECTED, LINKED, STANDBY }\n' > "$tmp/UavLinkState.kt"
kotlinc "$root/app/src/main/java/drone/test/core/Telemetry.kt" \
  "$root/app/src/main/java/drone/test/core/DispatchSafety.kt" \
  "$tmp/UavLinkState.kt" "$root/tests/DispatchSafetyTest.kt" \
  -include-runtime -d "$tmp/test.jar"
java -jar "$tmp/test.jar"
