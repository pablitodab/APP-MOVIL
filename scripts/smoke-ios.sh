#!/usr/bin/env bash
# Prueba de humo en simulador: compila la app, la instala, la abre y comprueba que
# sigue viva. Guarda una captura y los errores del log en build/smoke/.
# Requiere macOS con Xcode y el proyecto generado (`xcodegen generate`).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/smoke"
BUNDLE_ID="com.pablitodab.gymtracker"
DERIVED_DATA="build/DerivedData-sim"
mkdir -p "$OUT"

DEVICE_ID="$(scripts/pick-simulator.sh)"

set +e
xcodebuild build \
  -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  > "$OUT/xcodebuild-sim.log" 2>&1
STATUS=$?
set -e
grep -E "error:|\*\* BUILD" "$OUT/xcodebuild-sim.log" || true
if [[ $STATUS -ne 0 ]]; then
  tail -n 60 "$OUT/xcodebuild-sim.log" >&2
  exit $STATUS
fi

echo "Arrancando simulador $DEVICE_ID..."
SECONDS=0
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b > /dev/null
echo "Simulador listo en ${SECONDS}s"

xcrun simctl install "$DEVICE_ID" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/GymTracker.app"
LAUNCH_TIME="$(date -u +"%Y-%m-%d %H:%M:%S")"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
sleep 15

xcrun simctl io "$DEVICE_ID" screenshot "$OUT/launch.png" > /dev/null
xcrun simctl spawn "$DEVICE_ID" log show --start "$LAUNCH_TIME" --style compact \
  --predicate 'process == "GymTracker" AND (messageType == error OR messageType == fault)' \
  > "$OUT/app-errors.log" 2>&1 || true
echo "Errores/fallos registrados por la app: $(grep -c "GymTracker" "$OUT/app-errors.log" || true)"
head -n 40 "$OUT/app-errors.log"

if ! xcrun simctl spawn "$DEVICE_ID" launchctl list | grep -q "UIKitApplication:$BUNDLE_ID"; then
  echo "La app no sigue en ejecución 15 s después de abrirla (¿crash al arrancar?)." >&2
  exit 1
fi
echo "La app arranca y sigue en ejecución."
