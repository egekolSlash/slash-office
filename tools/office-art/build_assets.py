# Slash Office varlıkları: iskeletli Animal Crossing tarzı köylü + eşyalar -> Resources/OfficeArt/office-art.json.
# Çalıştır: scripts/build-office-art.sh  (Blender -b --factory-startup --python build_assets.py -- <depo kökü>)
#
# Sözleşme (uygulama buna güvenir, v3 spec §4/§8, v4 spec §4; Core'da OfficeArtFile):
#  - Blender (x, y, z) -> uygulama (x, z, -y), Y yukarı. Köylü -Y'ye (uygulamada +z'ye, kameraya) bakar; ayakları z=0'da.
#  - Köylü mesh'leri: Body, HairShort, HairPigtails, HairSpiky, HairBob, Glasses (saç modeli kodu 1…4, gözlük parça 4).
#  - Değiştirilebilir malzemeler taban rengiyle tanınır: tişört (0.30,0.55,0.95), ten (0.99,0.84,0.72), saç (0.35,0.20,0.10).
#  - Klipler (24 fps): idle 1-24, walk 31-54, sitType 61-84, sitDoze 91-138, wave 141-164 ve v5 aşama 2'nin
#    klipleri 171-638 (CLIP_RANGES; AvatarClip.frames ile aynı).
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

# Eşyalarda küçük parçalar (çiçek, kupa, kalem, düğme…) daha az dilimle: en yakın görünümde bile ekranda birkaç
# düzine piksel; silüet ve yumuşak gölgeleme aynı kalır, köşe sayısı yarıya iner. Köylüde (yakın önizleme) kapalı.
SMALL_PART_LOD = False
def lod(radius, seg, rings):
    if not SMALL_PART_LOD: return seg, rings
    if radius < 0.03: return min(seg, 12), min(rings, 6)
    if radius < 0.06: return min(seg, 16), min(rings, 8)
    return seg, rings

def sphere(r, loc, m, group=None, scale=(1, 1, 1), seg=24, rings=12):
    seg, rings = lod(r * max(scale), seg, rings)
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
    verts, _ = lod(r, verts, 0)
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
sphere(0.022, (0, FY - 0.02, HZ - 0.045), M["skin"], "Head")
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

# ---- ofis hayatı §C2: varyantlar. Her nesne (grup, değer) taşır; çizici seçili olmayanları gizler.
# Gruplar (VillagerVariant): 1 saç, 2 şapka, 3 göz, 4 kaş, 5 ağız, 6 çil, 7 allık, 8 gözlük, 9 saç tepesi, 10 tepe süsü.
VARIANTS = {}
def variant(name, group, value, build):
    PARTS.clear(); build()
    o = join(name, list(PARTS))
    VARIANTS[name] = (group, value)
    return o
M["freckle"] = mat("Freckle", (0.62, 0.38, 0.28), 0.7)
M["tongue"] = mat("Tongue", (0.95, 0.45, 0.50), 0.6)
def eyes_round():
    for s in (-1, 1):
        sphere(0.042, (s * 0.09, FY, HZ), M["eye"], "Head", (0.75, 0.35, 1.0))
        sphere(0.012, (s * 0.09 + 0.012, FY - 0.012, HZ + 0.022), M["shine"], "Head")
def eyes_happy():
    for s in (-1, 1):  # ^ ^
        capsule(0.011, (s * 0.09 - 0.035, FY + 0.005, HZ - 0.01), (s * 0.09, FY - 0.012, HZ + 0.02), M["eye"], "Head")
        capsule(0.011, (s * 0.09, FY - 0.012, HZ + 0.02), (s * 0.09 + 0.035, FY + 0.005, HZ - 0.01), M["eye"], "Head")
def eyes_sleepy():
    for s in (-1, 1):  # yarı kapalı: yassı göz, üstünde ten rengi kapak
        sphere(0.042, (s * 0.09, FY, HZ - 0.012), M["eye"], "Head", (0.8, 0.35, 0.45))
        capsule(0.012, (s * 0.09 - 0.035, FY - 0.006, HZ + 0.004), (s * 0.09 + 0.035, FY - 0.006, HZ + 0.004), M["skin"], "Head")
def brows(r):
    for s in (-1, 1):
        capsule(r, (s * 0.09 - 0.03, FY + 0.012, HZ + 0.07), (s * 0.09 + 0.03, FY + 0.008, HZ + 0.078 + s * 0.004), M["hair"], "Head")
def mouth_smile():
    sphere(0.03, (0, FY + 0.005, HZ - 0.105), M["mouth"], "Head", (1.0, 0.3, 0.45))
def mouth_open():
    sphere(0.036, (0, FY + 0.004, HZ - 0.108), M["mouth"], "Head", (1.1, 0.35, 0.8))
    sphere(0.018, (0, FY - 0.004, HZ - 0.122), M["tongue"], "Head", (1.0, 0.5, 0.5))
def mouth_flat():
    capsule(0.009, (-0.026, FY + 0.004, HZ - 0.105), (0.026, FY + 0.004, HZ - 0.105), M["mouth"], "Head")
