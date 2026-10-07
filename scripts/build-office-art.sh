#!/bin/sh
# Ofis varlıklarını (köylü + eşyalar, office-art.json) Blender'la yeniden üretir: Resources/OfficeArt.
# Blender yolu BLENDER ile değiştirilebilir. Poz önizlemeleri: tools/office-art/out/.
set -eu
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
"$BLENDER" -b --factory-startup --python tools/office-art/build_assets.py -- "$(pwd)" 2>&1 | grep -E "CHECK|PROP|JSON|DONE|Error|Traceback" || true
