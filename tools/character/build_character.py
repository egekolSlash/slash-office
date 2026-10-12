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
import hair as H  # noqa: E402
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
    if region == "arm":
        # Kol, kol ağzı ve el: yalnız kol zinciri; kökü (gövdenin içinde kalan kapak) omuza yumuşar.
        return chain(ax, [0.030, 0.078, 0.203, 0.318], ["Shoulder_" + side, "UpperArm_" + side, "ForeArm_" + side, "Hand_" + side],
                     0.03)
    if y < 0.36 and (region == "leg" or ax > 0.02):
        w = chain(-y, [-0.35, -0.168, -0.055], ["Thigh_" + side, "Shin_" + side, "Foot_" + side], 0.035)
        hip = float(smooth(0.30, 0.37, y)) * (0.4 if region != "leg" else 0.25)
        if hip > 0:
            w = {k: v * (1 - hip) for k, v in w.items()}
            w["Hips"] = w.get("Hips", 0) + hip
        return w
    if y > 0.60:
        return {"Neck": 1.0}
    # Gövde (ve gövde kabukları): yalnız omurga; kol kalkınca yanları kola çekilmez (koltuk altında perde olmasın).
    return chain(y, [0.0, 0.38, 0.45, 0.52], ["Hips", "Spine1", "Spine2", "Spine3"], 0.035)


# ---------------------------------------------------------------- dışa aktarım yardımcıları
MESHES = {}


def b64(fmt, values):
    return base64.b64encode(struct.pack("<%d%s" % (len(values), fmt), *values)).decode()


def add_mesh(name, mesh, region, normals=None):
    n = mesh.normals() if normals is None else normals
    joints, wts = [], []
    for p, own in zip(mesh.p, mesh.region):
        w = sorted(weights(p, own or region).items(), key=lambda kv: -kv[1])[:4]
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
# Süperelipsoit kafa (hair.Head): yatay kesit daire, alın-çene önden bakınca düz, tepe ve ense yuvarlak.
HEADM = H.Head((0.0, 0.848, -0.057), (0.236, 0.228, 0.234),
               {"up": (2.0, 2.5, 2.0), "down": (2.7, 4.0, 2.3)})
HEAD_C = tuple(HEADM.c)


def head_grid(segments=28, rings=18):
    pos, uv = [], []
    for i in range(rings + 1):
        polar = math.pi * i / rings
        for s in range(segments + 1):
            ph = 2 * math.pi * s / segments - math.pi
            pos.append(HEADM.point(ph, polar))
            uv.append((s / segments, 1 - i / rings))
    faces = []
    cols = segments + 1
    for i in range(rings):
        for s in range(segments):
            a, b = i * cols + s, i * cols + s + 1
            faces += [(a, a + cols, b), (b, a + cols, b + cols)]
    return G.Mesh(pos, uv, faces)


head_full = head_grid()
# Kulak: kafanın yanında, öne-arkaya basık yarım disk. Burun: yüz düzleminde küçük topuz.
ears = G.ellipsoid((0.236, 0.765, -0.058), (0.030, 0.052, 0.034), 10, 6) + \
    G.ellipsoid((-0.236, 0.765, -0.058), (0.030, 0.052, 0.034), 10, 6)
nose = G.ellipsoid((0.0, 0.790, 0.172), (0.024, 0.017, 0.016), 8, 5)

# Yüz bölgeleri kafa yüzeyinin kendisi (ayrı alt mesh'ler, aynı köşe ve normaller: dikiş yok). Yüz önden düz olduğu için
# dokular önden izdüşümle oturur: bölge = (x aralığı, y aralığı), uv bu dikdörtgende doğrusal. Öncelik: göz, ağız, yanak.
FACE_REGIONS = {"eyes": ((-0.18, 0.18), (0.745, 0.925)), "mouth": ((-0.09, 0.09), (0.62, 0.80)),
                "cheeks": ((-0.21, 0.21), (0.655, 0.76))}


def split_head(mesh):
    normals = mesh.normals()
    centers = mesh.p[mesh.f].mean(axis=1)
    front = mesh.p[mesh.f][:, :, 2].min(axis=1) > HEADM.c[2] + 0.05
    owner = np.full(len(mesh.f), "head", dtype=object)
    for name in reversed(list(FACE_REGIONS)):   # öncelik: sonra yazılan kazanır
        (x0, x1), (y0, y1) = FACE_REGIONS[name]
        inside = front & (centers[:, 0] > x0) & (centers[:, 0] < x1) & (centers[:, 1] > y0) & (centers[:, 1] < y1)
        owner[inside] = name
    out = {}
    for name in ["head"] + list(FACE_REGIONS):
        faces = mesh.f[owner == name]
        used = np.unique(faces)
        remap = {v: i for i, v in enumerate(used)}
        uv = mesh.uv[used]
        if name in FACE_REGIONS:
            (x0, x1), (y0, y1) = FACE_REGIONS[name]
            uv = np.c_[(mesh.p[used, 0] - x0) / (x1 - x0), (mesh.p[used, 1] - y0) / (y1 - y0)]
        sub = G.Mesh(mesh.p[used], uv, np.vectorize(remap.get)(faces))
        out[name] = (sub, normals[used])
    return out


