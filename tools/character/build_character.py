# Slash Office karakteri: kendi modelimiz (düşük poligon, parametrik), iskelet, ağırlıklar, dokular ve katalog.
# Çalıştır: Blender -b --factory-startup --python tools/character/build_character.py -- <çıktı klasörü>
# Çıktı: <çıktı>/character.json + <çıktı>/tex/*.png. Klipler `clips.py` ile aynı dosyaya yazılır.
#
# Sözleşme (uygulama, CharacterArt): Y yukarı, karakter +z'ye bakar, X karakterin solu, metre; dinlenme T-pozu.
# Mesh: konum/normal/uv (float32), 4 kemik + 4 ağırlık (u8, toplam 255), üçgen indeksleri (uint32).
# Parça: {mesh, mode (flat|albedo|tinted|pattern|eye|mouth|decal|cutout), texture?, tint? (skin|hair|top|bottom|shoes),
#         color? [r,g,b]}.
import base64, json, math, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geometry as G  # noqa: E402
import textures as T  # noqa: E402
import numpy as np  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(os.path.join(OUT, "tex"), exist_ok=True)

# ---------------------------------------------------------------- iskelet (kendi adlarımız, dinlenme T-pozu)
JOINTS = [  # (ad, ebeveyn, konum)
    ("Root", None, (0, 0, 0)),
    ("Hips", "Root", (0, 0.34, 0)),
    ("Spine1", "Hips", (0, 0.38, 0)),
    ("Spine2", "Spine1", (0, 0.45, 0)),
    ("Spine3", "Spine2", (0, 0.52, -0.01)),
    ("Neck", "Spine3", (0, 0.60, -0.02)),
    ("Head", "Neck", (0, 0.63, -0.02)),
]
for s, x in (("L", 1), ("R", -1)):
    JOINTS += [
        ("Shoulder_" + s, "Spine3", (0.030 * x, 0.571, -0.021)),
        ("UpperArm_" + s, "Shoulder_" + s, (0.078 * x, 0.571, -0.021)),
        ("ForeArm_" + s, "UpperArm_" + s, (0.203 * x, 0.571, -0.021)),
        ("Hand_" + s, "ForeArm_" + s, (0.318 * x, 0.571, -0.021)),
        ("Thigh_" + s, "Hips", (0.064 * x, 0.35, 0.0)),
        ("Shin_" + s, "Thigh_" + s, (0.064 * x, 0.168, 0.0)),
        ("Foot_" + s, "Shin_" + s, (0.064 * x, 0.055, 0.0)),
    ]
BONES = [j[0] for j in JOINTS]
IDX = {n: i for i, n in enumerate(BONES)}
PARENTS = [IDX[p] if p else -1 for _, p, _ in JOINTS]
POS = {n: np.array(p, float) for n, _, p in JOINTS}
assert all(p < i for i, p in enumerate(PARENTS))


