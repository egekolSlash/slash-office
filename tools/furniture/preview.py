# Dekor eşyalarının önizlemesi (köşe renkleri). Blender -b --factory-startup --python tools/furniture/preview.py -- <furniture.json> <çıktı.png> [ad ...]
import base64, json, math, sys
import bpy
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
data = json.load(open(argv[0]))["props"]
out, names = argv[1], argv[2:] or sorted(data)
sc = bpy.context.scene
for ob in list(sc.objects):
    bpy.data.objects.remove(ob)   # varsayılan küp, kamera, ışık
try:
    sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x, sc.render.resolution_y = 300 * min(len(names), 7), 360 * math.ceil(len(names) / 7)
sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND").inputs["Color"].default_value = (0.86, 0.88, 0.92, 1)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 2.5
sun.rotation_euler = (math.radians(45), 0, math.radians(30)); sc.collection.objects.link(sun)
mat = bpy.data.materials.new("vc"); mat.use_nodes = True
bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
attr = mat.node_tree.nodes.new("ShaderNodeVertexColor"); attr.layer_name = "col"
mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
for k, name in enumerate(names):
    m = data[name]
    arr = lambda key, t, n: np.frombuffer(base64.b64decode(m[key]), dtype=t).reshape(-1, n)
    p = arr("positions", "<f4", 3).astype(float); col = arr("colors", "u1", 4) / 255.0; idx = arr("indices", "<u4", 3)
    gx, gz = (k % 7) * 1.2, -(k // 7) * 1.6
    verts = [(x + gx, -z, y + gz) for x, y, z in p]   # uygulama -> Blender
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], idx.tolist())
    ca = me.color_attributes.new("col", "BYTE_COLOR", "POINT")
    for i, c in enumerate(col):
        ca.data[i].color = tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c[:3]) + (1.0,)   # sRGB -> doğrusal
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cols, rows = min(len(names), 7), math.ceil(len(names) / 7)
cam.data.lens = 50
center = Vector(((cols - 1) * 0.6, 0, 0.6 - (rows - 1) * 0.8))
span = max(cols * 1.2, rows * 1.6 * sc.render.resolution_x / sc.render.resolution_y)
cam.location = center + Vector((0.45, -0.75, 0.42)).normalized() * (span * 1.25 + 1.5)
cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("PREVIEW", out)
