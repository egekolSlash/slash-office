# Oda dekor eşyaları: kendi düşük poligon modellerimiz (referansa bakılarak, parametrik). Ofisin öteki eşyalarıyla
# aynı biçim: köşe renkli (sRGB 8 bit, alfa = emissive/4), dokusuz; düz gölgeli kutular, yumuşak yuvarlak parçalar.
# Çalıştır: Blender -b --factory-startup --python tools/furniture/build_furniture.py -- Resources/OfficeArt/furniture.json
# Sözleşme (OfficeArtFile.props): uygulama uzayı (Y yukarı, metre). Zemin eşyaları: orijin taban ortası, ön yüz +x.
# Duvar eşyaları: orijin arka yüzün ortası (duvara değer), ön yüz +x.
import base64, json, math, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "character"))
import geometry as G  # noqa: E402
import numpy as np  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1]


class Prop:
    """Renkli parçalardan oluşan eşya."""
    def __init__(self):
        self.parts = []   # (Mesh, normaller, rgba)

    def add(self, mesh, color, emissive=0.0, flat=False):
        if flat:
            # Düz gölge: her üçgen kendi köşeleri.
            p = mesh.p[mesh.f].reshape(-1, 3)
            uv = mesh.uv[mesh.f].reshape(-1, 2)
            f = np.arange(len(p)).reshape(-1, 3)
            mesh = G.Mesh(p, uv, f)
            a, b, c = p[0::3], p[1::3], p[2::3]
            n = np.cross(b - a, c - a)
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
            normals = np.repeat(n, 3, axis=0)
        else:
            normals = mesh.normals()
        rgba = tuple(int(round(min(max(c, 0), 1) * 255)) for c in color) + (int(round(min(emissive / 4, 1) * 255)),)
        self.parts.append((mesh, normals, rgba))
        return self

    def json(self):
        pos, nrm, uv, col, idx = [], [], [], [], []
        base = 0
        for mesh, normals, rgba in self.parts:
            pos.append(mesh.p); nrm.append(normals); uv.append(mesh.uv)
            col.append(np.tile(rgba, (len(mesh.p), 1)))
            idx.append(mesh.f.ravel() + base)
            base += len(mesh.p)
        enc = lambda a, t: base64.b64encode(np.ascontiguousarray(np.concatenate(a), dtype=t).tobytes()).decode()
        return {"vertexCount": base, "positions": enc(pos, "<f4"), "normals": enc(nrm, "<f4"), "uvs": enc(uv, "<f4"),
                "colors": enc(col, "u1"), "indices": enc(idx, "<u4")}

    @property
    def triangles(self):
        return sum(len(m.f) for m, _, _ in self.parts)


def box(cx, cy, cz, hx, hy, hz):
    """Eksen hizalı kutu (merkez, yarı ölçüler); dışa bakan."""
    corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], float) * [hx, hy, hz] + [cx, cy, cz]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    faces = []
    for a, b, c, d in quads:
        faces += [(a, b, c), (a, c, d)]
    m = G.Mesh(corners, np.zeros((8, 2)), faces)
    # Yönü düzelt (dışa).
    tri = m.p[m.f]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    out = np.einsum("ij,ij->i", n, tri.mean(axis=1) - [cx, cy, cz]) < 0
    m.f[out] = m.f[out][:, [0, 2, 1]]
    return m


def cylinder(cx, cz, y0, y1, r0, r1=None, segments=14, axis="y"):
    r1 = r0 if r1 is None else r1
    m = G.lathe([(y0, r0), (y1, r1)], segments, center=(0, 0, 0), cap_bottom=True, cap_top=True)
    if axis == "x":   # x ekseni boyunca (duvar saati): y'yi x'e çevir
        m.p = np.c_[m.p[:, 1], m.p[:, 2], m.p[:, 0]]
        m.f = m.f[:, [0, 2, 1]]
        m.p += [0, cx, cz]
        return m
    m.p += [cx, 0, cz]
    return m


GRAY, DARK, WHITE = (0.86, 0.87, 0.88), (0.20, 0.21, 0.24), (0.96, 0.96, 0.95)
PROPS = {}

