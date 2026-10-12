# Slash Office eşyaları (masa takımı, kitaplık, koltuk, ağaçlar, kayalıklar…) -> Resources/OfficeArt/office-art.json.
# Çalıştır: scripts/build-office-art.sh  (Blender -b --factory-startup --python build_assets.py -- <depo kökü>)
#
# Sözleşme (uygulama buna güvenir; Core'da OfficeArtFile):
#  - Blender (x, y, z) -> uygulama (x, z, -y), Y yukarı. Renkler sRGB 8 bit, alfa = emissive gücü / 4.
#  - Eşyalar orijinde, zeminde. Masa takımında tabure +Y tarafında (uygulamada -z) y=+0.32 (DeskGeometry.seatOffset).
#    Masa üstü 0.565; tabure üstü 0.46.
#    Duvara yaslanan eşyalar (kitaplık, pencere, perde) +X'e bakar.
#  - Çiçek başı taban rengi (1.0,0.42,0.48): uygulama renk çeşitler.
#  - Köylüler ayrı: karakter paketi (tools/character, Resources/Character). Dekor eşyaları: tools/furniture.
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

def mesh_json(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    verts, index_of, indices = [], {}, []
    for obj in objs:
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        uv_layer = me.uv_layers.active
        world = YUP @ obj.matrix_world
        normal_m = world.to_3x3().inverted().transposed()
        for tri in me.loop_triangles:
            mat = me.materials[tri.material_index] if me.materials else None
            color, emit = material_info(mat)
            rgba = tuple(int(round(lin_to_srgb(c) * 255)) for c in color) + (int(round(min(emit / 4.0, 1.0) * 255)),)
            for corner, loop in zip(range(3), tri.loops):
                vi = tri.vertices[corner]
                p = world @ me.vertices[vi].co
                n = (normal_m @ Vector(tri.split_normals[corner])).normalized()
                uv = tuple(uv_layer.data[loop].uv) if uv_layer else (0.0, 0.0)
                key = (round(p.x, 5), round(p.y, 5), round(p.z, 5), round(n.x, 3), round(n.y, 3), round(n.z, 3),
                       round(uv[0], 4), round(uv[1], 4), rgba)
                if key not in index_of:
                    index_of[key] = len(verts)
                    verts.append((p, n, uv, rgba))
                indices.append(index_of[key])
        ev.to_mesh_clear()
    return {
        "vertexCount": len(verts),
        "positions": b64(np.array([v[0][:] for v in verts], dtype=np.float32).reshape(-1)),
        "normals": b64(np.array([v[1][:] for v in verts], dtype=np.float32).reshape(-1)),
        "uvs": b64(np.array([v[2] for v in verts], dtype=np.float32).reshape(-1)),
        "colors": b64(np.array([v[3] for v in verts], dtype=np.uint8).reshape(-1)),
        "indices": b64(np.array(indices, dtype=np.uint32)),
    }

art = {"version": 2, "props": {name: mesh_json([o]) for name, o in PROP_OBJS.items()}}
with open(os.path.join(OUT, "office-art.json"), "w") as f:
    json.dump(art, f)
print("JSON", os.path.getsize(os.path.join(OUT, "office-art.json")), "props", len(PROP_OBJS))
print("DONE")
