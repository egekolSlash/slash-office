#!/bin/sh
# Gardırop paketini (indirilebilir ek kıyafetler) üretir: build/packs/wardrobe-<sürüm>.zip ve Resources/packs.json'u
# (adres, SHA-256, boyut) günceller. Zip GitHub'da `wardrobe-<sürüm>` sürüm etiketine yüklenir; uygulama bu adresten
# indirip SHA-256'yı doğrular.
set -eu
cd "$(dirname "$0")/.."
VERSION=${1:-1}
OUT=build/packs
rm -rf "$OUT/wardrobe" "$OUT/wardrobe-$VERSION.zip"
mkdir -p "$OUT"
python3 tools/wardrobe/build_wardrobe.py "$OUT" "$VERSION" | grep WARDROBE
python3 - "$OUT/wardrobe-$VERSION.zip" "$VERSION" <<'PY'
import hashlib, json, os, sys
zip_path, version = sys.argv[1], sys.argv[2]
entry = {"id": "wardrobe", "title": "Wardrobe",
         "summary": "93 tops, 21 bottoms and 14 pairs of shoes (recolourable designs).",
         "version": version,
         "url": "https://github.com/egekolSlash/slash-office/releases/download/wardrobe-%s/wardrobe-%s.zip" % (version, version),
         "sha256": hashlib.sha256(open(zip_path, "rb").read()).hexdigest(), "bytes": os.path.getsize(zip_path)}
json.dump([entry], open("Resources/packs.json", "w"), indent=2)
open("Resources/packs.json", "a").write("\n")
print("packs.json:", entry["url"], entry["sha256"], entry["bytes"])
PY