def smooth(a, b, t):
    t = np.clip((t - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def chain(t, joints, bones, width):
    """Bir zincir boyunca (t artan) ağırlıklar: eklemlerde `width` genişliğinde yumuşak geçiş."""
    w = {}
    k = max(0, min(len(joints) - 1, int(np.searchsorted(joints, t, side="right")) - 1))
    w[bones[k]] = 1.0
    for j in range(1, len(joints)):
        if abs(t - joints[j]) < width:
            s = float(smooth(joints[j] - width, joints[j] + width, t))
            w = {bones[j - 1]: 1 - s, bones[j]: s}
    return w


def weights(p, region):
    x, y, z = p
    side = "L" if x >= 0 else "R"
    ax = abs(x)
    if region == "head":
        return {"Head": 1.0}
    if region == "hips":
        return {"Hips": 1.0}
    if region == "foot":
        return {"Foot_" + side: 1.0}
    if ax > 0.075 and y > 0.47 and region != "leg":
        w = chain(ax, [0.030, 0.078, 0.203, 0.318], ["Shoulder_" + side, "UpperArm_" + side, "ForeArm_" + side, "Hand_" + side],
                  0.03)
        body = float(smooth(0.11, 0.07, ax))   # omuz derisi gövdeye karışır
        if body > 0:
            w = {k: v * (1 - body) for k, v in w.items()}
            w["Spine3"] = w.get("Spine3", 0) + body
        return w
    if y < 0.36 and (region == "leg" or ax > 0.02):
        w = chain(-y, [-0.35, -0.168, -0.055], ["Thigh_" + side, "Shin_" + side, "Foot_" + side], 0.035)
        hip = float(smooth(0.30, 0.37, y)) * (0.4 if region != "leg" else 0.25)
        if hip > 0:
            w = {k: v * (1 - hip) for k, v in w.items()}
            w["Hips"] = w.get("Hips", 0) + hip
        return w
    if y > 0.60:
        return {"Neck": 1.0}
    return chain(y, [0.0, 0.38, 0.45, 0.52], ["Hips", "Spine1", "Spine2", "Spine3"], 0.035)


# ---------------------------------------------------------------- dışa aktarım yardımcıları
MESHES = {}


def b64(fmt, values):
    return base64.b64encode(struct.pack("<%d%s" % (len(values), fmt), *values)).decode()


def add_mesh(name, mesh, region, normals=None):
    n = mesh.normals() if normals is None else normals
    joints, wts = [], []
    for p in mesh.p:
        w = sorted(weights(p, region).items(), key=lambda kv: -kv[1])[:4]
        total = sum(v for _, v in w) or 1
        q = [int(round(255 * v / total)) for _, v in w]
        q[0] += 255 - sum(q)
        w += [("Root", 0)] * (4 - len(w)); q += [0] * (4 - len(q))
        joints += [IDX[b] for b, _ in w]
        wts += q
    MESHES[name] = {"vertexCount": len(mesh.p), "positions": b64("f", mesh.p.ravel().tolist()),
                    "normals": b64("f", n.ravel().tolist()), "uvs": b64("f", mesh.uv.ravel().tolist()),
                    "joints": b64("B", joints), "weights": b64("B", wts), "indices": b64("I", mesh.f.ravel().tolist()),
                    "triangles": mesh.triangles}
    return name


def save_png(rgba, rel):
    import bpy
    path = os.path.join(OUT, "tex", rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, w = rgba.shape[:2]
    im = bpy.data.images.new("t", w, h, alpha=True)
    im.pixels[:] = np.flipud(rgba).astype(np.float32).ravel()   # Blender: satır 0 alt
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    return "tex/" + rel


def part(mesh, mode, **kw):
    return dict(mesh=mesh, mode=mode, **kw)


# ---------------------------------------------------------------- baş ve yüz
HEAD_C, HEAD_R = (0.0, 0.845, -0.03), (0.272, 0.236, 0.250)


def head_shape(p):
    """Önden yumuşakça basık (kırışıksız), çene biraz dar."""
    q = p.copy()
    cz = HEAD_C[2]
    front = np.clip((q[:, 2] - cz) / HEAD_R[2], 0, 1)
    q[:, 2] = cz + (q[:, 2] - cz) * (1 - 0.13 * front ** 2)
    low = np.clip((HEAD_C[1] - q[:, 1]) / HEAD_R[1], 0, 1)
    q[:, 0] *= 1 - 0.10 * low ** 2
    return q


head_full = G.ellipsoid(HEAD_C, HEAD_R, segments=28, rings=18, shape=head_shape)
ears = G.ellipsoid((0.268, 0.805, -0.045), (0.030, 0.048, 0.028), 10, 6) + \
    G.ellipsoid((-0.268, 0.805, -0.045), (0.030, 0.048, 0.028), 10, 6)
nose = G.ellipsoid((0.0, 0.808, 0.222), (0.021, 0.016, 0.014), 8, 5)

# Yüz bölgeleri kafa yüzeyinin kendisi (ayrı alt mesh'ler, aynı köşe ve normaller: dikiş yok).
# (phi: yatay açı, 0 = ön, +x'e doğru artar; el: yükseklik açısı). Öncelik sırası: göz, ağız, yanak.
FACE_REGIONS = {"eyes": ((-0.62, 0.62), (-0.20, 0.16)), "mouth": ((-0.34, 0.34), (-0.50, -0.22)),
                "cheeks": ((-0.95, 0.95), (-0.40, 0.02))}


def angles(p):
    q = (p - np.array(HEAD_C)) / np.array(HEAD_R)
    return np.arctan2(q[:, 0], q[:, 2]), np.arcsin(np.clip(q[:, 1] / np.linalg.norm(q, axis=1), -1, 1))


def split_head(mesh):
    normals = mesh.normals()
    tri_ph, tri_el = angles(mesh.p[mesh.f].mean(axis=1))
    owner = np.full(len(mesh.f), "head", dtype=object)
    for name in reversed(list(FACE_REGIONS)):   # öncelik: sonra yazılan kazanır
        (p0, p1), (e0, e1) = FACE_REGIONS[name]
        inside = (tri_ph > p0) & (tri_ph < p1) & (tri_el > e0) & (tri_el < e1)
        if name == "cheeks":
            inside &= np.abs(tri_ph) > 0.36
        owner[inside] = name
    vph, vel = angles(mesh.p)
    out = {}
    for name in ["head"] + list(FACE_REGIONS):
        faces = mesh.f[owner == name]
        used = np.unique(faces)
        remap = {v: i for i, v in enumerate(used)}
        uv = mesh.uv[used]
        if name in FACE_REGIONS:
            (p0, p1), (e0, e1) = FACE_REGIONS[name]
            uv = np.c_[(vph[used] - p0) / (p1 - p0), (vel[used] - e0) / (e1 - e0)]
        sub = G.Mesh(mesh.p[used], uv, np.vectorize(remap.get)(faces))
        out[name] = (sub, normals[used])
    return out


face = split_head(head_full)

# ---------------------------------------------------------------- gövde (T-pozu)
torso = G.lathe([(0.300, 0.050), (0.310, 0.092), (0.350, 0.106), (0.430, 0.112), (0.500, 0.106), (0.550, 0.092),
                 (0.590, 0.068), (0.625, 0.030)], segments=16, center=(0, 0, -0.01), zscale=0.86, cap_bottom=True)
arms = G.Mesh()
legs = G.Mesh()
hands = G.Mesh()
socks = G.Mesh()
for x in (1, -1):
    arms = arms + G.tube((0.062 * x, 0.571, -0.021), (0.203 * x, 0.571, -0.021), 0.034, 0.030, 10, 3, cap0=True, cap1=False)
    arms = arms + G.tube((0.203 * x, 0.571, -0.021), (0.312 * x, 0.571, -0.021), 0.030, 0.027, 10, 3, cap0=True, cap1=False)
    hands = hands + G.ellipsoid((0.338 * x, 0.571, -0.016), (0.042, 0.040, 0.038), 12, 8)
    legs = legs + G.tube((0.064 * x, 0.335, 0.0), (0.064 * x, 0.168, 0.0), 0.047, 0.040, 10, 3, cap0=False, cap1=False)
    legs = legs + G.tube((0.064 * x, 0.168, 0.0), (0.064 * x, 0.060, 0.0), 0.040, 0.034, 10, 3, cap0=True, cap1=False)
    socks = socks + G.ellipsoid((0.064 * x, 0.040, 0.012), (0.040, 0.034, 0.058), 10, 6)

BODY = [
    part(add_mesh("body/head", face["head"][0], "head", face["head"][1]), "flat", tint="skin"),
    part(add_mesh("body/ears", ears, "head"), "flat", tint="skin"),
    part(add_mesh("body/nose", nose, "head"), "flat", tint="skin"),
    part(add_mesh("body/eyes", face["eyes"][0], "head", face["eyes"][1]), "eye", tint="skin"),
    part(add_mesh("body/mouth", face["mouth"][0], "head", face["mouth"][1]), "mouth", tint="skin"),
    part(add_mesh("body/torso", torso, "torso"), "flat", tint="skin"),
    part(add_mesh("body/arms", arms, "torso"), "flat", tint="skin"),
    part(add_mesh("body/hands", hands, "torso"), "flat", tint="skin"),
    part(add_mesh("body/legs", legs, "leg"), "flat", tint="skin"),
    part(add_mesh("body/socks", socks, "foot"), "flat", color=[0.95, 0.95, 0.95]),
]
# Yanaklar: allık açıksa çıkartma, kapalıysa düz ten (çizici seçer).
BLUSH = [part(add_mesh("body/cheeks", face["cheeks"][0], "head", face["cheeks"][1]), "decal", tint="skin",
              texture=save_png(T.blush_texture(), "face/blush.png"))]

# ---------------------------------------------------------------- saç modelleri
HAIR_TEX = save_png(T.hair_texture(), "hair/strands.png")
HR = tuple(r * 1.075 for r in HEAD_R)


def hair_cap(limit, scale=1.075, segments=28, rings=12, bump=0.0, bumps=0, lip=True):
    """Başı saran saç: her açı (phi, 0 = ön) için tepeden `limit(phi)` kutup açısına kadar. Alt kenarda içe dönük
    dudak (kalınlık hissi)."""
    cx, cy, cz = HEAD_C
    rx, ry, rz = (r * scale for r in HEAD_R)
    pos, uv = [], []
    for i in range(rings + 1):
        for s in range(segments + 1):
            ph = 2 * math.pi * s / segments - math.pi   # -pi..pi, 0 = ön
            t = limit(ph) * i / rings
            k = 1 + bump * math.cos(bumps * ph) * math.sin(t) if bumps else 1
            pos.append((cx + rx * k * math.sin(t) * math.sin(ph), cy + ry * math.cos(t), cz + rz * k * math.sin(t) * math.cos(ph)))
            uv.append((2 * s / segments, 1 - i / rings))
    faces = []
    cols = segments + 1
    for i in range(rings):
        for s in range(segments):
            a = i * cols + s
            b, c, d = a + 1, a + cols, a + cols + 1
            faces += [(a, c, b), (b, c, d)]
    m = G.Mesh(pos, uv, faces)
    m.p = head_shape(m.p)
    if lip:
        # Kenardan başa doğru kısa iç yüz.
        edge = m.p[rings * cols:(rings + 1) * cols]
        inner = np.array(HEAD_C) + (edge - np.array(HEAD_C)) * 0.94
        lipm = G.Mesh(np.r_[edge, inner], np.r_[m.uv[rings * cols:], m.uv[rings * cols:]],
                      [(s, s + cols, s + 1) for s in range(segments)] + [(s + 1, s + cols, s + 1 + cols) for s in range(segments)])
        m = m + lipm
    return m


def bangs(ph, depth=1.17, sides=1.55, back=2.05, clumps=5, clump=0.10, part_shift=0.0):
    """Saç çizgisi: önde kâkül (tırtıklı), yanlarda kulak üstü, arkada ense."""
    a = abs(ph)
    if a < 1.0:
        base = depth + (sides - depth) * smooth(0.55, 1.0, a)
        scallop = clump * abs(math.sin(clumps * (ph + part_shift) * 1.6)) * (1 - smooth(0.6, 1.0, a))
        return float(base + scallop)
    return float(sides + (back - sides) * smooth(1.2, 2.6, a))


def tail(p0, p1, r0, r1):
    return G.tube(p0, p1, r0, r1, 10, 5, cap0=True, cap1=True, u_repeat=2, v_scale=4)


HAIRS = []
styles = {
    "short": hair_cap(lambda ph: bangs(ph)),
    "bob": hair_cap(lambda ph: bangs(ph, sides=2.05, back=2.25, clumps=4) if abs(ph) > 0.4 else bangs(ph), bump=0.02, bumps=9),
    "ponytail": hair_cap(lambda ph: bangs(ph, clumps=3)) + tail((0, 0.93, -0.30), (0, 0.66, -0.40), 0.075, 0.035),
    "pigtails": hair_cap(lambda ph: bangs(ph, clumps=4)) + tail((0.24, 0.84, -0.14), (0.32, 0.62, -0.12), 0.060, 0.030)
    + tail((-0.24, 0.84, -0.14), (-0.32, 0.62, -0.12), 0.060, 0.030),
    "spiky": hair_cap(lambda ph: bangs(ph, clumps=6, clump=0.14)) + sum(
        (G.tube((0.15 * math.sin(a), 1.02, -0.03 + 0.15 * math.cos(a)), (0.26 * math.sin(a), 1.13, -0.03 + 0.26 * math.cos(a)), 0.05, 0.004,
                8, 2, cap0=False, cap1=False) for a in np.linspace(-2.6, 2.6, 7)), G.Mesh()),
    "long": hair_cap(lambda ph: bangs(ph, sides=2.15, back=2.3, clumps=4), bump=0.015, bumps=11)
    + G.lathe([(0.48, 0.20), (0.56, 0.235), (0.66, 0.255), (0.74, 0.262)], segments=18, center=(0, 0, -0.06), zscale=0.80,
              u_repeat=2, v_scale=4).transformed(lambda q: np.where((q[:, 2] > -0.02)[:, None], q * [1, 1, 0] + [0, 0, -0.02], q)),
    "bun": hair_cap(lambda ph: bangs(ph, clumps=4)) + G.ellipsoid((0, 1.10, -0.06), (0.085, 0.075, 0.085), 12, 8),
    "buzz": hair_cap(lambda ph: 1.05 + 0.5 * smooth(0.8, 2.6, abs(ph)), scale=1.025, lip=False),
    "curly": hair_cap(lambda ph: bangs(ph, clumps=7, clump=0.08), bump=0.05, bumps=14),
    "sidepart": hair_cap(lambda ph: bangs(ph, clumps=3, clump=0.06) + (0.16 if -0.9 < ph < -0.1 else -0.05 if 0.1 < ph < 0.9 else 0)),
}
HAIR_NAMES = list(styles)
for name, mesh in styles.items():
    HAIRS.append([part(add_mesh("hair/" + name, mesh, "head"), "tinted", tint="hair", texture=HAIR_TEX)])

# ---------------------------------------------------------------- kıyafetler (gövde kabukları)
PATTERN_TEX = [save_png(T.pattern_texture(n), "pattern/%s.png" % n) for n in T.PATTERNS]


def shell_torso(y0, y1, grow=0.010, segments=16):
    prof = [(y, r + grow) for y, r in [(0.300, 0.092), (0.350, 0.106), (0.430, 0.112), (0.500, 0.106), (0.550, 0.092),
                                       (0.590, 0.068), (0.618, 0.040)] if y0 - 1e-6 <= y <= y1 + 1e-6]
    return G.lathe(prof, segments, center=(0, 0, -0.01), zscale=0.86, u_repeat=4, v_scale=8)


def sleeves(x1, grow=0.008):
    m = G.Mesh()
    for x in (1, -1):
        m = m + G.tube((0.055 * x, 0.571, -0.021), (x1 * x, 0.571, -0.021), 0.034 + grow + 0.006, 0.031 + grow, 10, 3,
                       cap0=True, cap1=False, u_repeat=2, v_scale=8)
    return m


def skirt(y_top, y_bottom, r_top, r_bottom):
    return G.lathe([(y_bottom, r_bottom), ((y_bottom + y_top) / 2, (r_bottom + r_top) / 2 + 0.01), (y_top, r_top)], 18,
                   center=(0, 0, -0.01), zscale=0.90, u_repeat=4, v_scale=8)


def pants(y_bottom, grow=0.008):
    m = G.lathe([(0.30, 0.10), (0.36, 0.112), (0.40, 0.118)], 16, center=(0, 0, -0.01), zscale=0.86, u_repeat=4, v_scale=8)
    for x in (1, -1):
        m = m + G.tube((0.064 * x, 0.345, 0.0), (0.064 * x, y_bottom, 0.0), 0.047 + grow + 0.004, 0.036 + grow, 10, 4,
                       cap0=False, cap1=False, u_repeat=2, v_scale=8)
    return m


TOPS = {
    "tee": shell_torso(0.33, 0.618) + sleeves(0.15),
    "longsleeve": shell_torso(0.33, 0.618) + sleeves(0.30),
    "tank": shell_torso(0.33, 0.600),
    "sweater": shell_torso(0.31, 0.618, grow=0.016) + sleeves(0.30, grow=0.014),
}
ONEPIECE = {
    "dress": (shell_torso(0.40, 0.618) + sleeves(0.13), skirt(0.42, 0.13, 0.118, 0.205)),
    "overalls": (shell_torso(0.33, 0.618) + sleeves(0.15), None),
}
OUTFITS = []
for name, mesh in TOPS.items():
    OUTFITS.append({"name": name, "parts": [part(add_mesh("top/" + name, mesh, "torso"), "pattern", tint="top")], "onepiece": False})
for name, (upper, lower) in ONEPIECE.items():
    parts = [part(add_mesh("top/" + name, upper, "torso"), "pattern", tint="top")]
    if lower is not None:
        parts.append(part(add_mesh("top/%s-skirt" % name, lower, "hips"), "pattern", tint="top"))
    if name == "overalls":
        parts.append(part(add_mesh("top/overalls-pants", pants(0.075, grow=0.012), "leg"), "flat", tint="bottom"))
    OUTFITS.append({"name": name, "parts": parts, "onepiece": True})

BOTTOMS = [
    {"name": "pants", "parts": [part(add_mesh("bottom/pants", pants(0.075), "leg"), "flat", tint="bottom")]},
    {"name": "shorts", "parts": [part(add_mesh("bottom/shorts", pants(0.235), "leg"), "flat", tint="bottom")]},
    {"name": "skirt", "parts": [part(add_mesh("bottom/skirt", skirt(0.40, 0.21, 0.118, 0.165), "hips"), "flat", tint="bottom")]},
]

SHOE_TEX = save_png(T.shoe_texture(), "shoes/sneaker.png")


def shoe(height, toe=0.072):
    m = G.Mesh()
    for x in (1, -1):
        m = m + G.ellipsoid((0.064 * x, 0.030 + height / 2, 0.018), (0.046, 0.030 + height / 2, toe), 12, 8,
                            shape=lambda q: np.c_[q[:, 0], np.maximum(q[:, 1], 0.004), q[:, 2]])
    return m


SHOES = [
    {"name": "sneakers", "parts": [part(add_mesh("shoes/sneakers", shoe(0.0), "foot"), "pattern", tint="shoes", texture=SHOE_TEX)]},
    {"name": "boots", "parts": [part(add_mesh("shoes/boots", shoe(0.05, 0.068), "foot"), "flat", tint="shoes")]},
    {"name": "slippers", "parts": [part(add_mesh("shoes/slippers", shoe(-0.012, 0.078), "foot"), "flat", tint="shoes")]},
]

# ---------------------------------------------------------------- yüz dokuları
EYES = [[save_png(T.eye_texture(s, e), "face/eye%d_%s.png" % (s, e)) for e in T.EYE_EXPRESSIONS] for s in range(T.EYE_STYLES)]
MOUTHS = [[save_png(T.mouth_texture(e), "face/mouth_%s.png" % e) for e in T.MOUTH_EXPRESSIONS]]

# ---------------------------------------------------------------- paket
rest = []
for n in BONES:
    m = np.eye(4)
    m[:3, 3] = POS[n]
    rest += [m[r, c] for c in range(4) for r in range(4)]   # sütun-öncelikli
pack = {"version": 1, "bones": BONES, "parents": PARENTS, "rest": b64("f", rest), "clips": {}, "meshes": MESHES,
        "body": BODY, "blush": BLUSH, "hairs": HAIRS, "hairNames": HAIR_NAMES, "eyes": EYES, "mouths": MOUTHS,
        "patterns": PATTERN_TEX, "patternNames": T.PATTERNS, "outfits": OUTFITS, "bottoms": BOTTOMS, "shoes": SHOES,
        "eyeExpressions": T.EYE_EXPRESSIONS, "mouthExpressions": T.MOUTH_EXPRESSIONS}
path = os.path.join(OUT, "character.json")
if os.path.exists(path):
    old = json.load(open(path))
    if old.get("bones") == BONES:
        pack["clips"] = old.get("clips", {})
json.dump(pack, open(path, "w"))
tris = {k: v["triangles"] for k, v in MESHES.items()}
body = sum(tris[p["mesh"]] for p in BODY)
print("CHARACTER bones=%d meshes=%d bodyTris=%d hairTris=%s topTris=%s size=%.2fMB" % (
    len(BONES), len(MESHES), body, [tris["hair/" + n] for n in HAIR_NAMES],
    [tris["top/" + n] for n in list(TOPS) + list(ONEPIECE)], os.path.getsize(path) / 1e6))
