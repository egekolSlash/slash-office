# Gardırop paketinin önizlemesi (Blender headless, CPU skinning): temel karakter + paket öğeleri.
# Blender -b --factory-startup --python tools/wardrobe/preview.py -- <character.json> <paket klasörü> <çıktı.png> <çekim>...
# çekim: "top=<kimlik>;bottom=<kimlik>;shoes=<kimlik>;hair=<n>;clip=<ad>;t=<0..1>;view=<x,y,z>;cy=<m>;dist=<m>"
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "character"))
import pack as acpack  # noqa: E402
import clips  # noqa: E402

import bpy  # noqa: E402
import numpy as np  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
BASE, PACK_DIR, OUT, SHOTS = argv[0], argv[1], argv[2], argv[3:]
base = acpack.Pack(BASE)
extra = json.load(open(os.path.join(PACK_DIR, "pack.json")))
base.data["meshes"].update(extra["meshes"])
items = {i["name"]: i for i in extra["outfits"] + extra["bottoms"] + extra["shoes"]}
ROOT = os.path.dirname(BASE)
TINTS = {"skin": (1.0, 0.84, 0.72), "hair": (0.40, 0.24, 0.13), "top": (0.30, 0.55, 0.95), "bottom": (0.30, 0.33, 0.45),
         "shoes": (0.85, 0.30, 0.28)}
_img = {}


def image(path, colorspace="sRGB"):
    if path not in _img:
        im = bpy.data.images.load(path)
        im.colorspace_settings.name = colorspace
        _img[path] = im
    return _img[path]


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(part, eye_tex=None, mouth_tex=None):
    mode = part["mode"]
    mat = bpy.data.materials.new(mode)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.85
    sock = lambda coll, ident: next(x for x in coll if x.identifier == ident)
    if mode == "design":
        c1, c2 = (srgb_to_linear(c) for c in part["colors"])
        mask = nt.nodes.new("ShaderNodeTexImage"); mask.image = image(os.path.join(PACK_DIR, part["texture"]))
        det = nt.nodes.new("ShaderNodeTexImage"); det.image = image(os.path.join(PACK_DIR, part["detail"]))
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(mask.outputs["Color"], sep.inputs["Color"])
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
        nt.links.new(sep.outputs[0], sock(mix.inputs, "Factor_Float"))
        sock(mix.inputs, "A_Color").default_value = (*c1, 1)
        sock(mix.inputs, "B_Color").default_value = (*c2, 1)
        mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
        sock(mul.inputs, "Factor_Float").default_value = 1
        nt.links.new(sock(mix.outputs, "Result_Color"), sock(mul.inputs, "A_Color"))
        comb = nt.nodes.new("ShaderNodeCombineColor")
        for k in range(3):
            nt.links.new(sep.outputs[1], comb.inputs[k])
        nt.links.new(comb.outputs[0], sock(mul.inputs, "B_Color"))
        top = nt.nodes.new("ShaderNodeMix"); top.data_type = "RGBA"
        nt.links.new(det.outputs["Alpha"], sock(top.inputs, "Factor_Float"))
        nt.links.new(sock(mul.outputs, "Result_Color"), sock(top.inputs, "A_Color"))
        nt.links.new(det.outputs["Color"], sock(top.inputs, "B_Color"))
        nt.links.new(sock(top.outputs, "Result_Color"), bsdf.inputs["Base Color"])
        return mat
    tint = TINTS.get(part.get("tint")) or tuple(part.get("color", (1, 1, 1)))
    rel = part.get("texture") or (eye_tex if mode == "eye" else mouth_tex if mode == "mouth" else None)
    if mode in ("eye", "mouth", "decal") and rel:
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = image(os.path.join(ROOT, rel))
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
        nt.links.new(tex.outputs["Alpha"], sock(mix.inputs, "Factor_Float"))
        sock(mix.inputs, "A_Color").default_value = (*tint, 1)
        nt.links.new(tex.outputs["Color"], sock(mix.inputs, "B_Color"))
        nt.links.new(sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    elif mode in ("tinted", "pattern") and rel:
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = image(os.path.join(ROOT, rel))
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
        sock(mix.inputs, "Factor_Float").default_value = 1
        nt.links.new(tex.outputs["Color"], sock(mix.inputs, "A_Color"))
        sock(mix.inputs, "B_Color").default_value = (*tint, 1)
        nt.links.new(sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*tint, 1)
    return mat


def setup():
    sc = bpy.context.scene
    for ob in list(sc.objects):
        bpy.data.objects.remove(ob)
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 300, 420
    sc.view_settings.view_transform = "Standard"
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.80, 0.86, 0.92, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.2
    sun.rotation_euler = (math.radians(45), 0, math.radians(25))
    sc.collection.objects.link(sun)
    bpy.ops.mesh.primitive_plane_add(size=3)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def to_blender(p):
    return np.c_[p[:, 0], -p[:, 2], p[:, 1]]


frames = []
for i, shot in enumerate(SHOTS):
    opts = dict(kv.split("=", 1) for kv in shot.split(";"))
    cam = setup()
    hair = int(opts.get("hair", "0"))
    parts = list(base.data["body"]) + base.data.get("blush", []) + base.data["hairs"][hair]
    top = items.get(opts.get("top", ""))
    if top:
        parts += top["parts"]
    else:
        parts += base.data["outfits"][0]["parts"]
    if not (top and top.get("onepiece")):
        b = items.get(opts.get("bottom", ""))
        parts += b["parts"] if b else base.data["bottoms"][0]["parts"]
    s = items.get(opts.get("shoes", ""))
    parts += s["parts"] if s else base.data["shoes"][0]["parts"]
    eye_tex, mouth_tex = base.data["eyes"][0][0], base.data["mouths"][0][0]
    mats = clips.sample(base, opts.get("clip", "rest"), float(opts.get("t", "0")))
    for part in parts:
        m = base.mesh(part["mesh"])
        pos = to_blender(acpack.skin_vertices(m, mats))
        me = bpy.data.meshes.new(part["mesh"])
        me.from_pydata(pos.tolist(), [], m["indices"].tolist())
        uv = me.uv_layers.new()
        uv.data.foreach_set("uv", m["uvs"][m["indices"].ravel()].ravel())
        for poly in me.polygons:
            poly.use_smooth = True
        me.materials.append(material(part, eye_tex, mouth_tex))
        ob = bpy.data.objects.new(part["mesh"], me)
        bpy.context.collection.objects.link(ob)
    view = np.array([float(v) for v in opts.get("view", "0.35,-1,0.12").split(",")])
    center = np.array([0, 0, float(opts.get("cy", "0.45"))])
    from mathutils import Vector
    cam.location = Vector(center + view / np.linalg.norm(view) * float(opts.get("dist", "1.8")))
    cam.rotation_euler = (Vector(center) - cam.location).to_track_quat("-Z", "Y").to_euler()
    path = OUT + "_shot%02d.png" % i
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    frames.append(path)

imgs = []
for f in frames:
    im = bpy.data.images.load(f)
    w, h = im.size
    imgs.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4))
sheet = np.concatenate(imgs, axis=1)
o = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
o.pixels[:] = sheet.ravel()
o.filepath_raw = OUT
o.file_format = "PNG"
o.save()
for f in frames:
    os.remove(f)
print("PREVIEW", OUT, len(frames))
