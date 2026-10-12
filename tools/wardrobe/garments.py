# Gardırop paketinin kalıpları: kıyafet meshleri (karakterin gövdesine oturan halkalar, kollar, bacaklar) ve doku
# düzenleri. Uygulama uzayı: Y yukarı, +Z ileri, X karakterin solu; metre. Gövde ölçüleri tools/character ile aynı.
#
# Doku düzeni (tasarım dokusu 256 x 256, v aşağıdan yukarı):
#   üst / tek parça: gövde (ve etek) u ∈ [0, 1] etrafında, ön orta u = 0,5, dikiş arkada; v ∈ [0, 0,75] (etek ucundan
#   boyna). Tulum ve salopette bacaklar v ∈ [0, 0,30] (sol bacak u ∈ [0, 0,5], sağ [0,5, 1]), gövde v ∈ [0,30, 0,75].
#   Kollar v ∈ [0,75, 0,97]: sol kol u ∈ [0, 0,5], sağ kol [0,5, 1]; v omuzdan bileğe. v ∈ [0,97, 1]: renk örnekleri
#   (yaka, kapüşon gibi düz parçalar buraya bakar).
#   alt: bel bandı v ∈ [0,80, 1]; bacaklar v ∈ [0, 0,80] (sol/sağ yarı). Etek: v ∈ [0, 1] tek parça.
#   ayakkabı: üst u ∈ [0, 1] (ön u = 0,5), v ∈ [0, 0,75]; konç v ∈ [0,75, 0,97].
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "character"))
import geometry as G  # noqa: E402

ZS, CZ = 0.86, -0.01               # gövde kesiti: derinlik / genişlik, merkez z
BODY = [(0.300, 0.092), (0.310, 0.092), (0.350, 0.108), (0.430, 0.110), (0.490, 0.098), (0.530, 0.088), (0.565, 0.080),
        (0.595, 0.062), (0.618, 0.040)]
SHOULDER = (0.571, -0.021)          # kol ekseni (y, z)
LEG_X = 0.064
SWATCH_V = 0.985                    # renk örnekleri satırı
SWATCH_U = {"primary": 0.03, "secondary": 0.09, "detail": 0.15, "detail2": 0.21}


def body_r(y):
    ys = [p[0] for p in BODY]
    return float(np.interp(y, ys, [p[1] for p in BODY]))


class Layout:
    """Dokudaki bölgeler: (tür, u0, u1, v0, v1, y0, y1, çevre fonksiyonu). Gövde bölgesinde y dünya yüksekliği; kolda
    omuzdan uzaklık; bacakta dünya yüksekliği."""

    def __init__(self):
        self.regions = []
        self.chest = 0.48            # ön motiflerin merkezi
        self.waist = 0.40
        self.hem = 0.32
        self.sleeve = 0.0            # kol boyu (0: kolsuz)

    def add(self, kind, u0, u1, v0, v1, y0, y1, circ):
        self.regions.append((kind, u0, u1, v0, v1, y0, y1, circ))


def orient(mesh, axis_point, axis_dir):
    """Yüzleri eksenden dışa bakacak şekilde çevirir (çoğunluğa göre)."""
    a, b, c = mesh.p[mesh.f[:, 0]], mesh.p[mesh.f[:, 1]], mesh.p[mesh.f[:, 2]]
    n = np.cross(b - a, c - a)
    centers = (a + b + c) / 3
    d = np.asarray(axis_dir, float); d /= np.linalg.norm(d)
    rel = centers - np.asarray(axis_point, float)
    with np.errstate(all="ignore"):   # numpy 2 + Accelerate: sahte matmul uyarıları
        radial = rel - np.outer(rel @ d, d)
    if (np.einsum("ij,ij->i", n, radial) < 0).mean() > 0.5:
        mesh.f = mesh.f[:, [0, 2, 1]]
    return mesh


