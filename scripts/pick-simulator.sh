#!/usr/bin/env bash
# Imprime el UDID del simulador de iPhone más adecuado para el Xcode activo:
# runtime igual (o el más cercano por debajo) al SDK y un modelo estándar reciente.
set -euo pipefail

SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
echo "SDK del simulador: iOS $SDK_VERSION" >&2

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

echo "$DEVICE_ID"
