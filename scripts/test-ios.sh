#!/usr/bin/env bash
# Ejecuta los tests de la app en el simulador de iPhone más reciente disponible.
# Requiere macOS con Xcode y el proyecto generado (`xcodegen generate`).
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"], device["udid"]))
candidates.sort()
print(candidates[-1][2] if candidates else "")
')"

if [[ -z "$DEVICE_ID" ]]; then
  echo "No hay ningún simulador de iPhone disponible." >&2
  exit 1
fi
echo "Simulador: $DEVICE_ID"
mkdir -p build

xcodebuild test \
  -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData-tests \
  -resultBundlePath build/TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  | tee build/xcodebuild-test.log \
  | grep -E "error:|warning: .*GymTracker|Test Case .* (passed|failed)|Executed|\*\* TEST" || true

# `grep` no debe ocultar un fallo de xcodebuild.
exit "${PIPESTATUS[0]}"