def ring_loft(rings, segments=18, u=(0.0, 1.0), v=(0.0, 0.75), region=None, close_bottom=False):
    """Y ekseni boyunca halkalar [(y, r)] ya da [(y, r, zs, cz)], aşağıdan yukarı. Açı ön ortada u ortası. `region`
    bölge adı ya da y → bölge (ör. etek kalçaya, gövde omurgaya)."""
    pos, uv = [], []
    ys = [r[0] for r in rings]
    y0, y1 = ys[0], ys[-1]
    for ring in rings:
        y, r = ring[0], ring[1]
        zs = ring[2] if len(ring) > 2 else ZS
        cz = ring[3] if len(ring) > 3 else CZ
        for s in range(segments + 1):
            t = s / segments
            a = 2 * math.pi * (t - 0.5)
            pos.append((r * math.sin(a), y, cz + r * zs * math.cos(a)))
            uv.append((u[0] + (u[1] - u[0]) * t, v[0] + (v[1] - v[0]) * (y - y0) / (y1 - y0 or 1)))
    cols = segments + 1
    faces = []
    for i in range(len(rings) - 1):
        for s in range(segments):
            a = i * cols + s
            faces += [(a, a + 1, a + cols), (a + 1, a + cols + 1, a + cols)]
    m = G.Mesh(pos, uv, faces)
    m = orient(m, (0, 0, CZ), (0, 1, 0))
    if callable(region):
        m.region = [region(p[1]) for p in m.p]
        return m
    return m.tagged(region) if region else m


def limb(p0, p1, radii, segments=10, u=(0.0, 0.5), v=(0.75, 0.97), region=None, droop=0.0, flat=1.0):
    """p0'dan p1'e tüp; `radii` uç uca yarıçaplar (eşit aralıklı halkalar). `droop`: uca doğru aşağı sarkma (geniş
    kollar). UV: u etrafında, v boyunca."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    axis = p1 - p0
    length = np.linalg.norm(axis)
    w = axis / length
    ref = np.array([0, 0, 1.0]) if abs(w[2]) < 0.9 else np.array([1.0, 0, 0])
    e1 = np.cross(w, ref); e1 /= np.linalg.norm(e1)
    e2 = np.cross(w, e1)
    n = len(radii)
    pos, uv = [], []
    for i, r in enumerate(radii):
        t = i / (n - 1)
        c = p0 + axis * t + np.array([0, -droop * t * t, 0])
        for s in range(segments + 1):
            k = s / segments
            a = 2 * math.pi * k
            pos.append(c + (e1 * math.cos(a) + e2 * math.sin(a) * flat) * r)
            uv.append((u[0] + (u[1] - u[0]) * k, v[0] + (v[1] - v[0]) * t))
    cols = segments + 1
    faces = []
    for i in range(n - 1):
        for s in range(segments):
            a = i * cols + s
            faces += [(a, a + 1, a + cols), (a + 1, a + cols + 1, a + cols)]
    m = G.Mesh(pos, uv, faces)
    m = orient(m, p0, axis)
    return m.tagged(region) if region else m


def swatch_uv(mesh, which):
    """Düz parça (yaka, kapüşon, taban): bütün köşeler doku köşesindeki renk örneğine bakar."""
    mesh.uv[:] = (SWATCH_U[which], SWATCH_V)
    return mesh


# ---------------------------------------------------------------- üst ve tek parça
SLEEVES = {"H": dict(x1=0.165, r=(0.054, 0.050, 0.047)), "L": dict(x1=0.300, r=(0.050, 0.046, 0.042, 0.039)),
           "N": None}


def sleeves(kind, layout, puff=0.0, wide=0.0, droop=0.0):
    spec = SLEEVES[kind]
    if spec is None:
        return G.Mesh()
    y, z = SHOULDER
    radii = list(spec["r"])
    if puff:
        radii = [radii[0], radii[0] + puff, radii[-1] + puff * 0.4]
    if wide:
        radii = [radii[0]] + [radii[0] + wide * (i / (len(radii) - 1)) ** 0.8 for i in range(1, len(radii))]
    m = G.Mesh()
    for side, u in ((1, (0.0, 0.5)), (-1, (0.5, 1.0))):
        m = m + limb((0.050 * side, y, z), (spec["x1"] * side, y, z), radii, 12, u=u, v=(0.75, 0.97), region="arm",
                     droop=droop, flat=0.85 if wide else 1.0)
    layout.sleeve = spec["x1"] - 0.05
    for side, u in (("sleeveL", (0.0, 0.5)), ("sleeveR", (0.5, 1.0))):
        layout.add(side, u[0], u[1], 0.75, 0.97, 0.0, layout.sleeve, lambda _y: 2 * math.pi * radii[0])
    return m


def legs(y_top, y_hem, r_top, r_hem, layout, v=(0.0, 0.30), flare=0.0):
    """Tulum / salopet / alt bacakları: kalçadan `y_hem`'e iki tüp (bölge: bacak)."""
    m = G.Mesh()
    for side, u, name in ((1, (0.0, 0.5), "legL"), (-1, (0.5, 1.0), "legR")):
        rings = 5
        radii = [r_top + (r_hem - r_top) * i / (rings - 1) + flare * (i / (rings - 1)) ** 2 for i in range(rings)]
        x = LEG_X * side
        tube = limb((x, y_top, 0.0), (x, y_hem, 0.0), radii, 12, u=u, v=(v[1], v[0]), region="leg")
        m = m + tube
        layout.add(name, u[0], u[1], v[0], v[1], y_hem, y_top, lambda _y, r=r_top: 2 * math.pi * r)
    return m