def freckles():
    for s in (-1, 1):
        for dx, dz in ((0.0, 0.0), (0.025, 0.012), (0.012, -0.018)):
            sphere(0.008, (s * (0.14 + dx), FY + 0.035, HZ - 0.055 + dz), M["freckle"], "Head")
def blush():
    for s in (-1, 1):
        sphere(0.04, (s * 0.15, FY + 0.04, HZ - 0.07), M["cheek"], "Head", (1.0, 0.35, 0.6))
faces = [
    variant("EyesRound", 3, 1, eyes_round), variant("EyesHappy", 3, 2, eyes_happy), variant("EyesSleepy", 3, 3, eyes_sleepy),
    variant("BrowsThin", 4, 1, lambda: brows(0.008)), variant("BrowsBold", 4, 2, lambda: brows(0.016)),
    variant("MouthSmile", 5, 1, mouth_smile), variant("MouthOpen", 5, 2, mouth_open), variant("MouthFlat", 5, 3, mouth_flat),
    variant("Freckles", 6, 1, freckles), variant("Blush", 7, 1, blush),
]

def fringe():
    for dx in (-0.12, 0.0, 0.12):
        sphere(0.09, (dx, FY + 0.06, HZ + 0.15 - abs(dx) * 0.3), M["hair"], "Head", (1.2, 0.6, 0.8))
HAIR_STYLES = ["short", "pigtails", "spiky", "bob", "curly", "long", "bun"]
def style(value, sides=lambda: None):
    def build():
        fringe(); sides()
    return variant("Hair" + HAIR_STYLES[value - 1].capitalize(), 1, value, build)
hairs = [
    variant("HairCap", 9, 1, lambda: sphere(0.262, (0, 0.03, HZ + 0.05), M["hair"], "Head", (1.03, 1.0, 0.9))),
    style(1),
    style(2, lambda: [sphere(0.1, (s * 0.28, 0.05, HZ - 0.05), M["hair"], "Head", (0.8, 0.8, 1.2)) for s in (-1, 1)]),
    style(3),
    variant("HairSpikyTop", 10, 3, lambda: [sphere(0.075, (dx, 0.04 + dy, HZ + 0.27), M["hair"], "Head", (0.7, 0.7, 1.5))
                                            for dx, dy in ((-0.12, 0.02), (0.0, -0.02), (0.12, 0.02), (0.0, 0.1))]),
    style(4, lambda: [sphere(0.16, (s * 0.2, 0.04, HZ - 0.06), M["hair"], "Head", (0.8, 1.1, 1.3)) for s in (-1, 1)]),
    # Kıvırcık: yanlarda ve arkada küçük bukleler, tepede ayrıca (şapkayla gizlenir).
    # Bukleler yanlardan arkaya (+Y arkadır; yüz −Y'de).
    style(5, lambda: [sphere(0.075, (0.27 * math.sin(t), 0.06 + 0.24 * math.cos(t), HZ - 0.03 + 0.04 * math.cos(2 * t)), M["hair"], "Head")
                      for t in [math.radians(-110 + 220 * i / 6) for i in range(7)]]),
    variant("HairCurlyTop", 10, 5, lambda: [sphere(0.07, (dx, dy, HZ + 0.25), M["hair"], "Head")
                                            for dx, dy in ((-0.13, 0.05), (0.0, 0.0), (0.13, 0.05), (-0.07, 0.15), (0.07, 0.15))]),
    # Uzun: arkada omuzlara inen saç, yanlarda iki tutam.
    style(6, lambda: [sphere(0.2, (0, 0.13, HZ - 0.16), M["hair"], "Head", (1.25, 0.7, 1.45))]
                     + [sphere(0.08, (s * 0.24, -0.02, HZ - 0.16), M["hair"], "Head", (0.8, 0.9, 1.9)) for s in (-1, 1)]),
    style(7),
    variant("HairBunTop", 10, 7, lambda: [sphere(0.11, (0, 0.06, HZ + 0.3), M["hair"], "Head"),
                                          sphere(0.06, (0, 0.05, HZ + 0.22), M["hair"], "Head", (1.4, 1.4, 0.6))]),
]
def beanie():
    knit = mat("Beanie", (0.86, 0.32, 0.32), 0.9)
    sphere(0.275, (0, 0.03, HZ + 0.12), knit, "Head", (1.04, 1.02, 0.8))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.258, minor_radius=0.035, location=(0, 0.03, HZ + 0.11), major_segments=32, minor_segments=10)
    finish(bpy.context.active_object, mat("BeanieRim", (0.95, 0.90, 0.85), 0.9), "Head")
    sphere(0.06, (0, 0.03, HZ + 0.35), mat("BeaniePom", (0.98, 0.95, 0.90), 0.9), "Head")
def cap():
    cloth = mat("Cap", (0.25, 0.45, 0.85), 0.7)
    sphere(0.272, (0, 0.03, HZ + 0.07), cloth, "Head", (1.02, 1.02, 0.8))
    sphere(0.16, (0, FY - 0.03, HZ + 0.11), cloth, "Head", (1.0, 1.1, 0.12))
