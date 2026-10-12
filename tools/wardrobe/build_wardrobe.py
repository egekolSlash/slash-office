# Gardırop paketi: tasarımların meshlerini ve dokularını üretir, paket klasörü + zip yazar (SHA-256 ve boyutu yazdırır).
# Çalıştır: python3 tools/wardrobe/build_wardrobe.py <çıktı klasörü> [sürüm]
# Çıktı: <çıktı>/wardrobe/{pack.json, tex/*.png} ve <çıktı>/wardrobe-<sürüm>.zip. Blender gerekmez (numpy + PIL).
import hashlib
import json
import os
import sys
import zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "character"))
import designs as D  # noqa: E402
import garments as GM  # noqa: E402
from painter import Painter  # noqa: E402
from rig import mesh_json  # noqa: E402

OUT = sys.argv[1]
VERSION = sys.argv[2] if len(sys.argv) > 2 else "1"
PACK = os.path.join(OUT, "wardrobe")
os.makedirs(os.path.join(PACK, "tex"), exist_ok=True)

meshes = {}
mesh_cache = {}


def save_png(rgba, rel):
    path = os.path.join(PACK, "tex", rel)
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path, optimize=True)
    return "tex/" + rel


def add_mesh(name, mesh, region):
    if name not in meshes:
        meshes[name] = mesh_json(mesh, region)
    return name


def colors(design):
    return [list(map(float, c)) for c in design["colors"]]


def design_part(mesh, design, tex, detail, tint):
    return {"mesh": mesh, "mode": "design", "texture": tex, "detail": detail, "tint": tint, "colors": colors(design)}


def titles(design):
    return {"title": design["en"], "titles": {"tr": design["tr"]}}


def paint(design, layout, size, swatches):
    p = Painter(layout, size)
    design["paint"](p)
    mask, detail = p.images(swatches)
    return save_png(mask, design["id"] + "_m.png"), save_png(detail, design["id"] + "_d.png")


outfits, bottoms, shoes = [], [], []

for d in D.TOPS:
    key = (d["kind"], d["sleeve"], d.get("legs_to"), d.get("legs_r"))
    if key not in mesh_cache:
        layout = GM.Layout()
        parts, _ = GM.top_garment(d["kind"], d["sleeve"], layout, legs_to=d.get("legs_to"), legs_r=d.get("legs_r"))
        name = "top/%s-%s" % (d["kind"], d["sleeve"]) + ("-%s" % len(mesh_cache) if d.get("legs_to") or d.get("legs_r") else "")
        mesh_cache[key] = (name, parts, layout)
    name, parts, layout = mesh_cache[key]
    collar = d.get("collar")
    swatches = {"primary": ("first", None), "secondary": ("second", None),
                "detail": ("detail", collar) if collar else ("first", None)}
    tex, det = paint(d, layout, 256, swatches)
    item_parts = [design_part(add_mesh(name, parts["main"], "torso"), d, tex, det, "top")]
    if "collar" in parts:
        item_parts.append(design_part(add_mesh("top/shirt-collar", parts["collar"], "torso"), d, tex, det, "top"))
    if d.get("hood"):
        item_parts.append(design_part(add_mesh("top/hood", GM.hood(), "torso"), d, tex, det, "top"))
    outfits.append({"name": d["id"], "parts": item_parts, "onepiece": GM.onepiece_kind(d["kind"]), **titles(d)})

for d in D.BOTTOMS:
    key = ("bottom", d["kind"])
    if key not in mesh_cache:
        layout = GM.Layout()
        parts = GM.bottom_garment(d["kind"], layout)
        mesh_cache[key] = ("bottom/" + d["kind"], parts, layout)
    name, parts, layout = mesh_cache[key]
    tex, det = paint(d, layout, 256, {"primary": ("first", None), "secondary": ("second", None)})
    bottoms.append({"name": d["id"], "parts": [design_part(add_mesh(name, parts["main"], "leg"), d, tex, det, "bottom")], **titles(d)})

for d in D.SHOES:
    key = ("shoe", d["kind"])
    if key not in mesh_cache:
        layout = GM.Layout()
        layout.add("body", 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, lambda _y: 1.0)
        mesh_cache[key] = ("shoes/" + d["kind"], GM.shoe_garment(d["kind"]), layout)
    name, parts, layout = mesh_cache[key]
    tex, det = paint(d, layout, 128, {"primary": ("first", None), "secondary": ("second", None), "detail": ("second", None)})
    item = [design_part(add_mesh(name, parts["main"], "foot"), d, tex, det, "shoes"),
            {"mesh": add_mesh(name + "-sole", parts["sole"], "foot"), "mode": "flat", "color": list(map(float, d["sole"]))}]
    shoes.append({"name": d["id"], "parts": item, **titles(d)})

pack = {"version": 1, "id": "wardrobe", "meshes": meshes, "outfits": outfits, "bottoms": bottoms, "shoes": shoes}
with open(os.path.join(PACK, "pack.json"), "w") as f:
    json.dump(pack, f)

zip_path = os.path.join(OUT, "wardrobe-%s.zip" % VERSION)
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(PACK):
        for name in sorted(files):
            full = os.path.join(root, name)
            z.write(full, os.path.relpath(full, OUT))
sha = hashlib.sha256(open(zip_path, "rb").read()).hexdigest()
tris = {k: v["triangles"] for k, v in meshes.items()}
print("WARDROBE tops=%d bottoms=%d shoes=%d meshes=%d maxTris=%d zip=%s bytes=%d sha256=%s" % (
    len(outfits), len(bottoms), len(shoes), len(meshes), max(tris.values()), zip_path, os.path.getsize(zip_path), sha))