face = split_head(head_full)

# ---------------------------------------------------------------- gövde (T-pozu)
TORSO = [(0.310, 0.092), (0.350, 0.108), (0.430, 0.110), (0.490, 0.098), (0.530, 0.088), (0.565, 0.080), (0.595, 0.062)]
torso = G.lathe([(0.300, 0.050)] + TORSO + [(0.625, 0.030)], segments=16, center=(0, 0, -0.01), zscale=0.86, cap_bottom=True)
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
    part(add_mesh("body/arms", arms, "arm"), "flat", tint="skin"),
    part(add_mesh("body/hands", hands, "arm"), "flat", tint="skin"),
    part(add_mesh("body/legs", legs, "leg"), "flat", tint="skin"),
    part(add_mesh("body/socks", socks, "foot"), "flat", color=[0.95, 0.95, 0.95]),
]
# Yanaklar: allık açıksa çıkartma, kapalıysa düz ten (çizici seçer).
BLUSH = [part(add_mesh("body/cheeks", face["cheeks"][0], "head", face["cheeks"][1]), "decal", tint="skin",
              texture=save_png(T.blush_texture(), "face/blush.png"))]

# ---------------------------------------------------------------- saç modelleri
HAIR_TEX = save_png(T.hair_texture(), "hair/strands.png")


HAIRS = []
HAIR_STYLES = H.styles(HEADM)
HAIR_NAMES = list(HAIR_STYLES)
for name, (base, crown, band_mesh) in HAIR_STYLES.items():
    parts = [part(add_mesh("hair/" + name, base, "head"), "tinted", tint="hair", texture=HAIR_TEX)]
    if crown is not None:   # şapka takılınca çizilmez
        parts.append(part(add_mesh("hair/%s-crown" % name, crown, "head"), "tinted", tint="hair", texture=HAIR_TEX, crown=True))
    if band_mesh is not None:
        parts.append(part(add_mesh("hair/%s-band" % name, band_mesh, "head"), "flat", color=[0.92, 0.36, 0.42]))
    HAIRS.append(parts)

# Şapkalar ve gözlük.
# Bere: alna kadar inen örgü kapak, kenarında katlama (kapağın alt kenarını izleyen kalın halka), tepede ponpon.
BEANIE_LIMIT = lambda ph: 1.20 + 0.25 * (abs(ph) / math.pi) ** 2
beanie = H.cap(HEADM, BEANIE_LIMIT, scale_top=1.10, scale_edge=1.09, segments=32)
fold = G.Mesh()
ring = [HEADM.point(2 * math.pi * k / 32 - math.pi, BEANIE_LIMIT(2 * math.pi * k / 32 - math.pi) - 0.06, 1.115) for k in range(33)]
for p0, p1 in zip(ring, ring[1:]):
    fold = fold + G.tube(p0, p1, 0.030, 0.030, 8, 1, cap0=False, cap1=False, u_repeat=1, v_scale=4)
pompom = G.ellipsoid(tuple(HEADM.point(0, 0, 1.10) + [0, 0.035, 0]), (0.055, 0.05, 0.055), 10, 7)
# Kasket: taç + taç kenarından öne uzanan, hafif aşağı eğik siperlik.
CAP_LIMIT = lambda ph: 1.05 + 0.20 * (abs(ph) / math.pi) ** 2
cap_crown = H.cap(HEADM, CAP_LIMIT, scale_top=1.09, scale_edge=1.08)
brim = HEADM.point(0, CAP_LIMIT(0), 1.08)
visor = G.ellipsoid(tuple(brim + [0, -0.008, 0.075]), (0.17, 0.012, 0.105), 14, 6).transformed(
    lambda q: np.c_[q[:, 0], q[:, 1] - 0.25 * np.maximum(q[:, 2] - brim[2], 0), q[:, 2]])
# Kulaklık: kulaktan kulağa saçın üstünden geçen bant + kulak kapları.
arc = [HEADM.point(math.pi / 2 * sgn, polar, 1.13) for sgn in (-1, 1) for polar in (np.linspace(1.75, 0.02, 7) if sgn < 0 else np.linspace(0.02, 1.75, 7))]
phones_band = G.Mesh()
for p0, p1 in zip(arc, arc[1:]):
    phones_band = phones_band + G.tube(p0, p1, 0.016, 0.016, 8, 1, cap0=False, cap1=False)