def headphones():
    band = mat("HeadphoneBand", (0.16, 0.16, 0.18), 0.4)
    # Bant kulaktan kulağa başın üstünden (XZ düzleminde: halkanın ekseni Y).
    bpy.ops.mesh.primitive_torus_add(major_radius=0.29, minor_radius=0.022, location=(0, 0.03, HZ + 0.02),
                                     rotation=(math.radians(90), 0, 0), major_segments=32, minor_segments=8)
    o = bpy.context.active_object; bpy.ops.object.transform_apply(rotation=True); finish(o, band, "Head")
    for s in (-1, 1):
        cyl(0.075, 0.05, (s * 0.28, 0.03, HZ - 0.02), mat("HeadphoneCup", (0.95, 0.50, 0.60), 0.5), rot=(0, math.radians(90), 0))
        PARTS[-1].vertex_groups.new(name="Head").add(range(len(PARTS[-1].data.vertices)), 1.0, 'REPLACE')
hats = [variant("HatBeanie", 2, 1, beanie), variant("HatCap", 2, 2, cap), variant("HatHeadphones", 2, 3, headphones)]
def glasses_build():
    for s in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.058, minor_radius=0.011, location=(s * 0.09, FY - 0.035, HZ),
                                         rotation=(math.radians(90), 0, 0), major_segments=24, minor_segments=8)
        o = bpy.context.active_object; bpy.ops.object.transform_apply(rotation=True); finish(o, M["frame"], "Head")
    capsule(0.008, (-0.035, FY - 0.04, HZ + 0.01), (0.035, FY - 0.04, HZ + 0.01), M["frame"], "Head")
glasses = variant("Glasses", 8, 1, glasses_build)

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
meshes = [body, *faces, *hairs, *hats, glasses]
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
# ---- v5 aşama 2: canlı köylü klipleri (AvatarClip.frames ile aynı kareler)
TYPE = dict(UpperArmL=R(x=-70), UpperArmR=R(x=-70), ForeArmL=R(x=-20), ForeArmR=R(x=-20), Head=R(x=6))
LAP = dict(UpperArmL=R(x=-20), UpperArmR=R(x=-20), ForeArmL=R(x=-55), ForeArmR=R(x=-55))
REST = dict(ForeArmL=R(x=-8), ForeArmR=R(x=-8))
def merge(*ds):
    out = {}
    for d in ds: out.update(d)
    return out
# lookAround 171-218: baş sola ve sağa döner (kemik ekseni etrafında)
for f, y in ((171, 0), (183, 35), (195, 0), (207, -35), (218, 0)):
    key(f, **REST, Head=R(y=y), Hips=up(0.008 * abs(y) / 35))
# sitSip 221-268: sağ el ağza (kahve), baş hafif geriye
SIP = dict(UpperArmR=R(x=-60), ForeArmR=R(x=-115))
key(221, **SIT, **TYPE)
key(231, **merge(SIT, TYPE, SIP, dict(Head=R(x=-4))))
key(250, **merge(SIT, TYPE, SIP, dict(Head=R(x=-10))))
key(259, **merge(SIT, TYPE, SIP, dict(Head=R(x=-4))))
key(268, **SIT, **TYPE)
# sitThink 271-318: el çenede, baş yana eğik
THINK = dict(UpperArmR=R(x=-50), ForeArmR=R(x=-125))
key(271, **SIT, **TYPE)
key(281, **merge(SIT, TYPE, THINK, dict(Head=R(x=4, z=8))))
key(295, **merge(SIT, TYPE, THINK, dict(Head=R(x=6, z=-6))))
key(308, **merge(SIT, TYPE, THINK, dict(Head=R(x=4, z=8))))
key(318, **SIT, **TYPE)
# sitStretch 321-356: iki kol yukarı gerinme
UP = dict(UpperArmL=R(z=150), UpperArmR=R(z=-150), Head=R(x=-10))
key(321, **SIT, **TYPE)
key(333, **merge(SIT, UP))
key(345, **merge(SIT, UP, dict(Head=R(x=-14, z=5))))
key(356, **SIT, **TYPE)
# stretch 361-396: ayakta gerinme
key(361, **REST)
key(373, **UP, Hips=up(0.025))
key(385, **merge(UP, dict(Head=R(x=-12, z=6))), Hips=up(0.03))
key(396, **REST)
# waitTap 401-424: eller belde, sağ ayak yere vurur
HIPS = dict(UpperArmL=R(z=30), UpperArmR=R(z=-30), ForeArmL=R(x=-70), ForeArmR=R(x=-70), Head=R(z=-4))
for f, tap in ((401, 0), (404, 1), (407, 0), (410, 1), (413, 0), (416, 1), (419, 0), (422, 1), (424, 0)):
    key(f, **HIPS, ThighR=R(x=-12 * tap), ShinR=R(x=10 * tap))
