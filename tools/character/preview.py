# Karakter paketi + kliplerin önizlemesi (Blender headless, CPU skinning).
# Blender -b --factory-startup --python tools/character/preview.py -- <character.json> <çıktı.png> <çekim>...
# çekim: "look=<saç>,<üst>,<alt>,<ayakkabı>,<göz stili>,<göz>,<ağız>,<desen>;clip=<ad>;t=<0..1>;view=<x,y,z>"
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack as acpack  # noqa: E402
import clips  # noqa: E402

import bpy  # noqa: E402
import numpy as np  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
PACK_PATH, OUT, SHOTS = argv[0], argv[1], argv[2:]
pack = acpack.Pack(PACK_PATH)
ROOT = os.path.dirname(PACK_PATH)
TINTS = {"skin": (1.0, 0.82, 0.70), "hair": (0.40, 0.24, 0.13), "top": (0.30, 0.55, 0.95), "bottom": (0.30, 0.33, 0.45),
         "shoes": (0.85, 0.30, 0.28)}
_img = {}


def image(rel):
    if rel not in _img:
        _img[rel] = bpy.data.images.load(os.path.join(ROOT, rel))
    return _img[rel]


def material(part, eye_tex, mouth_tex, pattern_tex=None):
    mode = part["mode"]
    mat = bpy.data.materials.new(mode)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.85
    sock = lambda coll, ident: next(x for x in coll if x.identifier == ident)
    tint = TINTS.get(part.get("tint")) or tuple(part.get("color", (1, 1, 1)))
    rel = part.get("texture") or (eye_tex if mode == "eye" else mouth_tex if mode == "mouth" else
                                  pattern_tex if mode == "pattern" else None)
    if mode == "pattern":
        mode = "tinted"
    if mode == "decal":
        mode = "eye"
    tex = None
    if rel:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image(rel)
    if mode == "flat":
        bsdf.inputs["Base Color"].default_value = (*tint, 1)
    elif mode in ("albedo", "cutout"):
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if mode == "cutout":
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    elif mode == "tinted":
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
        sock(mix.inputs, "Factor_Float").default_value = 1
        nt.links.new(tex.outputs["Color"], sock(mix.inputs, "A_Color"))
        sock(mix.inputs, "B_Color").default_value = (*tint, 1)
        nt.links.new(sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    elif mode in ("eye", "mouth"):
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
        nt.links.new(tex.outputs["Alpha"], sock(mix.inputs, "Factor_Float"))
        sock(mix.inputs, "A_Color").default_value = (*tint, 1)
        nt.links.new(tex.outputs["Color"], sock(mix.inputs, "B_Color"))
        nt.links.new(sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    return mat


def parts_for(look):
    hair, outfit, bottom, shoes, eye_set, eye, mouth, pattern = (list(look) + [0])[:8]
    o = pack.data["outfits"][outfit]
    parts = list(pack.data["body"]) + pack.data.get("blush", []) + pack.data["hairs"][hair] + o["parts"] + pack.data["shoes"][shoes]["parts"]
    if not o["onepiece"]:
        parts += pack.data["bottoms"][bottom]["parts"]
    return parts, pack.data["eyes"][eye_set][eye], pack.data["mouths"][0][mouth], pack.data["patterns"][pattern]


def setup():
    sc = bpy.context.scene
    for ob in list(sc.objects):
        bpy.data.objects.remove(ob)
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 360, 480
    sc.view_settings.view_transform = "Standard"
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.80, 0.86, 0.92, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.2
    sun.rotation_euler = (math.radians(45), 0, math.radians(25))
    sc.collection.objects.link(sun)
    # Zemin + tabure/masa yükseklik çizgileri (referans).
    bpy.ops.mesh.primitive_plane_add(size=3)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def to_blender(p):  # uygulama (x, y, z) -> Blender (x, -z, y)
    return np.c_[p[:, 0], -p[:, 2], p[:, 1]]


frames = []
for i, shot in enumerate(SHOTS):
    opts = dict(kv.split("=", 1) for kv in shot.split(";"))
    look = tuple(int(x) for x in opts.get("look", "0,0,0,0,0,0,0,0").split(","))
    cam = setup()
    if opts.get("props") == "desk":
        # Avatar uzayı (uygulama z -> Blender -y): tabure merkez z=+0,08 (üst 0,46), masa merkez z=+0,40 (üst 0,565).
        bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=0.46, location=(0, -0.08, 0.23))
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.45, 0.55)); bpy.context.object.scale = (0.9, 0.40, 0.03)
    parts, eye_tex, mouth_tex, pattern_tex = parts_for(look)
    mats = clips.sample(pack, opts.get("clip", "rest"), float(opts.get("t", "0")))
    for part in parts:
        m = pack.mesh(part["mesh"])
        pos = to_blender(acpack.skin_vertices(m, mats))
        me = bpy.data.meshes.new(part["mesh"])
        me.from_pydata(pos.tolist(), [], m["indices"].tolist())
        uv = me.uv_layers.new()
        uv.data.foreach_set("uv", m["uvs"][m["indices"].ravel()].ravel())
        for poly in me.polygons:
            poly.use_smooth = True
        me.materials.append(material(part, eye_tex, mouth_tex, pattern_tex))
        ob = bpy.data.objects.new(part["mesh"], me)
        bpy.context.collection.objects.link(ob)
    view = np.array([float(v) for v in opts.get("view", "0.6,-1,0.25").split(",")])
    center = np.array([0, 0, float(opts.get("cy", "0.55"))])
    from mathutils import Vector
    cam.location = Vector(center + view / np.linalg.norm(view) * float(opts.get("dist", "3.2")))
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
