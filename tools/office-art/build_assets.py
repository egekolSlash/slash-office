# Slash Office varlıkları: iskeletli Animal Crossing tarzı köylü + eşyalar -> Resources/OfficeArt/office-art.json.
# Çalıştır: scripts/build-office-art.sh  (Blender -b --factory-startup --python build_assets.py -- <depo kökü>)
#
# Sözleşme (uygulama buna güvenir, v3 spec §4/§8, v4 spec §4; Core'da OfficeArtFile):
#  - Blender (x, y, z) -> uygulama (x, z, -y), Y yukarı. Köylü -Y'ye (uygulamada +z'ye, kameraya) bakar; ayakları z=0'da.
#  - Köylü mesh'leri: Body, HairShort, HairPigtails, HairSpiky, HairBob, Glasses (saç modeli kodu 1…4, gözlük parça 4).
#  - Değiştirilebilir malzemeler taban rengiyle tanınır: tişört (0.30,0.55,0.95), ten (0.99,0.84,0.72), saç (0.35,0.20,0.10).
#  - Klipler (24 fps): idle 1-24, walk 31-54, sitType 61-84, sitDoze 91-138, wave 141-164 (AvatarClip.frames).
#  - Eşyalar orijinde, zeminde. Masa takımında köylü +Y tarafında (uygulamada -z) oturur; tabure y=+0.32 (DeskGeometry.seatOffset).
#    Masa üstü 0.565; tabure üstü 0.46.
#    Duvara yaslanan eşyalar (kitaplık, pencere, perde) +X'e bakar.
#  - Çiçek başı taban rengi (1.0,0.42,0.48): uygulama renk çeşitler.
import base64, json
import bpy, math, os, sys
import numpy as np
from mathutils import Matrix, Vector

ROOT = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(ROOT, "Resources", "OfficeArt")
PREVIEW = os.path.join(ROOT, "tools", "office-art", "out")
os.makedirs(OUT, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = 24

# ---------------------------------------------------------------- yardımcılar
MATS = {}
def mat(name, color, rough=0.55, emit=None, es=0.0):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1); b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1); b.inputs["Emission Strength"].default_value = es
    MATS[name] = m
    return m

PARTS = []
def finish(o, m, group=None, bevel=0.0):
    o.data.materials.append(m)
    if group:
        vg = o.vertex_groups.new(name=group); vg.add(range(len(o.data.vertices)), 1.0, 'REPLACE')
    if bevel:
        bv = o.modifiers.new("Bevel", "BEVEL"); bv.width = bevel; bv.segments = 3; bv.limit_method = 'ANGLE'
        bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier=bv.name)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth()
    PARTS.append(o)
    return o

def sphere(r, loc, m, group=None, scale=(1, 1, 1), seg=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=rings)
    o = bpy.context.active_object; o.scale = scale; bpy.ops.object.transform_apply(scale=True)
    return finish(o, m, group)

def capsule(r, a, b, m, group=None):
    a, b = Vector(a), Vector(b); d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, location=(a + b) / 2, vertices=20)
    o = bpy.context.active_object; o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    bpy.ops.object.transform_apply(rotation=True)
    finish(o, m, group); sphere(r, a, m, group, seg=20, rings=10); sphere(r, b, m, group, seg=20, rings=10)

