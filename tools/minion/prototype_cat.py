# Deneme v2 (atılacak): sıfırdan kedi minyonu. Döküm kedisi yalnız yan yana referans olarak çizilir.
# Blender -b --factory-startup --python cat_v2.py -- <dae> <ac-import klasörü> <çıktı önek> <yaw>...
import math, os, sys

argv = sys.argv[sys.argv.index("--") + 1:]
DAE, IMPORT_DIR, OUT, YAWS = argv[0], argv[1], argv[2], [float(a) for a in argv[3:]] or [0.0]
sys.path.insert(0, IMPORT_DIR)
import dae  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


DROP = 0.75  # iki modelde de (referans dahil, adil ölçüm için) bacak kısaltma: kalça (y=2.6) altı sıkışır, üstü aşağı kayar


def squash(y):
    return y * (2.6 - DROP) / 2.6 if y < 2.6 else y - DROP


def B(p):  # döküm (x, y yukarı, z ileri) -> Blender (x, -z, y)
    return Vector((p[0], -p[2], squash(p[1])))


def bsdf_of(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def mat(name, color, rough=0.7):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = bsdf_of(m)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Base Color"].default_value = (*color, 1)
    return m


def link(ob, root):
    bpy.context.scene.collection.objects.link(ob) if ob.name not in bpy.context.scene.collection.objects else None
    ob.parent = root


# ---------------- referans ----------------
def reference(root):
    doc = dae.Document(DAE)
    folder = os.path.dirname(DAE)
    texmap = {"mBody": "mBody_Alb.png", "mCapVis": "mBody_Alb.png", "mEye": "mEye_Alb.0.png", "mMouth": "mMouth_Alb.0.png"}
    for gid, g in doc.geometries.items():
        prim = g.primitives[0]
        if prim.material not in texmap:
            continue
        P = g.positions
        verts = [B(P[i:i + 3]) for i in range(0, len(P), 3)]
        faces = [tuple(c[0] for c in prim.corners[i:i + 3]) for i in range(0, len(prim.corners), 3)]
        me = bpy.data.meshes.new(gid)
        me.from_pydata(verts, [], faces)
        uvdata, stride = g.uvs
        layer = me.uv_layers.new()
        for li, c in enumerate(prim.corners):
            layer.data[li].uv = (uvdata[c[2] * stride], uvdata[c[2] * stride + 1])
        for poly in me.polygons:
            poly.use_smooth = True
        m = bpy.data.materials.new(prim.material)
        m.use_nodes = True
        b = bsdf_of(m)
        b.inputs["Roughness"].default_value = 0.7
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(folder, texmap[prim.material]))
        m.node_tree.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        if prim.material in ("mEye", "mMouth"):
            m.node_tree.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
            m.surface_render_method = "BLENDED"
        me.materials.append(m)
        ob = bpy.data.objects.new(gid, me)
        link(ob, root)


# ---------------- bizim kedi ----------------
FUR = tuple(c ** 2.2 for c in (0.639, 0.341, 0.914))  # malzeme doğrusal
SPOT = (0.478, 0.055, 0.941)  # dokuya sRGB yazılır
CREAM = (1.0, 0.88, 0.70)
PINK = (0.97, 0.55, 0.60)
SHIRT = (0.16, 0.52, 0.58)