# Fotokopi makinesi / yazıcı.
p = Prop()
p.add(box(0, 0.03, 0, 0.27, 0.03, 0.30), DARK, flat=True)
p.add(box(0, 0.38, 0, 0.27, 0.32, 0.30), GRAY, flat=True)
p.add(box(0, 0.73, 0, 0.26, 0.03, 0.29), (0.74, 0.76, 0.78), flat=True)
p.add(box(0.20, 0.72, 0.17, 0.08, 0.03, 0.10), (0.42, 0.52, 0.62), flat=True)
p.add(box(0.27, 0.735, 0.20, 0.012, 0.012, 0.012), (0.3, 0.9, 0.4), emissive=2.5, flat=True)
for y in (0.20, 0.36):
    p.add(box(0.272, y, 0, 0.004, 0.012, 0.24), (0.55, 0.57, 0.60), flat=True)
p.add(box(0.02, 0.56, -0.36, 0.18, 0.012, 0.07), WHITE, flat=True)
PROPS["decor_printer"] = p

# Dosya dolabı: üç çekmece, kulplar.
p = Prop()
p.add(box(0, 0.38, 0, 0.22, 0.38, 0.22), (0.60, 0.67, 0.66), flat=True)
for i, y in enumerate((0.14, 0.38, 0.62)):
    p.add(box(0.225, y, 0, 0.01, 0.10, 0.19), (0.66, 0.73, 0.72), flat=True)
    p.add(box(0.24, y + 0.05, 0, 0.012, 0.012, 0.06), DARK, flat=True)
    p.add(box(0.236, y - 0.03, 0, 0.005, 0.02, 0.05), WHITE, flat=True)
PROPS["decor_file_cabinet"] = p

# Sunucu kabini: koyu gövde, açık cam ön, yanıp sönen ışık sıraları.
p = Prop()
p.add(box(0, 0.72, 0, 0.29, 0.72, 0.27), DARK, flat=True)
p.add(box(0.29, 0.72, 0, 0.006, 0.65, 0.22), (0.30, 0.34, 0.40), flat=True)
for i in range(8):
    y = 0.22 + i * 0.14
    p.add(box(0.30, y, -0.02, 0.004, 0.035, 0.16), (0.14, 0.15, 0.18), flat=True)
    p.add(box(0.305, y, 0.15, 0.004, 0.008, 0.008), (0.3, 0.95, 0.5) if i % 3 else (0.35, 0.65, 1.0), emissive=3, flat=True)
PROPS["decor_server_rack"] = p

# Mini buzdolabı.
p = Prop()
p.add(box(0, 0.33, 0, 0.24, 0.33, 0.24), (0.93, 0.94, 0.95), flat=True)
p.add(box(0.245, 0.30, 0, 0.004, 0.26, 0.22), (0.97, 0.97, 0.98), flat=True)
p.add(box(0.255, 0.42, 0.18, 0.01, 0.10, 0.012), (0.62, 0.64, 0.68), flat=True)
p.add(box(0, 0.665, 0, 0.245, 0.006, 0.245), (0.55, 0.78, 0.86), flat=True)
PROPS["decor_mini_fridge"] = p

# İçecek otomatı: kırmızı gövde, cam arkasında renkli kutular, para ve çıkış yuvaları.
p = Prop()
p.add(box(0, 0.82, 0, 0.32, 0.82, 0.37), (0.86, 0.27, 0.25), flat=True)
p.add(box(0.322, 1.02, -0.06, 0.004, 0.50, 0.26), (0.20, 0.22, 0.30), emissive=0.6, flat=True)
cans = [(0.96, 0.84, 0.30), (0.40, 0.70, 0.95), (0.98, 0.55, 0.25), (0.55, 0.85, 0.45), (0.95, 0.45, 0.65)]
for row, y in enumerate((0.66, 0.92, 1.18, 1.42)):
    for k in range(5):
        p.add(cylinder(0.352, -0.27 + k * 0.105, y - 0.07, y + 0.06, 0.028, segments=8), cans[(k + row) % 5], emissive=0.3)
    p.add(box(0.345, y - 0.085, -0.06, 0.022, 0.006, 0.25), (0.75, 0.76, 0.78), flat=True)