def torso_rings(hem, grow, flare_to=None, box=0.0):
    """Gövde halkaları: etek ucundan boyna; `flare_to` (y, r) etek ucu (bele kadar açılır), `box`: göğüs-bel düz."""
    rings = []
    if flare_to:
        y_hem, r_hem, shape = flare_to
        steps = 6
        for i in range(steps):
            t = i / (steps - 1)
            y = y_hem + (0.40 - y_hem) * t
            r_waist = body_r(0.40) + grow
            r = r_hem + (r_waist - r_hem) * (t ** shape)
            rings.append((y, r, ZS + (0.97 - ZS) * (1 - t)))
        start = 0.43
    else:
        start = hem
    for y, r in BODY:
        if y < start - 1e-6 or y > 0.618:
            continue
        rr = r + grow + 0.012 * float(np.clip((0.44 - y) / 0.10, 0, 1))   # etek ucu altın belini örtsün
        if box and y < 0.53:
            rr = max(rr, body_r(0.43) + grow + box)
        rings.append((y, rr))
    if not flare_to and rings[0][0] > hem + 1e-6:
        rings.insert(0, (hem, body_r(hem) + grow + 0.012))
    return rings


def top_garment(kind, sleeve, layout, legs_to=None, legs_r=None):
    """Kalıp → (mesh, düzen ayarı). `kind`: kalıp adı; `sleeve`: H / L / N."""
    m = G.Mesh()
    extra = {}
    grow = 0.016
    flare = None
    box = 0.0
    puff = wide = droop = 0.0
    body_v = (0.0, 0.75)
    hem = 0.32
    if kind in ("aline",):
        flare = (0.15, 0.20, 1.0)
    elif kind == "along":
        flare = (0.05, 0.22, 1.1)
    elif kind == "balloon":
        flare = None
    elif kind == "column":
        flare = (0.05, 0.155, 1.0)
    elif kind == "box":
        flare = (0.16, 0.150, 1.0); box = 0.012
    elif kind == "gown":
        flare = (0.03, 0.27, 0.55)
    elif kind == "kimono":
        flare = (0.05, 0.145, 1.0); wide = 0.045; droop = 0.03
    elif kind == "robe":
        flare = (0.04, 0.19, 0.9); wide = 0.040; droop = 0.02
    elif kind == "knitdress":
        flare = (0.20, 0.145, 1.0); grow = 0.020
    elif kind in ("wetsuit", "rashguard", "swimsuit", "jumpsuit", "dungaree"):
        hem = 0.30; grow = 0.012 if kind in ("wetsuit", "rashguard", "swimsuit") else 0.018
        body_v = (0.30, 0.75)
    elif kind == "tunic":
        flare = (0.25, 0.150, 1.0)
    elif kind in ("sweater", "vest"):
        grow = 0.022; hem = 0.31
    elif kind == "puff":
        puff = 0.018; hem = 0.33
    elif kind in ("tee", "shirt"):
        grow = 0.018 if kind == "shirt" else 0.016
    if kind == "balloon":
        rings = [(0.16, 0.170, 0.95), (0.19, 0.205, 0.95), (0.25, 0.215, 0.93), (0.31, 0.190, 0.90), (0.36, 0.150, 0.88),
                 (0.40, body_r(0.40) + grow)]
        rings += [(y, r + grow) for y, r in BODY if 0.43 - 1e-6 <= y <= 0.618]
    else:
        rings = torso_rings(hem, grow, flare, box)
    # Etek kalçaya bağlı (bacaklar içinden geçer), gövde omurgaya; tek parça (belde dikiş yok).
    y_lo, y_hi = rings[0][0], rings[-1][0]
    skirted = bool(flare) or kind == "balloon"
    m = m + ring_loft(rings, 20, v=body_v, region=(lambda y: "hips" if y < 0.37 else None) if skirted else None)
    ys = [r[0] for r in rings]
    rs = [r[1] for r in rings]
    zs = [r[2] if len(r) > 2 else ZS for r in rings]
    circ = lambda y: float(np.interp(y, ys, [math.pi * (r + r * z) for r, z in zip(rs, zs)]))
    layout.add("body", 0.0, 1.0, body_v[0], body_v[1], y_lo, y_hi, circ)
    layout.hem = y_lo
    if kind in ("wetsuit", "rashguard", "swimsuit", "jumpsuit", "dungaree"):
        to = legs_to if legs_to is not None else 0.07
        r0 = body_r(0.33) * 0.55 + grow
        m = m + legs(0.33, to, legs_r[0] if legs_r else 0.056, legs_r[1] if legs_r else 0.046, layout)
        extra["legs"] = to
    m = m + sleeves(sleeve, layout, puff=puff, wide=wide, droop=droop)
    parts = {"main": m}
    if kind == "shirt":
        collar = ring_loft([(0.598, 0.072, 0.92, -0.012), (0.612, 0.078, 0.92, -0.014), (0.626, 0.060, 0.92, -0.018)], 16)
        parts["collar"] = swatch_uv(collar, "detail")
    if kind == "hoodie":
        pass
    return parts, extra


