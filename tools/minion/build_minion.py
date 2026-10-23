# Minyon (arka plan işi kedisi): kendi modelimiz, ilkel şekiller + metaball + kendi çizdiğimiz yüz dokusu.
# Çalıştır: Blender -b --factory-startup --python tools/minion/build_minion.py -- <çıktı klasörü>
# Çıktı: <çıktı>/minion.json + <çıktı>/tex/head.png.
#
# Sözleşme (uygulama, MinionArt): Y yukarı, +z ileri, metre; mesh biçimi character.json ile aynı (konum/normal/uv
# float32, 4 kemik + 4 ağırlık u8, uint32 indeks). Parçalar katıdır: her mesh tek kemiğe tam ağırlıkla bağlı;
# animasyon uygulamada kodla (MinionPose). Kemikler: body, head, leg_L, leg_R, tail; `pivots` uygulama uzayında.
# Modelleme "birim"de yapılır (boy ≈ 14 birim), dışa aktarırken HEIGHT metreye ölçeklenir.
import base64, json, math, os, struct, sys

import bpy
import numpy as np
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(os.path.join(OUT, "tex"), exist_ok=True)
HEIGHT = 0.50  # kulak ucu dahil, metre

FUR = tuple(c ** 2.2 for c in (0.639, 0.341, 0.914))  # malzeme doğrusal
SPOT = (0.478, 0.055, 0.941)                            # dokuya sRGB yazılır
EAR_IN = (0.80, 0.16, 0.12)
DROP = 0.75  # kısa bacak: kalça (y=2.6) altı sıkışır, üstü aşağı kayar


def squash(y):
    return y * (2.6 - DROP) / 2.6 if y < 2.6 else y - DROP


def B(p):  # model (x, y yukarı, z ileri) -> Blender (x, -z, y)
    return Vector((p[0], -p[2], squash(p[1])))