# cheer 431-454: çömel, zıpla (kollar yukarı), in
key(431, **REST)
key(435, Root=up(-0.05), ThighL=R(x=-35), ThighR=R(x=-35), ShinL=R(x=60), ShinR=R(x=60), UpperArmL=R(x=20), UpperArmR=R(x=20))
key(441, Root=up(0.18), UpperArmL=R(z=150), UpperArmR=R(z=-150), Head=R(x=-10))
key(447, Root=up(-0.04), ThighL=R(x=-28), ThighR=R(x=-28), ShinL=R(x=50), ShinR=R(x=50), UpperArmL=R(z=120), UpperArmR=R(z=-120))
key(454, **REST)
# inspect 461-508: öne eğilip bakar (bacaklar dik kalsın diye uyluklar telafi eder), sağ el işaret
LEAN = dict(Hips=((0, 0, 0), (20, 0, 0)), ThighL=R(x=-20), ThighR=R(x=-20), UpperArmR=R(x=-35))
key(461, **REST)
key(471, **LEAN, Head=R(x=15))
key(485, **LEAN, Head=R(x=18, z=10))
key(497, **LEAN, Head=R(x=15, z=-6))
key(508, **REST)
# drink 511-546: ayakta bardaktan içer
key(511, **REST)
key(520, **SIP, Head=R(x=-4), ForeArmL=R(x=-8))
key(535, **SIP, Head=R(x=-12), ForeArmL=R(x=-8))
key(546, **REST)
# sitDown 551-562 ve standUp 571-582: ayakta ↔ oturur (kollar kucakta)
key(551, **REST)
key(556, Root=up(0.06), ThighL=R(x=-50), ThighR=R(x=-50), ShinL=R(x=55), ShinR=R(x=55), UpperArmL=R(x=-25), UpperArmR=R(x=-25))
key(562, **SIT, **LAP)
key(571, **SIT, **LAP)
key(577, Root=up(0.06), ThighL=R(x=-50), ThighR=R(x=-50), ShinL=R(x=55), ShinR=R(x=55), UpperArmL=R(x=-25), UpperArmR=R(x=-25))
key(582, **REST)
# sofaSit 591-638: koltukta (tabureden 4 cm alçak) arkasına yaslanmış, baş yavaşça bakınır
SOFA = dict(Root=up(0.12), ThighL=R(x=-90), ThighR=R(x=-90), ShinL=R(x=90), ShinR=R(x=90),
            UpperArmL=R(x=-15, z=12), UpperArmR=R(x=-15, z=-12), ForeArmL=R(x=-45), ForeArmR=R(x=-45))
for f, y in ((591, 0), (603, 12), (615, 0), (627, -12), (638, 0)):
    key(f, **SOFA, Head=R(x=-4, y=y), Hips=((0, 0.006 * abs(y) / 12, 0), (-6, 0, 0)))
# ---- ofis hayatı: masa başı (oturarak) ve eşya klipleri (AvatarClip.frames ile aynı kareler)
# sitDraw 641-688: tablete çizer (sağ ön kol küçük daireler), arada kalemi kaldırıp bakar
DRAW = dict(UpperArmL=R(x=-55), ForeArmL=R(x=-30), UpperArmR=R(x=-62), Head=R(x=14))
for f, (a, b) in zip(range(641, 677, 4), ((0, 0), (8, 6), (0, 10), (-8, 6), (0, 0), (8, -6), (0, -10), (-8, -6), (0, 0))):
    key(f, **merge(SIT, DRAW, dict(ForeArmR=R(x=-25 + a, z=b))))
key(682, **merge(SIT, DRAW, dict(ForeArmR=R(x=-60), Head=R(x=2, z=6))))
key(688, **merge(SIT, DRAW, dict(ForeArmR=R(x=-25))))
# sitWrite 691-738: sol el kâğıdı tutar, sağ el satır satır yazar
WRITE = dict(UpperArmL=R(x=-50, z=10), ForeArmL=R(x=-40), UpperArmR=R(x=-58), Head=R(x=16, z=-4))
for i, f in enumerate(range(691, 735, 4)):
    key(f, **merge(SIT, WRITE, dict(ForeArmR=R(x=-28, z=-12 + 6 * (i % 5)))))
key(738, **merge(SIT, WRITE, dict(ForeArmR=R(x=-28, z=-12))))
# sitRead 741-788: kâğıdı iki elle göz hizasına kaldırıp okur, baş satırları izler
READ = dict(UpperArmL=R(x=-75, z=8), UpperArmR=R(x=-75, z=-8), ForeArmL=R(x=-80), ForeArmR=R(x=-80))
key(741, **SIT, **TYPE)
for f, y in ((751, 6), (763, -6), (775, 6)):
    key(f, **merge(SIT, READ, dict(Head=R(x=8, y=y))))