p.add(box(0.322, 1.00, 0.28, 0.006, 0.10, 0.04), (0.88, 0.88, 0.90), flat=True)
p.add(box(0.322, 0.22, -0.06, 0.006, 0.06, 0.20), (0.10, 0.10, 0.12), flat=True)
PROPS["decor_vending_machine"] = p

# Puf koltuk: basık, tepesi çökük yumuşak kütle.
def beanbag_shape(q):
    r = np.hypot(q[:, 0], q[:, 2])
    dip = 0.10 * np.exp(-(r / 0.22) ** 2) * (q[:, 1] > 0.18)
    back = 0.08 * np.clip(-q[:, 0] / 0.4, 0, 1) * (q[:, 1] > 0.1)
    return np.c_[q[:, 0], np.maximum(q[:, 1] - dip + back, 0.0), q[:, 2]]
p = Prop()
p.add(G.ellipsoid((0, 0.21, 0), (0.42, 0.23, 0.40), 18, 10, shape=beanbag_shape), (0.36, 0.67, 0.70))
PROPS["decor_beanbag"] = p

# Lambader: taban, sap, ışık veren başlık.
p = Prop()
p.add(cylinder(0, 0, 0.0, 0.03, 0.16, segments=16), DARK)
p.add(cylinder(0, 0, 0.03, 1.32, 0.016, segments=8), (0.55, 0.50, 0.42))
p.add(G.lathe([(1.22, 0.20), (1.47, 0.13)], 16, cap_bottom=False, cap_top=True), (0.99, 0.93, 0.78), emissive=1.5)
PROPS["decor_floor_lamp"] = p

# Büyük saksı bitkisi (monstera benzeri): saksı, toprak, saplar ve iri yapraklar.
p = Prop()
p.add(G.lathe([(0.0, 0.14), (0.30, 0.18), (0.32, 0.19)], 14, cap_bottom=True), (0.80, 0.50, 0.35))
p.add(cylinder(0, 0, 0.28, 0.30, 0.17), (0.35, 0.25, 0.18))
leaves = [(0.0, 1.05, 0.25, 0.35), (2.1, 0.92, 0.30, 0.0), (4.2, 0.98, 0.28, -0.2), (1.0, 0.72, 0.32, 0.4), (3.2, 0.70, 0.34, 0.2),
          (5.2, 0.78, 0.30, -0.3)]
for ang, h, reach, tilt in leaves:
    tip = np.array([math.cos(ang) * reach, h, math.sin(ang) * reach])
    p.add(G.tube((0, 0.30, 0), tip * [0.85, 1, 0.85], 0.012, 0.008, 6, 3, cap0=False, cap1=False), (0.32, 0.52, 0.28))
    leaf = G.ellipsoid((0, 0, 0), (0.17, 0.018, 0.12), 10, 5)
    rot = np.array([[math.cos(ang), 0, -math.sin(ang)], [0, 1, 0], [math.sin(ang), 0, math.cos(ang)]])
    tilt_m = np.array([[math.cos(0.5), -math.sin(0.5), 0], [math.sin(0.5), math.cos(0.5), 0], [0, 0, 1]])
    leaf.p = (leaf.p @ tilt_m.T) @ rot.T + tip
    p.add(leaf, (0.22, 0.55, 0.30) if ang % 2 < 1 else (0.30, 0.62, 0.34))
PROPS["decor_big_plant"] = p

# Kaktüs: küçük saksı, gövde, iki kol, tepede çiçek.
p = Prop()
p.add(G.lathe([(0.0, 0.10), (0.18, 0.12), (0.20, 0.125)], 12, cap_bottom=True), (0.92, 0.82, 0.62))
p.add(G.tube((0, 0.18, 0), (0, 0.72, 0), 0.07, 0.062, 10, 4, cap0=False, cap1=True), (0.33, 0.62, 0.36))
for side in (1, -1):
    p.add(G.tube((0, 0.40 + 0.08 * side, side * 0.05), (0, 0.42 + 0.08 * side, side * 0.15), 0.035, 0.035, 8, 1, cap0=False, cap1=False),
          (0.33, 0.62, 0.36))
    p.add(G.tube((0, 0.42 + 0.08 * side, side * 0.15), (0, 0.58 + 0.08 * side, side * 0.16), 0.035, 0.03, 8, 2, cap0=True, cap1=True),
          (0.33, 0.62, 0.36))