def bsdf_of(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def mat(name, color):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf_of(m).inputs["Base Color"].default_value = (*color, 1)
    return m


def link(ob):
    if ob.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(ob)


# ---------------------------------------------------------------- yüz dokusu
def face_texture(size=1024):
    """Önden düz izdüşüm uzayında (u: x, v: y, -1..1) yüz; alfa = boya."""
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
    ink = (0.16, 0.10, 0.20)
    for s in (1, -1):
        ex, ey = s * 0.40, 0.02
        paint(ell(ex, ey, 0.25, 0.15), ink)                              # göz çerçevesi (yanlarda kalın)
        sclera = ell(ex, ey - 0.01, 0.195, 0.115)
        paint(sclera, (0.93, 0.90, 0.62))                                # sarımsı göz akı
        tilt = ey + 0.025 + s * (u - ex) * 0.10
        lid = ell(ex, ey, 0.26, 0.17, 0.004) * np.clip((v - tilt) / 0.006, 0, 1)
        paint(lid, tuple(c ** (1 / 2.2) for c in FUR))                   # yarı kapalı kapak
        line = ell(ex, ey, 0.26, 0.17, 0.004) * np.clip(1 - np.abs(v - tilt) / 0.024, 0, 1)
        paint(line, ink)
        paint(ell(ex + s * 0.25, ey + 0.025, 0.045, 0.026), ink)         # dış köşe ucu
        bar = np.clip((0.0455 - np.abs(u - (ex - s * 0.03))) / 0.004, 0, 1)
        paint(bar * sclera * (v < tilt), ink)                            # kedi göz bebeği: düz kalın dikey şerit
    curve = -0.40 + 0.10 * (u / 0.33) ** 2 + 0.03 * u
    paint(np.clip(1 - np.abs(v - curve) / 0.016, 0, 1) * (np.abs(u) < 0.33), ink)  # sığ yan gülüş
    img = bpy.data.images.new("face", size, size, alpha=True)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


# ---------------------------------------------------------------- parçalar
HEAD_C = np.array([0.0, 8.95, -0.1])
HEAD_R = np.array([3.6, 2.88, 3.05])


def head():
    """Yumuşak kare kafa (süper-elipsoid), yüz önden izdüşümle boyanır ve tek dokuya bake edilir."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1)
    ob = bpy.context.active_object
    ob.name = "head"
    me = ob.data
    co = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    p = co.reshape(-1, 3)
    p = np.c_[p[:, 0], p[:, 2], -p[:, 1]]
    n = 2.35
    q = p / ((np.abs(p) ** n).sum(1) ** (1 / n))[:, None]
    y = q[:, 1]
    q[:, 0] *= 1 - 0.03 * np.clip(-y, 0, 1)
    q[:, 2] *= 1 - 0.06 * np.clip(-y, 0, 1)
    w = q * HEAD_R + HEAD_C
    w[:, 2] -= 0.15 * q[:, 1]
    w[:, 2] += np.exp(-((q[:, 0] / 0.38) ** 2 + ((q[:, 1] + 0.35) / 0.28) ** 2)) * np.clip(q[:, 2], 0, 1) * 0.2
    w[:, 1] -= DROP
    me.vertices.foreach_set("co", np.c_[w[:, 0], -w[:, 2], w[:, 1]].ravel())
    me.update()
    for poly in me.polygons:
        poly.use_smooth = True
    bake_face(ob)
    return ob


def bake_face(ob):
    """Kafaya kendi UV'si (akıllı açılım) + albedo dokusu: kürk, önde yüz (yanlara doğru söner). Cycles EMIT bake."""
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="uv")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    m = bpy.data.materials.new("head_bake")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    # yüz izdüşümü: nesne uzayında x → u, z (yukarı) → v
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], sep.inputs[0])

    def affine(socket, scale, offset):
        a = nt.nodes.new("ShaderNodeMath"); a.operation = "MULTIPLY_ADD"
        nt.links.new(socket, a.inputs[0]); a.inputs[1].default_value = scale; a.inputs[2].default_value = offset
        return a.outputs[0]
    uu = affine(sep.outputs["X"], 0.5 / HEAD_R[0], 0.5)
    vv = affine(sep.outputs["Z"], 0.5 / HEAD_R[1], 0.5 - 0.5 * (HEAD_C[1] - DROP) / HEAD_R[1])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(uu, comb.inputs[0]); nt.links.new(vv, comb.inputs[1])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = face_texture()
    tex.extension = "CLIP"
    nt.links.new(comb.outputs[0], tex.inputs["Vector"])
    nsep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Normal"], nsep.inputs[0])
    front = nt.nodes.new("ShaderNodeMath"); front.operation = "MULTIPLY"; front.use_clamp = True
    front.inputs[1].default_value = -3.0  # Blender -y = ön
    nt.links.new(nsep.outputs["Y"], front.inputs[0])
    fac = nt.nodes.new("ShaderNodeMath"); fac.operation = "MULTIPLY"
    nt.links.new(tex.outputs["Alpha"], fac.inputs[0]); nt.links.new(front.outputs[0], fac.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*FUR, 1)
    nt.links.new(fac.outputs[0], mix.inputs[0])
    nt.links.new(tex.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], emit.inputs["Color"])
    target = bpy.data.images.new("head_albedo", 1024, 1024, alpha=False)
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = target
    nt.nodes.active = node
    me.materials.clear()
    me.materials.append(m)

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 4
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT")
    target.filepath_raw = os.path.join(OUT, "tex", "head.png")
    target.file_format = "PNG"
    target.save()