cups = G.ellipsoid((0.262, 0.78, -0.05), (0.035, 0.065, 0.06), 10, 7) + G.ellipsoid((-0.262, 0.78, -0.05), (0.035, 0.065, 0.06), 10, 7)
HATS = [
    {"name": "beanie", "parts": [part(add_mesh("hat/beanie", beanie, "head"),
                                      "pattern", tint="hat", texture=save_png(T.knit_texture(), "pattern/knit.png")),
                                 part(add_mesh("hat/beanie-fold", fold, "head"), "flat", tint="hat"),
                                 part(add_mesh("hat/beanie-pompom", pompom, "head"), "flat", color=[0.96, 0.96, 0.96])]},
    {"name": "cap", "parts": [part(add_mesh("hat/cap", cap_crown, "head"), "flat", tint="hat"),
                              part(add_mesh("hat/cap-visor", visor, "head"), "flat", tint="hat")]},
    {"name": "headphones", "parts": [part(add_mesh("hat/headphones-band", phones_band, "head"), "flat", color=[0.22, 0.22, 0.25]),
                                     part(add_mesh("hat/headphones-cups", cups, "head"), "flat", color=[0.30, 0.30, 0.34])]},
]
eye_pts = [HEADM.point(x * 0.49, HEADM.polar_at(x * 0.49, 0.81), 1.03) for x in (-1, 1)]
glasses = G.Mesh()
for p in eye_pts:
    nrm = p - np.array(HEAD_C); nrm /= np.linalg.norm(nrm)
    glasses = glasses + G.torus(tuple(p + nrm * 0.010), tuple(nrm), 0.048, 0.007, 18, 5)
glasses = glasses + G.tube(eye_pts[0] + [0.046, 0.008, 0.012], eye_pts[1] + [-0.046, 0.008, 0.012], 0.006, 0.006, 6, 2)
GLASSES = [part(add_mesh("accessory/glasses", glasses, "head"), "flat", color=[0.18, 0.15, 0.15])]

# ---------------------------------------------------------------- kıyafetler (gövde kabukları)
PATTERN_TEX = [save_png(T.pattern_texture(n), "pattern/%s.png" % n) for n in T.PATTERNS]


def shell_torso(y0, y1, grow=0.010, segments=16):
    prof = [(y, r + grow) for y, r in [(0.300, 0.092)] + TORSO[1:] + [(0.618, 0.040)] if y0 - 1e-6 <= y <= y1 + 1e-6]
    return G.lathe(prof, segments, center=(0, 0, -0.01), zscale=0.86, u_repeat=4, v_scale=8)


def sleeves(x1, grow=0.008, puff=0.0):
    """Kollar: omuzdan `x1`'e; `puff` kısa kolun ağzını genişletir (kutu tişört)."""
    m = G.Mesh()
    for x in (1, -1):
        m = m + G.tube((0.055 * x, 0.571, -0.021), (x1 * x, 0.571, -0.021), 0.034 + grow + 0.006 + puff * 0.5,
                       0.031 + grow + puff, 10, 3, cap0=True, cap1=False, u_repeat=2, v_scale=8)
    return m.tagged("arm")


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
    "tee": shell_torso(0.32, 0.618, grow=0.014) + sleeves(0.16, puff=0.014),
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


def shoe(height, length=0.080, collar=0.0):
    """Tıknaz ayakkabı: yuvarlak köşeli üst (bağcıklı doku) + kalın açık renk taban; `collar` bilekli (yüksek)
    ayakkabıda bileği saran kısım."""
    upper, sole = G.Mesh(), G.Mesh()
    for x in (1, -1):
        cx = 0.068 * x
        upper = upper + G.rounded_box((cx, 0.040 + height / 2, 0.018), (0.046, 0.034 + height / 2, length), 3.0, 12, 8,
                                      floor=0.018)
        sole = sole + G.rounded_box((cx, 0.012, 0.018), (0.049, 0.013, length + 0.004), 4.0, 12, 4)
        if collar:
            upper = upper + G.tube((cx, 0.06, -0.012), (cx, 0.06 + collar, -0.010), 0.044, 0.041, 10, 1, cap0=False,
                                   cap1=False, u_repeat=1, v_scale=2)
    return upper, sole


SHOES = []
for name, (h, length, collar, mode) in {"sneakers": (0.0, 0.080, 0.045, "pattern"), "boots": (0.05, 0.076, 0.06, "flat"),
                                        "slippers": (-0.018, 0.084, 0.0, "flat")}.items():
    upper, sole = shoe(h, length, collar)
    up = part(add_mesh("shoes/" + name, upper, "foot"), mode, tint="shoes", **({"texture": SHOE_TEX} if mode == "pattern" else {}))
    SHOES.append({"name": name, "parts": [up, part(add_mesh("shoes/%s-sole" % name, sole, "foot"), "flat",
                                                   color=[0.95, 0.94, 0.92] if name != "boots" else [0.30, 0.24, 0.20])]})

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
        "body": BODY, "blush": BLUSH, "hairs": HAIRS, "hairNames": HAIR_NAMES, "hats": HATS,
        "glasses": GLASSES, "eyes": EYES, "mouths": MOUTHS,
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
    len(BONES), len(MESHES), body, [tris["hair/" + n] + tris.get("hair/%s-crown" % n, 0) for n in HAIR_NAMES],
    [tris["top/" + n] for n in list(TOPS) + list(ONEPIECE)], os.path.getsize(path) / 1e6))
