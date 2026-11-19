#!/usr/bin/env bash
# Archiva GymTracker con firma de distribución y lo sube a App Store Connect (TestFlight).
#
# Requiere una cuenta de pago del Apple Developer Program y una clave de la API de
# App Store Connect con rol Admin (la firma automática en la nube necesita crear el
# certificado de distribución y el perfil con HealthKit). Variables:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contenido del .p8), TEAM_ID
#   BUNDLE_ID (opcional, por defecto com.pablitodab.gymtracker)
#   BUILD_NUMBER (opcional; debe crecer en cada subida)
set -euo pipefail
cd "$(dirname "$0")/.."

missing=()
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 TEAM_ID; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done
if (( ${#missing[@]} )); then
  echo "Faltan secretos para subir a TestFlight: ${missing[*]}. Ver README, sección TestFlight." >&2
  exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-com.pablitodab.gymtracker}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%s)}"
ARCHIVE="build/GymTracker.xcarchive"
KEY_DIR="$(mktemp -d)"
KEY_PATH="$KEY_DIR/AuthKey_$ASC_KEY_ID.p8"
trap 'rm -rf "$KEY_DIR"' EXIT

mkdir -p build
umask 077
printf '%s\n' "$ASC_KEY_P8" > "$KEY_PATH"

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

run() {
  local log="$1"; shift
  set +e
  "$@" > "$log" 2>&1
  local status=$?
  set -e
  grep -E "error:|\*\* (ARCHIVE|EXPORT)" "$log" || true
  if [[ $status -ne 0 ]]; then
    echo "Falló ($status). Últimas líneas de $log:" >&2
    tail -n 60 "$log" >&2
    exit $status
  fi
}

rm -rf "$ARCHIVE" build/export
run build/xcodebuild-archive.log xcodebuild archive \
  -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}"

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

run build/xcodebuild-export.log xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  "${AUTH[@]}"

echo "Subida la build $BUILD_NUMBER de $BUNDLE_ID. Aparecerá en TestFlight cuando Apple la procese (5-30 min)."