p.add(G.ellipsoid((0, 0.79, 0), (0.035, 0.022, 0.035), 8, 5), (0.98, 0.50, 0.66))
PROPS["decor_cactus"] = p

# Çöp kutusu: açık ağızlı konik kova, içinde buruşuk kâğıt.
p = Prop()
p.add(G.lathe([(0.0, 0.12), (0.32, 0.15)], 14, cap_bottom=True), (0.52, 0.66, 0.78))
p.add(G.lathe([(0.32, 0.14), (0.02, 0.11)], 14, cap_bottom=True), (0.40, 0.52, 0.62))
p.add(G.ellipsoid((0.02, 0.28, 0.02), (0.055, 0.05, 0.055), 7, 5), WHITE, flat=True)
PROPS["decor_trash_bin"] = p

# Duvar saati: çerçeveli yuvarlak kadran, akrep, yelkovan.
p = Prop()
p.add(cylinder(0.0, 0.0, 0.0, 0.045, 0.17, segments=24, axis="x"), (0.95, 0.62, 0.30))
p.add(cylinder(0.0, 0.0, 0.045, 0.05, 0.145, segments=24, axis="x"), WHITE)
for k in range(12):
    a = k * math.pi / 6
    p.add(box(0.052, 0.12 * math.cos(a), 0.12 * math.sin(a), 0.003, 0.012 if k % 3 else 0.02, 0.006), DARK, flat=True)
p.add(box(0.056, 0.035, 0.0, 0.003, 0.045, 0.008), DARK, flat=True)
p.add(box(0.058, 0.0, 0.045, 0.003, 0.006, 0.065), DARK, flat=True)
PROPS["decor_wall_clock"] = p

# Mantar pano: ahşap çerçeve, mantar, iğneli notlar ve fotoğraflar.
p = Prop()
p.add(box(0.015, 0, 0, 0.015, 0.27, 0.42), (0.62, 0.43, 0.28), flat=True)
p.add(box(0.032, 0, 0, 0.004, 0.24, 0.39), (0.83, 0.66, 0.45), flat=True)
notes = [((0.10, -0.25), (0.98, 0.90, 0.45)), ((0.08, -0.05), (0.98, 0.70, 0.78)), ((-0.06, 0.18), (0.60, 0.82, 0.98)),
         ((0.12, 0.25), WHITE), ((-0.10, -0.20), (0.75, 0.92, 0.65)), ((-0.08, 0.02), WHITE)]
for (y, z), color in notes:
    p.add(box(0.038, y, z, 0.003, 0.055, 0.06), color, flat=True)
    p.add(box(0.044, y + 0.045, z, 0.006, 0.008, 0.008), (0.90, 0.25, 0.25), flat=True)
PROPS["decor_corkboard"] = p

# Çerçeve: ahşap çerçeve, içinde gökyüzü, tepe ve güneş.
p = Prop()
p.add(box(0.012, 0, 0, 0.012, 0.22, 0.18), (0.95, 0.95, 0.93), flat=True)
p.add(box(0.026, 0.04, 0, 0.003, 0.14, 0.15), (0.62, 0.82, 0.96), flat=True)
p.add(box(0.029, -0.10, 0, 0.003, 0.05, 0.15), (0.48, 0.74, 0.42), flat=True)
p.add(cylinder(0.031, 0.06, 0.07, 0.034, 0.035, segments=12, axis="x").transformed(lambda q: q), (0.99, 0.82, 0.35))
PROPS["decor_picture"] = p

out = {"props": {name: prop.json() for name, prop in PROPS.items()}}
json.dump(out, open(OUT, "w"))
print("FURNITURE %d props, triangles %s, %.0fKB" % (len(PROPS), {k: v.triangles for k, v in PROPS.items()}, os.path.getsize(OUT) / 1e3))