def box(size, loc, m, bevel=0.02, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.scale = size; bpy.ops.object.transform_apply(scale=True)
    if rot:
        o.rotation_euler = rot; bpy.ops.object.transform_apply(rotation=True)
    return finish(o, m, bevel=bevel)

def cyl(r, h, loc, m, bevel=0.0, verts=24, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=verts, rotation=rot)
    o = bpy.context.active_object; bpy.ops.object.transform_apply(rotation=True)
    return finish(o, m, bevel=bevel)

def join(name, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object; o.name = name; o.data.name = name
    return o

# ---------------------------------------------------------------- köylü
M = dict(
    shirt=mat("Shirt", (0.30, 0.55, 0.95), 0.7), skin=mat("Skin", (0.99, 0.84, 0.72), 0.5),
    hair=mat("Hair", (0.35, 0.20, 0.10), 0.6), eye=mat("Eye", (0.04, 0.03, 0.05), 0.15),
    shine=mat("Shine", (1, 1, 1), 0.2, emit=(1, 1, 1), es=1.0), cheek=mat("Cheek", (1.0, 0.58, 0.58), 0.7),
    mouth=mat("Mouth", (0.45, 0.15, 0.12), 0.6), pants=mat("Pants", (0.25, 0.30, 0.45), 0.7),
    shoe=mat("Shoe", (0.55, 0.32, 0.20), 0.5), frame=mat("GlassFrame", (0.15, 0.12, 0.12), 0.3),
)
HIP, HZ = 0.34, 0.86
SH = HIP + 0.17                         # omuz
FY = -0.23                              # yüzün önü (y)
J = dict(shoulder=0.155, elbow=0.19, hand=0.21, elbowZ=HIP + 0.05, handZ=HIP - 0.06, leg=0.075, knee=0.19, ankle=0.07)

PARTS.clear()
capsule(0.14, (0, 0, HIP), (0, 0, HIP + 0.2), M["shirt"], "Hips")
sphere(0.25, (0, 0, HZ), M["skin"], "Head", (1.0, 0.95, 0.92))
for s in (-1, 1):
    sphere(0.042, (s * 0.09, FY, HZ), M["eye"], "Head", (0.75, 0.35, 1.0))
    sphere(0.012, (s * 0.09 + 0.012, FY - 0.012, HZ + 0.022), M["shine"], "Head")
    sphere(0.04, (s * 0.15, FY + 0.04, HZ - 0.07), M["cheek"], "Head", (1.0, 0.35, 0.6))
sphere(0.022, (0, FY - 0.02, HZ - 0.045), M["skin"], "Head")
sphere(0.03, (0, FY + 0.005, HZ - 0.105), M["mouth"], "Head", (1.0, 0.3, 0.45))
for s, side in ((-1, "L"), (1, "R")):
    sh, el, ha = (s * J["shoulder"], 0, SH), (s * J["elbow"], 0, J["elbowZ"]), (s * J["hand"], 0, J["handZ"])
    capsule(0.05, sh, el, M["shirt"], "UpperArm" + side)
    capsule(0.044, el, ha, M["skin"], "ForeArm" + side)
    sphere(0.056, ha, M["skin"], "ForeArm" + side)
    hip, knee, ankle = (s * J["leg"], 0, HIP), (s * J["leg"], 0, J["knee"]), (s * J["leg"], 0, J["ankle"])
    capsule(0.062, hip, knee, M["pants"], "Thigh" + side)
    capsule(0.056, knee, ankle, M["pants"], "Shin" + side)
    sphere(0.07, (s * J["leg"], -0.04, 0.06), M["shoe"], "Shin" + side, (1.0, 1.4, 0.7))
body = join("Body", list(PARTS))

def hair(name, extra):
    PARTS.clear()
    sphere(0.262, (0, 0.03, HZ + 0.05), M["hair"], "Head", (1.03, 1.0, 0.9))
    for dx in (-0.12, 0.0, 0.12):
        sphere(0.09, (dx, FY + 0.06, HZ + 0.15 - abs(dx) * 0.3), M["hair"], "Head", (1.2, 0.6, 0.8))
    extra()
    return join(name, list(PARTS))
hairs = [
    hair("HairShort", lambda: None),
    hair("HairPigtails", lambda: [sphere(0.1, (s * 0.28, 0.05, HZ - 0.05), M["hair"], "Head", (0.8, 0.8, 1.2)) for s in (-1, 1)]),
    hair("HairSpiky", lambda: [sphere(0.075, (dx, 0.04 + dy, HZ + 0.27), M["hair"], "Head", (0.7, 0.7, 1.5))
                                for dx, dy in ((-0.12, 0.02), (0.0, -0.02), (0.12, 0.02), (0.0, 0.1))]),
    hair("HairBob", lambda: [sphere(0.16, (s * 0.2, 0.04, HZ - 0.06), M["hair"], "Head", (0.8, 1.1, 1.3)) for s in (-1, 1)]),
]
PARTS.clear()
for s in (-1, 1):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.058, minor_radius=0.011, location=(s * 0.09, FY - 0.035, HZ),
                                     rotation=(math.radians(90), 0, 0), major_segments=24, minor_segments=8)
    o = bpy.context.active_object; bpy.ops.object.transform_apply(rotation=True); finish(o, M["frame"], "Head")
capsule(0.008, (-0.035, FY - 0.04, HZ + 0.01), (0.035, FY - 0.04, HZ + 0.01), M["frame"], "Head")
glasses = join("Glasses", list(PARTS))

bpy.ops.object.armature_add(location=(0, 0, 0)); arm = bpy.context.active_object; arm.name = "Villager"
bpy.ops.object.mode_set(mode='EDIT'); eb = arm.data.edit_bones
root = eb[0]; root.name = "Root"; root.head = (0, 0, 0); root.tail = (0, 0, 0.1)
def bone(name, head, tail, parent, connect=False):
    b = eb.new(name); b.head = head; b.tail = tail; b.parent = eb[parent]; b.use_connect = connect; return b
bone("Hips", (0, 0, HIP), (0, 0, HIP + 0.2), "Root")
bone("Head", (0, 0, HIP + 0.22), (0, 0, HZ + 0.28), "Hips")
for s, side in ((-1, "L"), (1, "R")):
    bone("UpperArm" + side, (s * J["shoulder"], 0, SH), (s * J["elbow"], 0, J["elbowZ"]), "Hips")
    bone("ForeArm" + side, (s * J["elbow"], 0, J["elbowZ"]), (s * J["hand"], 0, J["handZ"]), "UpperArm" + side, True)
    bone("Thigh" + side, (s * J["leg"], 0, HIP), (s * J["leg"], 0, J["knee"]), "Hips")
    bone("Shin" + side, (s * J["leg"], 0, J["knee"]), (s * J["leg"], 0, J["ankle"]), "Thigh" + side, True)
bpy.ops.object.mode_set(mode='OBJECT')
meshes = [body, *hairs, glasses]
for o in meshes:
    o.parent = arm
    mod = o.modifiers.new("Armature", "ARMATURE"); mod.object = arm

# ---------------------------------------------------------------- animasyon
pb = arm.pose.bones
for b in pb: b.rotation_mode = 'XYZ'
def key(frame, **poses):
    """poses: kemik -> (konum, (rx, ry, rz) derece). Belirtilmeyen kemikler dinlenme pozunda."""
    for b in pb:
        b.location = (0, 0, 0); b.rotation_euler = (0, 0, 0)
    for name, (loc, rot) in poses.items():
        pb[name].location = loc; pb[name].rotation_euler = [math.radians(a) for a in rot]
    for b in pb:
        b.keyframe_insert("location", frame=frame); b.keyframe_insert("rotation_euler", frame=frame)
Z = (0, 0, 0)
def R(x=0, y=0, z=0): return (Z, (x, y, z))
def up(dz): return ((0, dz, 0), Z)  # Root/Hips kemikleri +Z'yi gösterir: yerel y = yukarı

# idle 1-24: nefes
for f, b in ((1, 0), (12, 1), (24, 0)):
    key(f, Hips=up(0.012 * b), ForeArmL=R(x=-8), ForeArmR=R(x=-8), Head=R(x=2 * b))
# walk 31-54: bacak ve kol salınımı, arka bacakta diz kırılır
for f, ph in ((31, 0), (37, 1), (43, 0), (49, -1), (54, 0)):
    a = 28 * ph
    key(f, Hips=up(0.02 * (1 - abs(ph))),
        ThighL=R(x=-a), ThighR=R(x=a), ShinL=R(x=max(0, a) * 0.9), ShinR=R(x=max(0, -a) * 0.9),
        UpperArmL=R(x=a * 0.8), UpperArmR=R(x=-a * 0.8), ForeArmL=R(x=-15), ForeArmR=R(x=-15))
SIT = dict(Root=up(0.16), ThighL=R(x=-90), ThighR=R(x=-90), ShinL=R(x=90), ShinR=R(x=90))
# sitType 61-84: eller klavyede tıklar
for i, f in enumerate(range(61, 85, 3)):
    t = 7 if i % 2 == 0 else -7
    key(f, **SIT, UpperArmL=R(x=-70), UpperArmR=R(x=-70), ForeArmL=R(x=-20 + t), ForeArmR=R(x=-20 - t), Head=R(x=6))
# sitDoze 91-138: eller kucakta, baş yavaşça öne düşer
for f, n in ((91, 0), (103, 0.6), (115, 1), (127, 0.6), (138, 0)):
    key(f, **SIT, UpperArmL=R(x=-20), UpperArmR=R(x=-20), ForeArmL=R(x=-55), ForeArmR=R(x=-55),
        Head=R(x=22 * n), Hips=up(-0.01 * n))
# wave 141-164: sağ kol yana-yukarı, ön kol sallanır
for f, w in ((141, 0), (147, 1), (153, -1), (159, 1), (164, 0)):
    # Kollar kısa: ön kol -35..+15 dışında el kafanın içine girer (ölçüldü); hafif zıplama okunurluğu artırır.
    key(f, UpperArmR=R(z=-125), ForeArmR=R(z=-10 + 25 * w), Head=R(z=4 * w), ForeArmL=R(x=-8), Hips=up(0.015 * abs(w)))
scn.frame_start, scn.frame_end = 1, 164

# Doğrulama: el ve kalça konumları (sayısal) + her klipten bir kare (Workbench)
def tail(name, frame):
    scn.frame_set(frame); bpy.context.view_layer.update()
    return arm.matrix_world @ pb[name].tail
print("CHECK wave hand", [round(v, 2) for v in tail("ForeArmR", 147)], "head top z", round(HZ + 0.25, 2))
print("CHECK sit knee", [round(v, 2) for v in tail("ThighL", 70)],
      "foot", [round(v, 2) for v in tail("ShinL", 70)], "hand", [round(v, 2) for v in tail("ForeArmL", 70)])
scn.render.engine = 'BLENDER_WORKBENCH'; scn.render.resolution_x = 320; scn.render.resolution_y = 320
scn.display.shading.color_type = 'MATERIAL'
cd = bpy.data.cameras.new("Preview"); cd.type = 'ORTHO'; cd.ortho_scale = 1.9
cam = bpy.data.objects.new("Preview", cd); scn.collection.objects.link(cam); scn.camera = cam
cam.location = Vector((0, 0, 0.6)) + Vector((1, -1, 0.9)).normalized() * 6
cam.rotation_euler = (Vector((0, 0, 0.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
for h in hairs[1:] + [glasses]: h.hide_render = True
for name, frame in (("idle", 12), ("walk", 37), ("sitType", 64), ("sitDoze", 115), ("wave", 147)):
    scn.frame_set(frame); scn.render.filepath = os.path.join(PREVIEW, f"pose_{name}.png"); bpy.ops.render.render(write_still=True)
for h in hairs[1:] + [glasses]: h.hide_render = False
bpy.data.objects.remove(cam, do_unlink=True)
scn.frame_set(1)

# ---------------------------------------------------------------- eşyalar
for o in list(scn.objects): o.hide_set(True)
P = dict(
    wood=mat("Wood", (0.62, 0.40, 0.22), 0.45), woodL=mat("WoodLight", (0.85, 0.62, 0.38), 0.4),
    laptop=mat("Laptop", (0.95, 0.95, 0.93), 0.3), screen=mat("Screen", (0.1, 0.1, 0.1), 0.2, emit=(0.55, 0.9, 0.75), es=2.0),
    term=mat("TermScreen", (0.05, 0.05, 0.06), 0.2, emit=(0.30, 0.95, 0.45), es=1.6), dark=mat("Dark", (0.18, 0.18, 0.2), 0.4),
    mug=mat("Mug", (0.98, 0.98, 0.98), 0.3), cushion=mat("Cushion", (0.98, 0.78, 0.35), 0.7),
    pot=mat("Pot", (0.88, 0.48, 0.30), 0.55), leaf=mat("Leaf", (0.34, 0.70, 0.30), 0.5), leaf2=mat("Leaf2", (0.40, 0.76, 0.34), 0.5),
    flower=mat("Flower", (1.0, 0.42, 0.48), 0.5), yellow=mat("FlowerYellow", (1.0, 0.85, 0.30), 0.5),
    book1=mat("Book1", (0.95, 0.45, 0.42)), book2=mat("Book2", (0.40, 0.65, 0.92)), book3=mat("Book3", (0.98, 0.82, 0.35)),
    shade=mat("LampShade", (1.0, 0.92, 0.75), 0.6, emit=(1.0, 0.75, 0.45), es=3.0), trim=mat("Trim", (0.98, 0.96, 0.90), 0.4),
    glass=mat("WindowGlass", (0.75, 0.9, 1.0), 0.1, emit=(0.8, 0.92, 1.0), es=2.2), curtain=mat("Curtain", (0.95, 0.55, 0.55), 0.8),
    trunk=mat("Trunk", (0.55, 0.36, 0.22), 0.7), canopy=mat("Canopy", (0.25, 0.62, 0.25), 0.6), canopy2=mat("Canopy2", (0.36, 0.72, 0.30), 0.6),
)

def desk(device):
    box((0.70, 0.44, 0.05), (0, 0, 0.54), P["woodL"], 0.02)
    for dx in (-0.3, 0.3):
        for dy in (-0.17, 0.17): cyl(0.03, 0.52, (dx, dy, 0.26), P["wood"])
    device()
    cyl(0.04, 0.09, (0.25, -0.05, 0.61), P["mug"], 0.01)
    cyl(0.19, 0.09, (0, 0.32, 0.415), P["cushion"], 0.03)  # tabure: üstü 0.46
    for a in range(3):
        ang = a * 2.094
        cyl(0.025, 0.38, (0.12 * math.cos(ang), 0.32 + 0.12 * math.sin(ang), 0.19), P["wood"])
def laptop():
    box((0.34, 0.24, 0.02), (0, 0.04, 0.575), P["laptop"], 0.008)
    box((0.34, 0.02, 0.22), (0, -0.08, 0.69), P["laptop"], 0.008)
    box((0.30, 0.004, 0.18), (0, -0.068, 0.69), P["screen"], 0)  # ekran +Y'ye (köylüye) bakar
def monitor():
    box((0.05, 0.05, 0.1), (0, -0.1, 0.61), P["dark"], 0.01)
    box((0.34, 0.04, 0.24), (0, -0.1, 0.76), P["dark"], 0.012)
    box((0.30, 0.004, 0.2), (0, -0.078, 0.76), P["term"], 0)
    box((0.3, 0.1, 0.015), (0, 0.08, 0.575), P["dark"], 0.005)
def bookshelf():
    box((0.03, 0.9, 1.2), (-0.14, 0, 0.6), P["wood"], 0.01)
    for dy in (-0.44, 0.44): box((0.3, 0.03, 1.2), (0, dy, 0.6), P["wood"], 0.01)
    for z in (0.02, 0.42, 0.82, 1.19): box((0.3, 0.9, 0.03), (0, 0, z), P["woodL"], 0.01)
    books = ["book1", "book2", "book3"]
    for row, z in enumerate((0.04, 0.44, 0.84)):
        for i in range(5 - row):
            h = 0.26 + 0.05 * ((i * 5 + row) % 3)
            box((0.2, 0.08, h), (0.02, -0.33 + i * 0.12 + row * 0.04, z + h / 2), P[books[(i + row) % 3]], 0.01)
def plant():
    cyl(0.15, 0.28, (0, 0, 0.14), P["pot"], 0.02)
    for dx, dy, dz, r in ((0, 0, 0.42, 0.19), (-0.11, 0.05, 0.56, 0.13), (0.11, -0.04, 0.58, 0.14)):
        sphere(r, (dx, dy, dz), P["leaf"])
    for dx, dy, dz, c in ((0.05, -0.14, 0.64, "flower"), (-0.14, -0.05, 0.66, "yellow"), (0.12, 0.08, 0.7, "flower")):
        sphere(0.045, (dx, dy, dz), P[c])
def lamp():
    cyl(0.14, 0.035, (0, 0, 0.018), P["wood"], 0.01)
    cyl(0.022, 1.3, (0, 0, 0.65), P["wood"])
    bpy.ops.mesh.primitive_cone_add(radius1=0.24, radius2=0.15, depth=0.26, location=(0, 0, 1.38), vertices=32)
    finish(bpy.context.active_object, P["shade"])
def tree():
    cyl(0.1, 0.9, (0, 0, 0.3), P["trunk"])
    for i, (dz, r) in enumerate(((1.0, 0.58), (1.42, 0.45), (1.78, 0.3))):
        sphere(r, (0, 0, dz), P["canopy" if i % 2 == 0 else "canopy2"], scale=(1, 1, 0.82))
def flower():
    cyl(0.008, 0.1, (0, 0, 0.05), P["leaf"])
    sphere(0.035, (0.02, 0.02, 0.03), P["leaf2"], scale=(1.3, 0.8, 0.4))
    sphere(0.045, (0, 0, 0.11), P["flower"])
    sphere(0.018, (0, -0.03, 0.12), P["yellow"])
def window():
    box((0.06, 1.3, 0.95), (0, 0, 0), P["trim"], 0.02)
    box((0.06, 1.16, 0.81), (0.012, 0, 0), P["glass"], 0)
    box((0.07, 0.04, 0.81), (0.02, 0, 0), P["trim"], 0)
def curtain():
    box((0.05, 0.3, 1.1), (0, 0, 0), P["curtain"], 0.04)

# v5: dinlenme köşesi (koltuk, sehpa, sebil), arka plan tepeleri ve ikinci ağaç çeşidi.
def sofa():
    # +X'e (uygulamada +x'e) bakar; boyu Y boyunca 1.1, oturma yüksekliği 0.42.
    fabric = mat("SofaFabric", (0.36, 0.62, 0.70), 0.85)
    fabricD = mat("SofaFabricDark", (0.28, 0.52, 0.60), 0.85)
    box((0.5, 1.1, 0.2), (0.02, 0, 0.22), P["wood"], 0.03)
    box((0.42, 1.0, 0.12), (0.05, 0, 0.37), fabric, 0.05)
    box((0.14, 1.1, 0.42), (-0.2, 0, 0.45), fabricD, 0.06)
    for dy in (-0.5, 0.5): box((0.5, 0.12, 0.3), (0.02, dy, 0.38), fabricD, 0.05)
    for dx in (-0.18, 0.2):
        for dy in (-0.48, 0.48): cyl(0.03, 0.12, (dx, dy, 0.06), P["wood"])
def coffee_table():
    cyl(0.28, 0.04, (0, 0, 0.36), P["woodL"], 0.015, verts=32)
    cyl(0.035, 0.34, (0, 0, 0.17), P["wood"])
    cyl(0.16, 0.03, (0, 0, 0.015), P["wood"], 0.01)
    cyl(0.05, 0.08, (0.08, -0.06, 0.42), P["mug"], 0.01)
def water_cooler():
    body = mat("CoolerBody", (0.94, 0.94, 0.92), 0.4)
    water = mat("CoolerWater", (0.45, 0.70, 0.95), 0.15)
    box((0.32, 0.32, 0.9), (0, 0, 0.45), body, 0.04)
    cyl(0.13, 0.36, (0, 0, 1.08), water, 0.05)
    box((0.05, 0.06, 0.06), (0.17, 0, 0.62), P["dark"], 0.01)
    box((0.05, 0.06, 0.06), (0.17, 0.08, 0.62), mat("CoolerRed", (0.92, 0.35, 0.32), 0.4), 0.01)
def hill(tiers):
    # AC tarzı kademeli tepe: her kat düz tepeli, kenarı yuvarlatılmış elips; üstü çimen, yanı koyu yeşil.
    top = mat("HillTop", (0.48, 0.74, 0.36), 0.9)
    side = mat("HillSide", (0.36, 0.58, 0.28), 0.9)
    z = 0.0
    for rx, ry, h in tiers:
        bpy.ops.mesh.primitive_cylinder_add(radius=1, depth=h, location=(0, 0, z + h / 2), vertices=32, end_fill_type='TRIFAN')
        o = bpy.context.active_object; o.scale = (rx, ry, 1); bpy.ops.object.transform_apply(scale=True)
        o.data.materials.append(side); o.data.materials.append(top)
        for poly in o.data.polygons: poly.material_index = 1 if poly.normal.z > 0.5 else 0
        bv = o.modifiers.new("Bevel", "BEVEL"); bv.width = 0.25; bv.segments = 3; bv.limit_method = 'ANGLE'
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=bv.name)
        # Uygulamadaki zemin bükülmesi z'ye (Blender'da −y) bağlı: kapakları 0,6 m'lik dilimlere böl.
        bpy.ops.object.mode_set(mode='EDIT')
        k = -math.ceil(ry / 0.6)
        while k * 0.6 < ry:
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.bisect(plane_co=(0, k * 0.6, 0), plane_no=(0, 1, 0))
            k += 1
        bpy.ops.object.mode_set(mode='OBJECT')
        bpy.ops.object.shade_smooth()
        PARTS.append(o)
        z += h * 0.92
def tree_b():
    cyl(0.11, 1.0, (0, 0, 0.4), P["trunk"])
    crown = mat("CrownB", (0.42, 0.70, 0.30), 0.6)
    crown2 = mat("CrownB2", (0.50, 0.78, 0.36), 0.6)
    sphere(0.72, (0, 0, 1.45), crown, scale=(1, 1, 0.9))
    sphere(0.42, (0.42, -0.2, 1.2), crown2)
    sphere(0.38, (-0.4, 0.15, 1.75), crown2)

PROPS = dict(desk_set=lambda: desk(laptop), terminal_set=lambda: desk(monitor), bookshelf=bookshelf, plant=plant,
             lamp=lamp, tree=tree, flower=flower, window=window, curtain=curtain,
             sofa=sofa, coffee_table=coffee_table, water_cooler=water_cooler,
             hill_a=lambda: hill([(6.0, 3.0, 1.3), (4.2, 2.2, 1.3), (2.4, 1.3, 1.1)]),
             hill_b=lambda: hill([(7.0, 3.4, 1.6), (4.6, 2.4, 1.5)]),
             hill_c=lambda: hill([(4.5, 2.6, 1.2), (3.0, 1.8, 1.3), (1.8, 1.1, 1.0), (1.0, 0.7, 0.7)]),
             tree_b=tree_b)
PROP_OBJS = {}
for name, build in PROPS.items():
    PARTS.clear(); build()
    o = join(name, list(PARTS))
    o.hide_set(True)
    PROP_OBJS[name] = o
    print("PROP", name, len(o.data.vertices))

# ---------------------------------------------------------------- Metal çizici için JSON (spec v4 §4)
# Blender (x, y, z) -> Y-yukarı (x, z, -y). Renkler sRGB 8 bit; alfa = emissive gücü.
YUP = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
BONES = ["Root", "Hips", "Head", "UpperArmL", "ForeArmL", "ThighL", "ShinL", "UpperArmR", "ForeArmR", "ThighR", "ShinR"]
HAIR_CODES = {"HairShort": 1, "HairPigtails": 2, "HairSpiky": 3, "HairBob": 4}
KEYS = {1: (0.30, 0.55, 0.95), 2: (0.99, 0.84, 0.72), 3: (0.35, 0.20, 0.10)}  # tişört, ten, saç

def lin_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

def material_info(m):
    if m is None or not m.node_tree:
        return (0.8, 0.8, 0.8), 0.0
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    c = tuple(b.inputs["Base Color"].default_value[:3])
    return c, float(b.inputs["Emission Strength"].default_value)

def b64(array):
    return base64.b64encode(np.ascontiguousarray(array).tobytes()).decode("ascii")

def mesh_json(objs, villager=False):
    dg = bpy.context.evaluated_depsgraph_get()
    verts, index_of, indices = [], {}, []
    for obj in objs:
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        uv_layer = me.uv_layers.active
        group_names = [g.name for g in obj.vertex_groups]
        hair = HAIR_CODES.get(obj.name, 0)
        world = YUP @ obj.matrix_world
        normal_m = world.to_3x3().inverted().transposed()
        for tri in me.loop_triangles:
            mat = me.materials[tri.material_index] if me.materials else None
            color, emit = material_info(mat)
            part = 0
            if villager:
                if obj.name == "Glasses":
                    part = 4
                else:
                    for code, key in KEYS.items():
                        if all(abs(a - b) < 0.02 for a, b in zip(color, key)):
                            part = code
            rgba = tuple(int(round(lin_to_srgb(c) * 255)) for c in color) + (int(round(min(emit / 4.0, 1.0) * 255)),)
            for corner, loop in zip(range(3), tri.loops):
                vi = tri.vertices[corner]
                p = world @ me.vertices[vi].co
                n = (normal_m @ Vector(tri.split_normals[corner])).normalized()
                uv = tuple(uv_layer.data[loop].uv) if uv_layer else (0.0, 0.0)
                bone = 0
                if villager:
                    groups = me.vertices[vi].groups
                    if groups:
                        name = group_names[max(groups, key=lambda g: g.weight).group]
                        bone = BONES.index(name)
                key = (round(p.x, 5), round(p.y, 5), round(p.z, 5), round(n.x, 3), round(n.y, 3), round(n.z, 3),
                       round(uv[0], 4), round(uv[1], 4), rgba, bone, part, hair)
                if key not in index_of:
                    index_of[key] = len(verts)
                    verts.append((p, n, uv, rgba, bone, part, hair))
                indices.append(index_of[key])
        ev.to_mesh_clear()
    count = len(verts)
    out = {
        "vertexCount": count,
        "positions": b64(np.array([v[0][:] for v in verts], dtype=np.float32).reshape(-1)),
        "normals": b64(np.array([v[1][:] for v in verts], dtype=np.float32).reshape(-1)),
        "uvs": b64(np.array([v[2] for v in verts], dtype=np.float32).reshape(-1)),
        "colors": b64(np.array([v[3] for v in verts], dtype=np.uint8).reshape(-1)),
        "indices": b64(np.array(indices, dtype=np.uint32)),
    }
    if villager:
        out["bones"] = b64(np.array([v[4] for v in verts], dtype=np.uint8))
        out["parts"] = b64(np.array([v[5] for v in verts], dtype=np.uint8))
        out["hair"] = b64(np.array([v[6] for v in verts], dtype=np.uint8))
    return out

# Köylü dinlenme pozunda; klipler kare kare skinning matrisi (Y-yukarı uzayda).
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
villager_json = mesh_json([body, *hairs, glasses], villager=True)
arm.data.pose_position = 'POSE'
CLIP_RANGES = {"idle": (1, 24), "walk": (31, 54), "sitType": (61, 84), "sitDoze": (91, 138), "wave": (141, 164)}
yup_inv = YUP.inverted()
clips = {}
for clip, (first, last) in CLIP_RANGES.items():
    mats = []
    for f in range(first, last + 1):
        scn.frame_set(f)
        bpy.context.view_layer.update()
        for name in BONES:
            pb = arm.pose.bones[name]
            skin = YUP @ arm.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted() @ arm.matrix_world.inverted() @ yup_inv
            mats.extend(skin.col[c][r] for c in range(4) for r in range(4))
    clips[clip] = {"frames": last - first + 1, "matrices": b64(np.array(mats, dtype=np.float32))}
scn.frame_set(1)
art = {"version": 1, "bones": BONES, "clips": clips, "villager": villager_json,
       "props": {name: mesh_json([o]) for name, o in PROP_OBJS.items()}}
with open(os.path.join(OUT, "office-art.json"), "w") as f:
    json.dump(art, f)
print("JSON", os.path.getsize(os.path.join(OUT, "office-art.json")), "villager verts", villager_json["vertexCount"])
print("DONE")
