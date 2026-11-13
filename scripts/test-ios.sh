#!/usr/bin/env bash
# Ejecuta los tests de la app en un simulador de iPhone cuya versión coincide con el SDK
# del Xcode activo. Requiere macOS con Xcode y el proyecto generado (`xcodegen generate`).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
echo "SDK del simulador: iOS $SDK_VERSION"

DEVICE_ID="$(xcrun simctl list devices available -j | SDK_VERSION="$SDK_VERSION" python3 -c '
import json, os, re, sys
sdk = tuple(int(p) for p in os.environ["SDK_VERSION"].split(".")[:2])
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    if version > sdk:
        continue  # runtimes más nuevos que el SDK funcionan peor y arrancan más lento
    for device in entries:
        name = device["name"]
        if not (device.get("isAvailable") and name.startswith("iPhone")):
            continue
        model = re.fullmatch(r"iPhone (\d+)", name)
        # Preferir el runtime más cercano al SDK y un iPhone estándar reciente.
        candidates.append((version, 1 if model else 0, int(model.group(1)) if model else 0, name, device["udid"]))
candidates.sort()
if candidates:
    best = candidates[-1]
    print(best[4])
    print("Elegido: %s (iOS %d.%d)" % (best[3], best[0][0], best[0][1]), file=sys.stderr)
')"

if [[ -z "$DEVICE_ID" ]]; then
  echo "No hay ningún simulador de iPhone compatible con iOS $SDK_VERSION." >&2
  exit 1
fi

echo "Arrancando simulador $DEVICE_ID..."
SECONDS=0
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
echo "Simulador listo en ${SECONDS}s"

set +e
xcodebuild test \
  -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData-tests \
  -resultBundlePath build/TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  > build/xcodebuild-test.log 2>&1
STATUS=$?
set -e

grep -E "error:|Test Case .* (passed|failed)|Executed|\*\* TEST" build/xcodebuild-test.log || true
if [[ $STATUS -ne 0 ]]; then
  echo "xcodebuild test falló ($STATUS). Últimas líneas del log:" >&2
  tail -n 60 build/xcodebuild-test.log >&2
fi
exit $STATUS
