#!/bin/sh
# Ofis varlıklarını (köylü + eşyalar, USDZ) Blender'la yeniden üretir: Resources/OfficeArt.
# Blender yolu BLENDER ile değiştirilebilir. Poz önizlemeleri: tools/office-art/out/.
set -eu
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
"$BLENDER" -b --factory-startup --python tools/office-art/build_assets.py -- "$(pwd)" 2>&1 | grep -E "CHECK|PROP|DONE|Error|Traceback" || true
for f in Resources/OfficeArt/villager.usdz Resources/OfficeArt/props/*.usdz; do
    usdchecker "$f" >/dev/null 2>&1 || echo "usdchecker başarısız: $f"
done