def ears():
    """Sivri üçgen kulaklar: önü düz üçgen prizma, kenarlar yuvarlatılmış; içi kırmızı-turuncu (ayrı parça)."""
    obs = []
    for s in (1, -1):
        for inner in (False, True):
            w, h, d = (1.7, 3.0, 0.15) if inner else (2.6, 4.1, 0.85)
            hw = w / 2
            verts = [(-hw, 0, 0), (hw, 0, 0), (0, 0, h), (-hw, d, 0), (hw, d, 0), (0, d * 0.4, h)]
            faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
            me = bpy.data.meshes.new("ear")
            me.from_pydata(verts, [], faces)
            ob = bpy.data.objects.new(("ear_in" if inner else "ear") + ("_L" if s > 0 else "_R"), me)
            link(ob)
            bev = ob.modifiers.new("b", "BEVEL"); bev.width = min(d, w) * 0.22; bev.segments = 4
            sub = ob.modifiers.new("s", "SUBSURF"); sub.levels = sub.render_levels = 1
            for poly in me.polygons:
                poly.use_smooth = True
            ob.location = B((s * 1.9, 10.9 + (0.35 if inner else 0), -0.15 + (0.08 if inner else 0)))
            ob.rotation_euler = (math.radians(-12), math.radians(-s * 4), 0)
            obs.append(ob)
    return obs


def metaball(name, balls):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = mb.render_resolution = 0.22
    for c, r, st in balls:
        e = mb.elements.new()
        e.type = "ELLIPSOID"
        e.co = B(c)
        e.size_x, e.size_y, e.size_z = r[0], r[2], r[1]
        e.radius = 1.25 * st
        e.stiffness = 2.0
    ob = bpy.data.objects.new(name, mb)
    link(ob)
    return ob


def body():
    """Gövde + kollar + eller (tek metaball); bacaklar ayrı (yürürken sallanır)."""
    arms = [((s * (1.3 + 0.32 * k), 5.5 - 0.22 * k, 0.03 * k), (0.62,) * 3, 1.0) for s in (1, -1) for k in range(5)]
    hands = [((s * (2.85 + 0.25 * k), 4.25 - 0.15 * k, 0.15), (0.6,) * 3, 1.0) for s in (1, -1) for k in range(2)]
    torso = metaball("body", [((0, 4.5, 0.1), (1.7, 1.75, 1.6), 1.15), ((0, 5.6, 0), (1.25, 0.8, 1.05), 1.0),
                              ((0, 3.15, -0.2), (1.8, 1.15, 1.85), 1.2)] + arms + hands)
    legs = []
    for s, side in ((1, "L"), (-1, "R")):
        balls = [((s * 0.8, 2.5 - 0.36 * k, 0.02 * k), (0.72 - 0.02 * k, 0.72 - 0.02 * k, 0.85 - 0.05 * k), 1.0) for k in range(6)]
        balls.append(((s * 0.88, 0.45, 0.3), (0.7, 0.42, 0.85), 1.0))
        legs.append(metaball("leg_" + side, balls))
    return torso, legs


def tail():
    """Ucu kıvrık kuyruk: arkadan çıkıp kalkar, ucu öne döner; uca doğru incelir."""
    curve = bpy.data.curves.new("tail", "CURVE")
    curve.dimensions = "3D"
    sp = curve.splines.new("NURBS")
    pts = [(0, 3.0, -0.9), (0, 3.1, -2.3), (0, 3.9, -3.4), (0, 5.1, -3.6), (0, 5.8, -2.9), (0, 5.4, -2.2), (0, 4.8, -2.5)]
    sp.points.add(len(pts) - 1)
    for pt, p in zip(sp.points, pts):
        pt.co = (*B(p), 1)
    sp.order_u = 4
    sp.use_endpoint_u = True
    curve.bevel_depth = 0.42
    curve.bevel_resolution = 3
    curve.resolution_u = 8
    curve.use_fill_caps = True
    taper = bpy.data.curves.new("taper", "CURVE")
    tsp = taper.splines.new("POLY")
    tsp.points.add(2)
    for pt, (x, y) in zip(tsp.points, [(0, 1.0), (0.7, 0.85), (1, 0.55)]):
        pt.co = (x, y, 0, 1)
    tob = bpy.data.objects.new("taper", taper)
    link(tob)
    curve.taper_object = tob
    ob = bpy.data.objects.new("tail", curve)
    link(ob)
    return ob