def hood():
    """Kapüşon (sırtta, boynun arkasında yatık)."""
    h = G.ellipsoid((0.0, 0.585, -0.125), (0.105, 0.060, 0.070), 14, 8)
    h.p[:, 1] = np.maximum(h.p[:, 1], 0.55)
    return swatch_uv(h, "secondary")


def onepiece_kind(kind):
    return kind not in ("tunic", "sweater", "vest", "puff", "tee", "shirt")


# ---------------------------------------------------------------- alt
def bottom_garment(kind, layout):
    m = G.Mesh()
    if kind in ("askirt", "boxskirt", "longskirt"):
        hem, r = {"askirt": (0.20, 0.175), "boxskirt": (0.24, 0.138), "longskirt": (0.05, 0.175)}[kind]
        rings = []
        for i in range(6):
            t = i / 5
            y = hem + (0.395 - hem) * t
            rr = r + (0.118 - r) * (t ** (1.0 if kind != "boxskirt" else 3.0))
            rings.append((y, rr, ZS + (0.97 - ZS) * (1 - t)))
        m = m + ring_loft(rings, 20, v=(0.0, 1.0), region="hips")
        circ = lambda y: float(np.interp(y, [q[0] for q in rings], [math.pi * q[1] * (1 + q[2]) for q in rings]))
        layout.add("body", 0.0, 1.0, 0.0, 1.0, hem, 0.395, circ)
        return {"main": m}
    hem, r_hem, flare = {"knee": (0.17, 0.050, 0.0), "hot": (0.27, 0.056, 0.0), "pants": (0.075, 0.044, 0.0),
                         "wide": (0.05, 0.050, 0.030)}[kind]
    waist = [(0.30, 0.102), (0.36, 0.118), (0.395, 0.118)]
    m = m + ring_loft(waist, 18, v=(0.80, 1.0))
    layout.add("body", 0.0, 1.0, 0.80, 1.0, 0.30, 0.41, lambda _y: 2 * math.pi * 0.115)
    m = m + legs(0.345, hem, 0.060, r_hem, layout, v=(0.0, 0.80), flare=flare)
    return {"main": m}


