#!/usr/bin/env bash
# Compila GymTracker para iPhone y genera build/GymTracker.ipa para instalarlo con Sideloadly.
#
# El .ipa lleva una firma ad-hoc (no válida para instalar tal cual) cuyo único propósito
# es incrustar los entitlements de HealthKit: Sideloadly los lee de esa firma y vuelve a
# firmar la app con tu Apple ID. Sin ella, la app instalada no podría usar Salud.
set -euo pipefail
cd "$(dirname "$0")/.."

ENTITLEMENTS="GymTracker/SupportingFiles/GymTracker.entitlements"
DERIVED_DATA="build/DerivedData-device"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/GymTracker.app"
STAGING="build/ipa"

rm -rf "$STAGING" build/GymTracker.ipa
mkdir -p build

xcodebuild build \
  -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | tee build/xcodebuild-device.log \
  | grep -E "error:|\*\* BUILD" || true
if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
  echo "Falló la compilación para iPhone; ver build/xcodebuild-device.log" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "No se encontró $APP_PATH" >&2
  exit 1
fi

mkdir -p "$STAGING/Payload"
cp -R "$APP_PATH" "$STAGING/Payload/"
STAGED_APP="$STAGING/Payload/GymTracker.app"

# Firmar primero lo anidado (si algún día hay frameworks) y después la app con entitlements.
if [[ -d "$STAGED_APP/Frameworks" ]]; then
  find "$STAGED_APP/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) \
    -exec codesign --force --sign - {} \;
fi
codesign --force --sign - --entitlements "$ENTITLEMENTS" --generate-entitlement-der "$STAGED_APP"

echo "Entitlements incrustados:"
codesign -d --entitlements - "$STAGED_APP" 2>/dev/null | tee build/entitlements.txt
if ! grep -q "com.apple.developer.healthkit" build/entitlements.txt; then
  echo "El entitlement de HealthKit no está en la firma." >&2
  exit 1
fi

(cd "$STAGING" && zip -qry ../GymTracker.ipa Payload)
echo "IPA generado: build/GymTracker.ipa ($(du -h build/GymTracker.ipa | cut -f1))"