def face_texture(path, size=1024):
    """Yüz dokusu (kendi çizimimiz): ön projeksiyon uzayında (u: x, v: y), alfa = boya."""
    u, v = np.meshgrid(np.linspace(-1, 1, size), np.linspace(-1, 1, size))
    rgba = np.zeros((size, size, 4), np.float32)

    def paint(mask, color, a=1.0):
        m = np.clip(mask, 0, 1)[..., None] * a
        rgba[..., :3] = rgba[..., :3] * (1 - m) + np.array(color) * m
        rgba[..., 3:] = rgba[..., 3:] * (1 - m) + m

    def ell(cx, cy, rx, ry, soft=0.012):
        d = np.sqrt(((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2)
        return np.clip((1 - d) / (soft / min(rx, ry)), 0, 1)

    # büyük yumuşak lekeler (alın-tepe sağda, iki yanak kenarında)
    for cx, cy, rx, ry in [(0.45, 0.78, 0.55, 0.42), (-0.95, -0.15, 0.30, 0.45), (0.98, -0.25, 0.25, 0.4)]:
        paint(ell(cx, cy, rx, ry, 0.08), SPOT)
    INK = (0.16, 0.10, 0.20)
    for s in (1, -1):
        ex, ey = s * 0.40, 0.02
        paint(ell(ex, ey, 0.25, 0.15), INK)                             # göz çerçevesi (yanlarda kalın)
        sclera = ell(ex, ey - 0.01, 0.195, 0.115)
        paint(sclera, (0.93, 0.90, 0.62))                               # sarımsı göz akı
        tilt = ey + 0.025 + s * (u - ex) * 0.10
        lid = ell(ex, ey, 0.26, 0.17, 0.004) * np.clip((v - tilt) / 0.006, 0, 1)
        paint(lid, tuple(c ** (1 / 2.2) for c in FUR))                  # yarı kapalı kapak
        line = ell(ex, ey, 0.26, 0.17, 0.004) * np.clip(1 - np.abs(v - tilt) / 0.024, 0, 1)
        paint(line, INK)
        paint(ell(ex + s * 0.25, ey + 0.025, 0.045, 0.026), INK)        # dış köşe ucu
        # göz bebeği: kapağın altındaki görünen bölgede tam oval + parıltı
        pc = (ex - s * 0.03, ey - 0.04)
        # kedi göz bebeği: kalın dikey çizgi, kapak çizgisinden göz akının dibine kadar
        bar = np.clip((0.0455 - np.abs(u - pc[0])) / 0.004, 0, 1)  # düz kenarlı dikey şerit
        paint(bar * sclera * (v < tilt), INK)
    # ağız: geniş, sığ, hafif yan gülüş çizgisi
    x = u
    curve = -0.40 + 0.10 * (x / 0.33) ** 2 + 0.03 * x
    mouth = np.clip(1 - np.abs(v - curve) / 0.016, 0, 1) * (np.abs(x) < 0.33)
    paint(mouth, INK)
    img = bpy.data.images.new("face", size, size, alpha=True)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


HEAD_C = np.array([0.0, 8.95, -0.1])
HEAD_R = np.array([3.6, 2.88, 3.05])


def head(root):
    """Yumuşak kare kafa: süper-elipsoid (alt yanaklar dolgun, tepe hafif düz), tek mesh."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=40, radius=1)
    ob = bpy.context.active_object
    me = ob.data
    co = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    p = co.reshape(-1, 3)
    p = np.c_[p[:, 0], p[:, 2], -p[:, 1]]  # Blender -> döküm uzayı (x, y yukarı, z ileri)
    n = 2.35  # süper-elips üssü: 2 = küre, büyüdükçe kare
    norm = (np.abs(p) ** n).sum(1) ** (1 / n)
    q = p / norm[:, None]
    y = q[:, 1]
    widen = 1 - 0.03 * np.clip(-y, 0, 1) + 0.0 * np.clip(y, 0, 1)   # alt geniş, üst biraz dar
    q[:, 0] *= widen
    q[:, 2] *= 1 - 0.06 * np.clip(-y, 0, 1)                           # çene öne dolgun
    w = q * HEAD_R + HEAD_C
    w[:, 2] -= 0.15 * q[:, 1]  # tepe öne, çene geride: alın öne çıkık kafa
    # ağız/burun bölgesi hafif kabarık
    muzzle = np.exp(-((q[:, 0] / 0.38) ** 2 + ((q[:, 1] + 0.35) / 0.28) ** 2)) * np.clip(q[:, 2], 0, 1)
    w[:, 2] += muzzle * 0.2
    me.vertices.foreach_set("co", np.c_[w[:, 0], -w[:, 2], w[:, 1]].ravel())
    me.update()
    bpy.ops.object.shade_smooth()
    # yüz UV'si: önden düz izdüşüm
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="face")
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = ((v.x / HEAD_R[0] + 1) / 2, ((v.z - HEAD_C[1]) / HEAD_R[1] + 1) / 2)
    # malzeme: kürk + yüz dokusu (yalnız ön yarıda; arka yarı dokuyu tekrar etmesin)
    m = mat("head", FUR)
    nt = m.node_tree
    b = bsdf_of(m)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = face_texture(os.path.join(HERE, "face.png"))
    tex.extension = "CLIP"
    geo = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    front = nt.nodes.new("ShaderNodeMath"); front.operation = "MULTIPLY"; front.use_clamp = True
    front.inputs[1].default_value = -3.0  # yüze bakan yüzeyde tam, yanlara doğru söner (düz izdüşüm yanlarda uzamasın)   # Blender -y = ön; nesne konumuna göre değil dünya: kökler y=0'da
    nt.links.new(sep.outputs["Y"], front.inputs[0])
    amask = nt.nodes.new("ShaderNodeMath"); amask.operation = "MULTIPLY"
    nt.links.new(tex.outputs["Alpha"], amask.inputs[0])
    nt.links.new(front.outputs[0], amask.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*FUR, 1)
    nt.links.new(amask.outputs[0], mix.inputs[0])
    nt.links.new(tex.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    me.materials.append(m)
    link(ob, root)
    return ob


def ears(root):
    """Sivri üçgen kulaklar: önü düz üçgen prizma, kenarlar hafif yuvarlatılmış; içi kırmızı-turuncu."""
    def prism(name, w, h, d, color):
        hw = w / 2
        verts = [(-hw, 0, 0), (hw, 0, 0), (0, 0, h), (-hw, d, 0), (hw, d, 0), (0, d * 0.4, h)]
        faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], faces)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        bev = ob.modifiers.new("b", "BEVEL"); bev.width = min(d, w) * 0.22; bev.segments = 4
        sub = ob.modifiers.new("s", "SUBSURF"); sub.levels = sub.render_levels = 1
        ob.data.materials.append(mat(name, color))
        for poly in me.polygons:
            poly.use_smooth = True
        return ob
    for s in (1, -1):
        for inner in (False, True):
            ob = prism("ear_in" if inner else "ear", 1.7 if inner else 2.6, 3.0 if inner else 4.1,
                       0.15 if inner else 0.85, (0.80, 0.16, 0.12) if inner else FUR)
            ob.location = B((s * 1.9, 10.9 + (0.35 if inner else 0), -0.15 + (0.08 if inner else 0)))
            ob.rotation_euler = (math.radians(-12), math.radians(-s * 4), 0)
            link(ob, root)


DROP_ARMS = 0.0
TPOSE = bool(os.environ.get("TPOSE") or os.environ.get("MEASURE"))
if TPOSE:  # ölçüm için referansla aynı poz: kollar yatay
    ARMS = [((s * (1.2 + 0.5 * k), 5.45 + DROP_ARMS, 0), (0.62,) * 3, 1.0) for s in (1, -1) for k in range(6)]
    HANDS = [((s * 3.75, 5.45 + DROP_ARMS, 0.1), (0.6,) * 3, 1.0) for s in (1, -1)]
else:
    ARMS = [((s * (1.3 + 0.32 * k), 5.5 - 0.22 * k, 0.03 * k), (0.62,) * 3, 1.0) for s in (1, -1) for k in range(5)]
    HANDS = [((s * (2.85 + 0.25 * k), 4.25 - 0.15 * k, 0.15), (0.6,) * 3, 1.0) for s in (1, -1) for k in range(2)]


def body(root):
    """Gövde + kollar + bacaklar: metaball (yumuşak birleşen tek form)."""
    for name, color, balls in (
        ("torso", FUR, [((0, 4.5, 0.1), (1.7, 1.75, 1.6), 1.15), ((0, 5.6, 0), (1.25, 0.8, 1.05), 1.0)] +
         ARMS +
         [((0, 3.15, -0.2), (1.8, 1.15, 1.85), 1.2)] +
         [((s * 0.8, 2.5 - 0.36 * k, 0.02 * k), (0.72 - 0.02 * k, 0.72 - 0.02 * k, 0.85 - 0.05 * k), 1.0) for s in (1, -1) for k in range(6)] +
         [((s * 0.88, 0.45, 0.3), (0.7, 0.42, 0.85), 1.0) for s in (1, -1)] +
         HANDS),
    ):
        mb = bpy.data.metaballs.new(name)
        mb.resolution = 0.12
        mb.render_resolution = 0.08
        for c, r, st in balls:
            e = mb.elements.new()
            e.type = "ELLIPSOID"
            e.co = B(c)
            e.size_x, e.size_y, e.size_z = r[0], r[2], r[1]
            e.radius = 1.25 * st
            e.stiffness = 2.0
        ob = bpy.data.objects.new(name, mb)
        mb.materials.append(mat(name, color))
        link(ob, root)


def tail(root):
    """Kıvrık kuyruk: arkadan çıkıp yukarı kalkan, ucu öne dönen spiral."""
    curve = bpy.data.curves.new("tail", "CURVE")
    curve.dimensions = "3D"
    sp = curve.splines.new("NURBS")
    pts = [(0, 3.0, -0.9), (0, 3.1, -2.3), (0, 3.9, -3.4), (0, 5.1, -3.6), (0, 5.8, -2.9), (0, 5.4, -2.2), (0, 4.8, -2.5)]
    if os.environ.get("STRAIGHT_TAIL"):  # yalnız ölçüm: kuyruğun skora etkisini görmek için
        pts = [(0, 2.6, -1.0), (0, 3.0, -2.3), (0, 3.5, -3.6), (0, 4.0, -4.8), (0, 4.4, -5.3)]
    sp.points.add(len(pts) - 1)
    for pt, p in zip(sp.points, pts):
        pt.co = (*B(p), 1)
    sp.order_u = 4
    sp.use_endpoint_u = True
    curve.bevel_depth = 0.42
    curve.bevel_resolution = 6
    curve.use_fill_caps = True
    # uca doğru incelme
    taper = bpy.data.curves.new("taper", "CURVE")
    tsp = taper.splines.new("POLY")
    tsp.points.add(2)
    for pt, (x, y) in zip(tsp.points, [(0, 1.0), (0.7, 0.85), (1, 0.55)]):
        pt.co = (x, y, 0, 1)
    tob = bpy.data.objects.new("taper", taper)
    bpy.context.scene.collection.objects.link(tob)
    tob.hide_render = True
    curve.taper_object = tob
    ob = bpy.data.objects.new("tail", curve)
    curve.materials.append(mat("tail", FUR))
    link(ob, root)


def ours(root):
    head(root).location.z -= DROP
    ears(root)
    body(root)
    tail(root)


def belly(root):
    """Göbek: gövdenin önünde açık renk yassı leke (ağız çevresiyle aynı krem)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16)
    ob = bpy.context.active_object
    ob.location = B((0, 4.0, 0.3))
    ob.scale = (1.2, 1.15, 1.5)
    bpy.ops.object.shade_smooth()
    ob.data.materials.append(mat("belly", CREAM))
    link(ob, root)


# ---------------- sahne ----------------
sc = bpy.context.scene
for ob in list(sc.objects):
    bpy.data.objects.remove(ob)
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1000, 620
sc.view_settings.view_transform = "Standard"
sc.world = sc.world or bpy.data.worlds.new("w")
sc.world.use_nodes = True
bg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.85, 0.9, 0.94, 1)
bg.inputs["Strength"].default_value = 0.55
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 1.6
sun.rotation_euler = (math.radians(40), 0, math.radians(-20))
sc.collection.objects.link(sun)
bpy.ops.mesh.primitive_plane_add(size=60)
bpy.context.active_object.data.materials.append(mat("floor", (0.78, 0.72, 0.62)))