key(788, **SIT, **TYPE)
# readBook 791-862 (döngü): ayakta kitabı göğüs hizasında tutar, okur, ortada sayfa çevirir
BOOK = dict(UpperArmL=R(x=-55, z=10), UpperArmR=R(x=-55, z=-10), ForeArmL=R(x=-75), ForeArmR=R(x=-75))
key(791, **merge(BOOK, dict(Head=R(x=18, y=4))))
key(809, **merge(BOOK, dict(Head=R(x=18, y=-4))))
key(822, **merge(BOOK, dict(Head=R(x=16), ForeArmR=R(x=-75, z=-35))))
key(830, **merge(BOOK, dict(Head=R(x=16), ForeArmR=R(x=-75, z=20))))
key(845, **merge(BOOK, dict(Head=R(x=18, y=4))))
key(862, **merge(BOOK, dict(Head=R(x=18, y=4))))
# playArcade 865-912 (döngü): eller öndeki kumandada, hızlı kol ve beden hareketi
ARC = dict(UpperArmL=R(x=-62, z=8), UpperArmR=R(x=-62, z=-8), Head=R(x=4))
for i, f in enumerate(range(865, 913, 4)):
    j = (-1) ** i
    key(f, **merge(ARC, dict(ForeArmL=R(x=-30 + 10 * j, z=8 * j), ForeArmR=R(x=-30 - 12 * j),
                             Hips=((0, 0.008 * (i % 2), 0), (0, 4 * j, 0)))))
key(912, **merge(ARC, dict(ForeArmL=R(x=-30), ForeArmR=R(x=-30))))
# drawBoard 915-962 (döngü): sağ kol öne-yukarı, tahtada yana çizer; baş çizgiyi izler
for f, s_ in ((915, -1), (927, 1), (939, -1), (951, 1), (962, -1)):
    key(f, UpperArmR=R(x=-125, z=-20 * s_), ForeArmR=R(x=-20), ForeArmL=R(x=-8), Head=R(x=-8, y=8 * s_))
# stepBackLook 965-1012: tahtadan geri çekilir, el çenede bakar, geri gelir
key(965, UpperArmR=R(x=-125), ForeArmR=R(x=-20), ForeArmL=R(x=-8), Head=R(x=-8))
key(977, Root=((0, 0, -0.18), Z), **THINK, Head=R(x=-6, z=8))
key(1000, Root=((0, 0, -0.18), Z), **THINK, Head=R(x=-6, z=-6))
key(1012, UpperArmR=R(x=-125), ForeArmR=R(x=-20), ForeArmL=R(x=-8), Head=R(x=-8))
# brewCoffee 1015-1062: makineye uzanıp düğmeye basar, bekler, bardağı alıp göğse getirir
key(1015, **REST)
key(1023, UpperArmR=R(x=-85), ForeArmR=R(x=-10), ForeArmL=R(x=-8), Head=R(x=8))
key(1027, UpperArmR=R(x=-85), ForeArmR=R(x=-25), ForeArmL=R(x=-8), Head=R(x=8))
key(1040, **merge(HIPS, dict(Head=R(z=-6))))
key(1050, UpperArmR=R(x=-70), ForeArmR=R(x=-20), ForeArmL=R(x=-8), Head=R(x=10))
key(1062, UpperArmR=R(x=-40), ForeArmR=R(x=-100), ForeArmL=R(x=-8), Head=R(x=-4))
scn.frame_start, scn.frame_end = 1, 1062

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
DEFAULT_SHOWN = {"HairCap", "HairShort", "EyesRound", "MouthSmile", "Blush"}
for h in [*faces, *hairs, *hats, glasses]: h.hide_render = h.name not in DEFAULT_SHOWN
for name, frame in (("idle", 12), ("walk", 37), ("sitType", 64), ("sitDoze", 115), ("wave", 147),
                    ("lookAround", 183), ("sitSip", 250), ("sitThink", 295), ("sitStretch", 340), ("stretch", 380),
                    ("waitTap", 404), ("cheer", 441), ("inspect", 485), ("drink", 535), ("sitDown", 556), ("sofaSit", 603),
                    ("sitDraw", 653), ("sitWrite", 703), ("sitRead", 763), ("readBook", 826), ("playArcade", 877),
                    ("drawBoard", 927), ("stepBackLook", 990), ("brewCoffee", 1025)):
    scn.frame_set(frame); scn.render.filepath = os.path.join(PREVIEW, f"pose_{name}.png"); bpy.ops.render.render(write_still=True)