# ---------------------------------------------------------------- ayakkabı
def shoe_body(cx, length, height, n=3.0, segments=14, rings=8, front_lift=0.0):
    """Ayakkabının yuvarlak köşeli üstü: süperelipsoit, ön u = 0,5; v aşağıdan yukarı [0, 0,75]."""
    pos, uv = [], []
    half = np.array([0.046, 0.034 + height / 2, length])
    center = np.array([cx, 0.040 + height / 2, 0.018])
    for i in range(rings + 1):
        th = math.pi * i / rings                       # 0 üst
        for s in range(segments + 1):
            k = s / segments
            a = 2 * math.pi * (k - 0.5)
            d = np.array([math.sin(th) * math.sin(a), math.cos(th), math.sin(th) * math.cos(a)])
            q = np.sign(d) * np.abs(d) ** (2 / n)
            p = center + q * half
            p[1] = max(p[1], 0.018)
            pos.append(p)
            uv.append((k, 0.75 * (1 - i / rings)))
    cols = segments + 1
    faces = []
    for i in range(rings):
        for s in range(segments):
            a = i * cols + s
            faces += [(a, a + cols, a + 1), (a + 1, a + cols, a + cols + 1)]
    m = G.Mesh(pos, uv, faces)
    return orient(m, center, (0, 1, 0)) if False else m


def shoe_garment(kind):
    """Ayakkabı kalıbı → parçalar: 'main' (tasarım), 'sole' (düz taban rengi)."""
    upper, sole, shaft = G.Mesh(), G.Mesh(), G.Mesh()
    spec = {"hightop": (0.0, 0.080, 0.045, 0.044), "lowtop": (-0.004, 0.080, 0.0, 0.0), "flat": (-0.022, 0.084, 0.0, 0.0),
            "slipper": (-0.012, 0.086, 0.0, 0.0), "loafer": (-0.014, 0.084, 0.0, 0.0), "maryjane": (-0.020, 0.082, 0.0, 0.0),
            "ankle": (0.01, 0.082, 0.085, 0.060), "knee": (0.01, 0.080, 0.165, 0.058), "western": (0.01, 0.084, 0.165, 0.059),
            "cast": (0.02, 0.080, 0.17, 0.062), "zori": (-0.030, 0.084, 0.0, 0.0), "slide": (-0.024, 0.084, 0.0, 0.0)}[kind]
    height, length, shaft_h, shaft_r = spec
    for x in (1, -1):
        cx = 0.068 * x
        if kind != "zori":
            upper = upper + shoe_body(cx, length, height)
        sole_h = 0.014 if kind not in ("flat", "maryjane", "slide", "zori") else 0.009
        sole = sole + G.rounded_box((cx, sole_h / 2 + 0.002, 0.018), (0.049, sole_h / 2 + 0.002, length + 0.004), 4.0, 12, 4)
        if kind == "western":
            sole = sole + G.rounded_box((cx, 0.012, -0.045), (0.035, 0.014, 0.022), 4.0, 8, 3)
        if shaft_h:
            shaft = shaft + limb((cx, 0.055, -0.012), (cx, 0.055 + shaft_h, -0.008), [shaft_r, shaft_r * 0.98, shaft_r * 1.03], 12,
                                 u=(0.0, 1.0), v=(0.75, 0.97))
        if kind == "zori":
            for dz in (0.03, -0.01):
                strap = limb((cx + 0.04 * (1 if dz < 0 else 0.3), 0.022, dz), (cx, 0.05, 0.05), [0.007, 0.007], 6)
                upper = upper + swatch_uv(strap, "detail")
    main = upper + shaft
    return {"main": main.tagged("foot"), "sole": sole.tagged("foot")}