# ---------------------------------------------------------------- dışa aktarım
def b64(fmt, values):
    return base64.b64encode(struct.pack("<%d%s" % (len(values), fmt), *values)).decode()


BONES = ["body", "head", "leg_L", "leg_R", "tail"]
PARENTS = [-1, 0, 0, 0, 0]
PIVOTS_MODEL = {"body": (0, 2.6, 0), "head": (0, 6.0, -0.1), "leg_L": (0.8, 2.5, 0), "leg_R": (-0.8, 2.5, 0),
                "tail": (0, 3.0, -0.9)}


def to_app(blender_co, scale):
    """Blender (x, y, z yukarı) → uygulama (x, y yukarı, z ileri), metre."""
    x, y, z = blender_co
    return (x * scale, z * scale, -y * scale)


def export_mesh(ob, bone, scale):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    mw = ob.matrix_world
    uv = me.uv_layers.active
    nm = mw.to_3x3().inverted().transposed()
    pos, nrm, uvs, idx = [], [], [], []
    # köşe başına (loop) ayrık: UV dikişleri ve düzgün normaller korunur
    for tri in me.loop_triangles:
        for li in tri.loops:
            vi = me.loops[li].vertex_index
            p = mw @ me.vertices[vi].co
            n = (nm @ (me.loops[li].normal if tri.use_smooth else tri.normal)).normalized()
            pos += to_app(p, scale)
            nrm += (n.x, n.z, -n.y)
            uvs += (uv.data[li].uv[0], 1 - uv.data[li].uv[1]) if uv else (0, 0)
            idx.append(len(idx))
    ev.to_mesh_clear()
    n = len(idx)
    return {"vertexCount": n, "positions": b64("f", pos), "normals": b64("f", nrm), "uvs": b64("f", uvs),
            "joints": b64("B", [BONES.index(bone), 0, 0, 0] * n), "weights": b64("B", [255, 0, 0, 0] * n),
            "indices": b64("I", idx), "triangles": n // 3}


for ob in list(bpy.context.scene.objects):
    bpy.data.objects.remove(ob)
h = head()
ear_objs = ears()
torso, legs = body()
tl = tail()
bpy.context.view_layer.update()

top = max((ob.matrix_world @ Vector(c)).z for ob in ear_objs for c in ob.bound_box)
scale = HEIGHT / top
srgb = tuple(round(c ** (1 / 2.2), 4) for c in FUR)
parts, meshes = [], {}
plan = [(h, "head", "albedo", None), (torso, "body", "flat", srgb), (legs[0], "leg_L", "flat", srgb),
        (legs[1], "leg_R", "flat", srgb), (tl, "tail", "flat", srgb)]
plan += [(ob, "head", "flat", srgb if not ob.name.startswith("ear_in") else EAR_IN) for ob in ear_objs]
for ob, bone, mode, color in plan:
    meshes[ob.name] = export_mesh(ob, bone, scale)
    part = {"mesh": ob.name, "mode": mode}
    if mode == "albedo":
        part["texture"] = "tex/head.png"
    if color:
        part["color"] = list(color)
    parts.append(part)

pivots = {b: list(to_app(B(p), scale)) for b, p in PIVOTS_MODEL.items()}
with open(os.path.join(OUT, "minion.json"), "w") as f:
    json.dump({"version": 1, "height": HEIGHT, "bones": BONES, "parents": PARENTS, "pivots": [pivots[b] for b in BONES],
               "meshes": meshes, "parts": parts}, f, separators=(",", ":"))
print("MINION", {k: v["triangles"] for k, v in meshes.items()}, "scale", round(scale, 5))
