#!/bin/sh
# Minyonu (arka plan işi kedisi) Blender'la yeniden üretir: Resources/Minion.
# Blender yolu BLENDER ile değiştirilebilir.
set -eu
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
OUT=Resources/Minion
rm -rf "$OUT"
"$BLENDER" -b --factory-startup --python tools/minion/build_minion.py -- "$OUT" 2>&1 | grep -E "MINION|Error|Traceback|line [0-9]" || true
