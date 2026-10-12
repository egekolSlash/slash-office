#!/bin/sh
# Karakteri (gövde, saçlar, kıyafetler, yüz dokuları, klipler) Blender'la yeniden üretir: Resources/Character.
# Blender yolu BLENDER ile değiştirilebilir.
set -eu
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
OUT=Resources/Character
rm -rf "$OUT/tex"
"$BLENDER" -b --factory-startup --python tools/character/build_character.py -- "$OUT" 2>&1 | grep -E "CHARACTER|Error|Traceback" || true
"$BLENDER" -b --factory-startup --python tools/character/clips.py -- "$OUT/character.json" 2>&1 | grep -E "CLIPS|Error|Traceback" || true