# Ofis hayatı klipleri yandan (+X): kolların ileri-yukarı hareketi okunur.
cam.location = Vector((5, 0, 0.6)); cam.rotation_euler = (Vector((0, 0, 0.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cd.ortho_scale = 1.6
for name, frame in (("sitDraw", 653), ("sitWrite", 703), ("sitRead", 763), ("readBook", 826), ("playArcade", 877),
                    ("drawBoard", 927), ("stepBackLook", 990), ("brewCoffee", 1025), ("brewCoffee2", 1062)):
    scn.frame_set(frame); scn.render.filepath = os.path.join(PREVIEW, f"side_{name}.png"); bpy.ops.render.render(write_still=True)
# Varyantlar önden (yüz −Y'ye bakar): saç modelleri, şapkalar, yüz kombinasyonları.
cam.location = Vector((0, -5, 0.9)); cam.rotation_euler = (Vector((0, 0, 0.9)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cd.ortho_scale = 0.75
scn.frame_set(1)
ALLV = [*faces, *hairs, *hats, glasses]
def show(names, file):
    for h in ALLV: h.hide_render = h.name not in names
    scn.render.filepath = os.path.join(PREVIEW, file); bpy.ops.render.render(write_still=True)
base = {"EyesRound", "MouthSmile", "Blush"}
for i, st in enumerate(HAIR_STYLES):
    cap_name = "Hair" + st.capitalize()
    top = {"spiky": "HairSpikyTop", "curly": "HairCurlyTop", "bun": "HairBunTop"}.get(st)
    show(base | {"HairCap", cap_name} | ({top} if top else set()), f"variant_hair{i + 1}.png")
for hat in ("HatBeanie", "HatCap", "HatHeadphones"):
    show(base | {"HairBob", hat}, f"variant_{hat}.png")
show({"EyesHappy", "BrowsThin", "MouthOpen", "Freckles", "Blush", "HairCap", "HairShort", "Glasses"}, "variant_face1.png")
show({"EyesSleepy", "BrowsBold", "MouthFlat", "HairCap", "HairLong"}, "variant_face2.png")
for h in [*faces, *hairs, *hats, glasses]: h.hide_render = False
bpy.data.objects.remove(cam, do_unlink=True)
scn.frame_set(1)

# ---------------------------------------------------------------- eşyalar
SMALL_PART_LOD = True
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
    # Ofis hayatı: masa büyüdü (0.95 × 0.55); köylü +Y'deki taburede, −Y'ye bakar. Dünyada masa koridora döner.
    paper = mat("Paper", (0.97, 0.96, 0.92), 0.6)
    box((0.95, 0.55, 0.05), (0, 0, 0.54), P["woodL"], 0.02)
    for dx in (-0.42, 0.42):
        for dy in (-0.22, 0.22): cyl(0.03, 0.52, (dx, dy, 0.26), P["wood"])
    device()
    cyl(0.04, 0.09, (0.36, 0.06, 0.61), P["mug"], 0.01)
    box((0.17, 0.23, 0.03), (-0.31, 0.08, 0.58), paper, 0.005)
    box((0.17, 0.23, 0.012), (-0.30, 0.07, 0.601), paper, 0.004)
    cyl(0.032, 0.09, (-0.38, -0.17, 0.61), P["dark"], 0.008)
    for dx, c in ((-0.39, "book1"), (-0.37, "book2")):
        cyl(0.006, 0.12, (dx, -0.17, 0.68), P[c])
    cyl(0.05, 0.015, (0.38, -0.18, 0.572), P["dark"], 0.004)
    cyl(0.008, 0.22, (0.38, -0.18, 0.68), P["dark"])
    bpy.ops.mesh.primitive_cone_add(radius1=0.07, radius2=0.03, depth=0.08, location=(0.38, -0.15, 0.79), vertices=20)
    finish(bpy.context.active_object, P["shade"])
    cyl(0.035, 0.06, (0.22, -0.19, 0.6), P["pot"], 0.006)
    sphere(0.05, (0.22, -0.19, 0.66), P["leaf"])
    cyl(0.19, 0.09, (0, 0.40, 0.415), P["cushion"], 0.03)  # tabure: üstü 0.46
    for a in range(3):
        ang = a * 2.094
        cyl(0.025, 0.38, (0.12 * math.cos(ang), 0.40 + 0.12 * math.sin(ang), 0.19), P["wood"])
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
def cliff(tiers, seed):
    # AC: New Horizons tarzı kayalık: yuvarlatılmış dikdörtgen (süper elips) taban, hafif dalgalı kenar, dik kaya yüzü,
    # düz çimen tepe. Katlar arkaya (Blender +Y, uygulamada −z) doğru kaydırılır. z'de (Blender y) 0,6 m dilimlenir.
    import bmesh
    rock = mat("CliffRock", (0.60, 0.50, 0.38), 0.9)
    rockDark = mat("CliffRockDark", (0.50, 0.41, 0.31), 0.9)
    top = mat("CliffTop", (0.45, 0.72, 0.32), 0.9)
    z = 0.0
    for t, (rx, ry, h, dy) in enumerate(tiers):
        me = bpy.data.meshes.new(f"cliff{t}")
        bm = bmesh.new()
        n = 44
        ring = []
        for i in range(n):
            a = 2 * math.pi * i / n
            c, s_ = math.cos(a), math.sin(a)
            r = (abs(c) ** 4 + abs(s_) ** 4) ** -0.25
            r *= 1 + 0.05 * math.sin(3 * a + seed + t) + 0.03 * math.sin(7 * a + 2 * seed)
            ring.append(bm.verts.new((rx * r * c, dy + ry * r * s_, z)))
        face = bm.faces.new(ring)
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, 0, h), verts=moved)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        o = bpy.data.objects.new(f"cliff{t}", me); bpy.context.collection.objects.link(o)
        for m in (rock, top, rockDark): o.data.materials.append(m)
        bpy.context.view_layer.objects.active = o
        bv = o.modifiers.new("Bevel", "BEVEL"); bv.width = 0.18; bv.segments = 3; bv.limit_method = 'ANGLE'
        bpy.ops.object.modifier_apply(modifier=bv.name)
        bpy.ops.object.mode_set(mode='EDIT')
        k = -math.ceil((ry + abs(dy) + 1) / 0.6)
        while k * 0.6 < ry + abs(dy) + 1:
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.bisect(plane_co=(0, k * 0.6, 0), plane_no=(0, 1, 0))
            k += 1
        # Kaya yüzünde yatay bant: alt üçte bir koyu.
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.bisect(plane_co=(0, 0, z + h * 0.35), plane_no=(0, 0, 1))
        bpy.ops.object.mode_set(mode='OBJECT')
        for poly in o.data.polygons:
            if poly.normal.z > 0.6: poly.material_index = 1
            elif poly.center.z < z + h * 0.35: poly.material_index = 2
            else: poly.material_index = 0
        bpy.ops.object.shade_flat()
        PARTS.append(o)
        z += h
def cedar():
    # AC'deki sedir: ince gövde, üst üste dar koniler.
    cyl(0.08, 0.6, (0, 0, 0.3), P["trunk"])
    needles = mat("Cedar", (0.20, 0.46, 0.30), 0.7)
    needles2 = mat("Cedar2", (0.26, 0.54, 0.34), 0.7)
    for i, (z0, r, h) in enumerate(((0.5, 0.62, 0.8), (0.95, 0.5, 0.75), (1.35, 0.38, 0.7), (1.72, 0.25, 0.6))):
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=0.02, depth=h, location=(0, 0, z0 + h / 2), vertices=20)
        finish(bpy.context.active_object, needles if i % 2 == 0 else needles2)
def tree_b():
    cyl(0.11, 1.0, (0, 0, 0.4), P["trunk"])
    crown = mat("CrownB", (0.42, 0.70, 0.30), 0.6)
    crown2 = mat("CrownB2", (0.50, 0.78, 0.36), 0.6)
    sphere(0.72, (0, 0, 1.45), crown, scale=(1, 1, 0.9))
    sphere(0.42, (0.42, -0.2, 1.2), crown2)
    sphere(0.38, (-0.4, 0.15, 1.75), crown2)

def arcade():
    # +X'e bakar: kabin, eğik ekran, kumanda paneli, çubuk ve düğmeler, ışıklı başlık.
    body = mat("ArcadeBody", (0.42, 0.30, 0.78), 0.5)
    side = mat("ArcadeSide", (0.98, 0.45, 0.62), 0.5)
    scr = mat("ArcadeScreen", (0.05, 0.05, 0.08), 0.2, emit=(0.45, 0.85, 1.0), es=2.2)
    marquee = mat("ArcadeMarquee", (1.0, 0.85, 0.3), 0.4, emit=(1.0, 0.8, 0.35), es=2.0)
    box((0.5, 0.56, 1.45), (0, 0, 0.725), body, 0.03)
    for dy in (-0.285, 0.285): box((0.48, 0.02, 0.5), (0, dy, 0.55), side, 0.01)
    box((0.03, 0.44, 0.34), (0.255, 0, 1.13), scr, 0)
    box((0.24, 0.52, 0.07), (0.33, 0, 0.92), P["dark"], 0.02)
    cyl(0.012, 0.08, (0.38, -0.12, 0.99), P["dark"])
    sphere(0.028, (0.38, -0.12, 1.04), mat("ArcadeBall", (0.95, 0.30, 0.30), 0.3))
    for dy, c in ((0.02, (0.35, 0.75, 0.98)), (0.09, (1.0, 0.85, 0.3)), (0.16, (0.45, 0.85, 0.45))):
        cyl(0.022, 0.025, (0.38, dy, 0.965), mat(f"ArcadeBtn{dy}", c, 0.3), 0.005)
    box((0.08, 0.56, 0.16), (0.21, 0, 1.38), marquee, 0.01)
def whiteboard():
    # +X'e bakar, ayaklı (arka duvarı alçak odalarda da durur): çerçeve, beyaz yüzey, karalamalar, kalem rafı.
    alu = mat("BoardFrame", (0.78, 0.80, 0.82), 0.3)
    white = mat("BoardWhite", (0.98, 0.98, 0.97), 0.2)
    for dy in (-0.6, 0.6):
        cyl(0.02, 1.56, (0, dy, 0.78), alu)
        box((0.42, 0.05, 0.03), (0, dy, 0.015), alu, 0.01)
    box((0.04, 1.24, 0.82), (0, 0, 1.16), alu, 0.01)
    box((0.02, 1.14, 0.72), (0.022, 0, 1.16), white, 0)
    for dy, dz, w, c in ((-0.35, 1.38, 0.32, (0.25, 0.45, 0.85)), (-0.3, 1.28, 0.22, (0.25, 0.45, 0.85)),
                         (0.1, 1.36, 0.4, (0.85, 0.30, 0.30)), (0.2, 1.05, 0.3, (0.30, 0.65, 0.35)),
                         (-0.2, 1.0, 0.26, (0.85, 0.30, 0.30)), (0.32, 1.22, 0.16, (0.25, 0.45, 0.85))):
        box((0.005, w, 0.018), (0.034, dy, dz), mat(f"Ink{c}", c, 0.4), 0)
    box((0.09, 0.62, 0.025), (0.055, 0, 0.77), alu, 0.005)
    for dy, c in ((-0.1, (0.25, 0.45, 0.85)), (0.0, (0.85, 0.30, 0.30)), (0.1, (0.30, 0.65, 0.35))):
        cyl(0.01, 0.1, (0.07, dy, 0.79), mat(f"Marker{c}", c, 0.4))
def coffee_machine():
    # +X'e bakar: tezgâh, üstünde makine, damlama ızgarası, bardaklar.
    box((0.45, 0.56, 0.8), (0, 0, 0.4), P["woodL"], 0.02)
    box((0.47, 0.58, 0.03), (0, 0, 0.815), P["wood"], 0.01)
    box((0.28, 0.26, 0.4), (-0.02, -0.05, 1.03), P["dark"], 0.03)
    box((0.02, 0.2, 0.12), (0.125, -0.05, 1.12), mat("MachineLed", (0.1, 0.1, 0.1), 0.2, emit=(0.4, 1.0, 0.6), es=1.5), 0)
    box((0.12, 0.08, 0.04), (0.1, -0.05, 0.95), P["dark"], 0.01)
    box((0.14, 0.16, 0.02), (0.1, -0.05, 0.84), mat("Drip", (0.7, 0.7, 0.72), 0.3), 0.005)
    cyl(0.035, 0.07, (0.1, -0.05, 0.885), P["mug"], 0.008)
    for i in range(3): cyl(0.035, 0.07, (0.02, 0.17, 0.865 + 0.06 * i), P["mug"], 0.008)

PROPS = dict(desk_set=lambda: desk(laptop), terminal_set=lambda: desk(monitor), bookshelf=bookshelf, plant=plant,
             lamp=lamp, tree=tree, flower=flower, window=window, curtain=curtain,
             sofa=sofa, coffee_table=coffee_table, water_cooler=water_cooler,
             cliff_a=lambda: cliff([(5.0, 2.4, 1.3, 0.0), (3.4, 1.6, 1.2, 0.9)], 1.0),
             cliff_b=lambda: cliff([(6.5, 2.8, 1.5, 0.0), (4.2, 1.8, 1.3, 1.1)], 2.3),
             cliff_c=lambda: cliff([(4.0, 2.2, 1.2, 0.0), (2.6, 1.4, 1.1, 0.8), (1.6, 0.9, 0.9, 1.3)], 3.7),
             tree_b=tree_b, cedar=cedar, arcade=arcade, whiteboard=whiteboard, coffee_machine=coffee_machine)
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
KEYS = {1: (0.30, 0.55, 0.95), 2: (0.99, 0.84, 0.72), 3: (0.35, 0.20, 0.10),  # tişört, ten, saç
        6: (0.25, 0.30, 0.45), 7: (0.55, 0.32, 0.20)}                         # pantolon, ayakkabı

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
        vgroup, vvalue = VARIANTS.get(obj.name, (0, 0))
        world = YUP @ obj.matrix_world
        normal_m = world.to_3x3().inverted().transposed()
        for tri in me.loop_triangles:
            mat = me.materials[tri.material_index] if me.materials else None
            color, emit = material_info(mat)
            part = 0
            if villager:
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
                       round(uv[0], 4), round(uv[1], 4), rgba, bone, part, vgroup, vvalue)
                if key not in index_of:
                    index_of[key] = len(verts)
                    verts.append((p, n, uv, rgba, bone, part, vgroup, vvalue))
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
        out["variantGroups"] = b64(np.array([v[6] for v in verts], dtype=np.uint8))
        out["variantValues"] = b64(np.array([v[7] for v in verts], dtype=np.uint8))
    return out

# Köylü dinlenme pozunda; klipler kare kare skinning matrisi (Y-yukarı uzayda).
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
villager_json = mesh_json(meshes, villager=True)
arm.data.pose_position = 'POSE'
CLIP_RANGES = {"idle": (1, 24), "walk": (31, 54), "sitType": (61, 84), "sitDoze": (91, 138), "wave": (141, 164),
               "lookAround": (171, 218), "sitSip": (221, 268), "sitThink": (271, 318), "sitStretch": (321, 356),
               "stretch": (361, 396), "waitTap": (401, 424), "cheer": (431, 454), "inspect": (461, 508),
               "drink": (511, 546), "sitDown": (551, 562), "standUp": (571, 582), "sofaSit": (591, 638),
               "sitDraw": (641, 688), "sitWrite": (691, 738), "sitRead": (741, 788), "readBook": (791, 862),
               "playArcade": (865, 912), "drawBoard": (915, 962), "stepBackLook": (965, 1012), "brewCoffee": (1015, 1062)}
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