roots = []
for name, x, build in (("ref", -6.5, reference), ("ours", 6.5, ours)):
    root = bpy.data.objects.new(name, None)
    root.location = (x, 0, 0)
    sc.collection.objects.link(root)
    build(root)
    roots.append(root)

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.lens = 50
sc.collection.objects.link(cam)
sc.camera = cam
cam.location = (0, -46, 13)
cam.rotation_euler = (Vector((0, 0, 7)) - cam.location).to_track_quat("-Z", "Y").to_euler()

if os.environ.get("MEASURE"):
    # Silüet ölçümü: iki model aynı yerde, ayrı ayrı düz beyaz çizilir; IoU + fark görseli (kırmızı: yalnız ref, yeşil: yalnız bizim).
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type, sh.single_color = "FLAT", "SINGLE", (1, 1, 1)
    sc.world.color = (0, 0, 0)
    sc.view_settings.view_transform = "Standard"
    for ob in sc.objects:
        if ob.type == "MESH" and ob.name.startswith("Plane"):
            ob.hide_render = True
    for r in roots:
        r.location.x = 0
    cam.location = (0, -60, 7.5)
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 19
    sc.render.resolution_x = sc.render.resolution_y = 400

    def kids(r):
        return [o for o in sc.objects if o.parent == r]

    scores = []
    for yaw in YAWS:
        masks = []
        for r in roots:
            for o in roots:
                for k in kids(o):
                    k.hide_render = o is not r
            r.rotation_euler = (0, 0, math.radians(yaw))
            path = f"{OUT}_mask_{r.name}_{int(yaw)}.png"
            sc.render.filepath = path
            bpy.ops.render.render(write_still=True)
            im = bpy.data.images.load(path)
            masks.append(np.array(im.pixels[:]).reshape(400, 400, 4)[..., 0] > 0.5)
        ref, ours_m = masks
        iou = (ref & ours_m).sum() / max((ref | ours_m).sum(), 1)
        scores.append(iou)
        diff = np.zeros((400, 400, 4), np.float32); diff[..., 3] = 1
        diff[ref & ours_m] = (0.6, 0.6, 0.6, 1)
        diff[ref & ~ours_m] = (1, 0.1, 0.1, 1)
        diff[~ref & ours_m] = (0.1, 0.9, 0.2, 1)
        img = bpy.data.images.new("diff", 400, 400)
        img.pixels.foreach_set(diff.ravel())
        img.filepath_raw = f"{OUT}_diff_{int(yaw)}.png"; img.file_format = "PNG"; img.save()
        print(f"IOU yaw={int(yaw)} {iou:.3f}")
    print(f"IOU mean {sum(scores) / len(scores):.3f}")
    sys.exit(0)

for yaw in YAWS:
    for r in roots:
        r.rotation_euler = (0, 0, math.radians(yaw))
    sc.render.filepath = f"{OUT}_{int(yaw)}.png"
    bpy.ops.render.render(write_still=True)
print("SPIKE done")
