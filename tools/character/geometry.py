# Karakter geometrisi: düşük poligonlu, yumuşak gölgeli parametrik parçalar (numpy). Uygulama uzayı: Y yukarı, +Z ileri
# (karakter kameraya bakar), X karakterin solu; metre. Her parça (konum, uv, üçgen) döner; normaller birleştirmede.
import math
import numpy as np


class Mesh:
    def __init__(self, positions=None, uvs=None, faces=None, region=None):
        self.p = np.zeros((0, 3)) if positions is None else np.asarray(positions, float)
        self.uv = np.zeros((0, 2)) if uvs is None else np.asarray(uvs, float)
        self.f = np.zeros((0, 3), int) if faces is None else np.asarray(faces, int)
        # Köşe başına deri bölgesi (ör. "arm"); None: mesh'in genel bölgesi (build_character.add_mesh).
        self.region = [None] * len(self.p) if region is None else list(region)

    def __add__(self, other):
        return Mesh(np.r_[self.p, other.p], np.r_[self.uv, other.uv], np.r_[self.f, other.f + len(self.p)],
                    self.region + other.region)

    def tagged(self, region):
        """Bütün köşeleri `region` bölgesine bağlar (kol parçaları gövdeyle aynı mesh'te olsa da kola göre deri alır)."""
        return Mesh(self.p, self.uv, self.f, [region] * len(self.p))

    def normals(self):
        n = np.zeros_like(self.p)
        a, b, c = self.p[self.f[:, 0]], self.p[self.f[:, 1]], self.p[self.f[:, 2]]
        fn = np.cross(b - a, c - a)
        for k in range(3):
            np.add.at(n, self.f[:, k], fn)
        length = np.linalg.norm(n, axis=1, keepdims=True)
        return n / np.where(length == 0, 1, length)

    def transformed(self, fn):
        return Mesh(fn(self.p.copy()), self.uv.copy(), self.f.copy(), self.region)

    @property
    def triangles(self):
        return len(self.f)


def grid_faces(rows, cols, wrap):
    """(rows+1) x (cols+1 ya da cols) ızgara, dörtgen başına iki üçgen (dışa bakan, saat yönü tersine)."""
    stride = cols if wrap else cols + 1
    faces = []
    for r in range(rows):
        for c in range(cols):
            a = r * stride + c
            b = r * stride + (c + 1) % stride if wrap else a + 1
            d = a + stride
            e = b + stride
            faces += [(a, b, d), (b, e, d)]
    return faces


def lathe(profile, segments=16, center=(0, 0, 0), zscale=1.0, xscale=1.0, u_repeat=1.0, v_scale=1.0, cap_bottom=False,
          cap_top=False):
    """Y ekseni etrafında döndürülmüş profil [(y, r)], aşağıdan yukarı. Kesit elips (xscale, zscale)."""
    cx, cy, cz = center
    pos, uv = [], []
    ys = [y for y, _ in profile]
    for y, r in profile:
        for s in range(segments + 1):
            a = 2 * math.pi * s / segments
            # açı 0: karakterin önü (+z); saat yönünün tersine sola doğru.
            pos.append((cx + r * xscale * math.sin(a), y, cz + r * zscale * math.cos(a)))
            uv.append((u_repeat * s / segments, (y - ys[0]) * v_scale))
    faces = []
    cols = segments + 1
    for i in range(len(profile) - 1):
        for s in range(segments):
            a = i * cols + s
            b, c, d = a + 1, a + cols, a + cols + 1
            faces += [(a, b, c), (b, d, c)]
    m = Mesh(pos, uv, faces)
    if cap_bottom:
        m = m + disk(profile[0], segments, center, zscale, xscale, down=True)
    if cap_top:
        m = m + disk(profile[-1], segments, center, zscale, xscale, down=False)
    return m


def disk(yr, segments, center, zscale, xscale, down):
    y, r = yr
    cx, _, cz = center
    pos = [(cx, y, cz)] + [(cx + r * xscale * math.sin(2 * math.pi * s / segments), y,
                           cz + r * zscale * math.cos(2 * math.pi * s / segments)) for s in range(segments)]
    uv = [(0.5, 0.5)] * (segments + 1)
    faces = [(0, (s + 1) % segments + 1, s % segments + 1) if down else (0, s % segments + 1, (s + 1) % segments + 1)
             for s in range(segments)]
    return Mesh(pos, uv, faces)


def ellipsoid(center, radii, segments=16, rings=10, theta=(0.0, math.pi), u_repeat=1.0, shape=None):
    """Elipsoid (theta: kutuptan kutba açı aralığı, 0 = üst). `shape(p)` noktaları sonradan biçimler."""
    cx, cy, cz = center
    rx, ry, rz = radii
    pos, uv = [], []
    for i in range(rings + 1):
        t = theta[0] + (theta[1] - theta[0]) * i / rings
        for s in range(segments + 1):
            a = 2 * math.pi * s / segments
            pos.append((cx + rx * math.sin(t) * math.sin(a), cy + ry * math.cos(t), cz + rz * math.sin(t) * math.cos(a)))
            uv.append((u_repeat * s / segments, 1 - i / rings))
    faces = []
    cols = segments + 1
    for i in range(rings):
        for s in range(segments):
            a = i * cols + s
            b, c, d = a + 1, a + cols, a + cols + 1
            faces += [(a, c, b), (b, c, d)]
    m = Mesh(pos, uv, faces)
    if shape:
        m.p = shape(m.p)
    return m


def rounded_box(center, half, n=3.0, segments=14, rings=10, floor=None):
    """Köşeleri yuvarlak kutu (süperelipsoit, üs `n`): `floor` verilirse altı o yükseklikte düzlenir (taban)."""
    m = ellipsoid((0, 0, 0), (1, 1, 1), segments, rings)
    q = np.sign(m.p) * np.abs(m.p) ** (2 / n)
    q = q * np.asarray(half, float) + np.asarray(center, float)
    if floor is not None:
        q[:, 1] = np.maximum(q[:, 1], floor)
    m.p = q
    return m


def tube(p0, p1, r0, r1, segments=10, rings=4, cap0=True, cap1=True, u_repeat=1.0, v_scale=1.0, flat=1.0):
    """p0'dan p1'e konik tüp; uçlarda yarım küre kapak. `flat`: kesitin ikinci ekseni (yassılık)."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    axis = p1 - p0
    length = np.linalg.norm(axis)
    w = axis / length
    ref = np.array([0, 0, 1.0]) if abs(w[2]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(w, ref); u /= np.linalg.norm(u)
    v = np.cross(w, u)
    profile = []  # (eksen boyunca konum, yarıçap)
    if cap0:
        for k in range(3, 0, -1):
            a = math.pi / 2 * k / 3
            profile.append((-r0 * math.sin(a) * 0.9, r0 * math.cos(a)))
    for i in range(rings + 1):
        t = i / rings
        profile.append((t * length, r0 + (r1 - r0) * t))
    if cap1:
        for k in range(1, 4):
            a = math.pi / 2 * k / 3
            profile.append((length + r1 * math.sin(a) * 0.9, r1 * math.cos(a)))
    pos, uv = [], []
    for d, r in profile:
        for s in range(segments + 1):
            a = 2 * math.pi * s / segments
            pos.append(p0 + w * d + (u * math.cos(a) + v * math.sin(a) * flat) * max(r, 1e-5))
            uv.append((u_repeat * s / segments, d * v_scale))
    faces = []
    cols = segments + 1
    for i in range(len(profile) - 1):
        for s in range(segments):
            a = i * cols + s
            b, c, d = a + 1, a + cols, a + cols + 1
            faces += [(a, b, c), (b, d, c)]
    return Mesh(pos, uv, faces)


def patch_on(surface, center, radii, phi, theta, cols=16, rows=8, lift=0.003, shape=None):
    """Elipsoid yüzeyine oturan ızgara (yüz çıkartmaları için): phi yatay açı (0 = ön), theta yükseklik açısı.
    UV: (0,0) sol alt, (1,1) sağ üst (karakterin bakışından: u, karakterin sağından soluna değil, izleyicinin
    soldan sağına)."""
    cx, cy, cz = center
    rx, ry, rz = radii
    pos, uv = [], []
    for i in range(rows + 1):
        th = theta[0] + (theta[1] - theta[0]) * i / rows
        for j in range(cols + 1):
            ph = phi[0] + (phi[1] - phi[0]) * j / cols
            x, y, z = rx * math.cos(th) * math.sin(ph), ry * math.sin(th), rz * math.cos(th) * math.cos(ph)
            p = np.array([cx + x, cy + y, cz + z])
            if shape is not None:
                p = shape(p[None])[0]
            n = np.array([x / rx ** 2, y / ry ** 2, z / rz ** 2]); n /= np.linalg.norm(n)
            pos.append(p + n * lift)
            uv.append((j / cols, i / rows))
    return Mesh(pos, uv, grid_faces(rows, cols, wrap=False))


def torus(center, normal, radius, tube_radius, segments=20, sides=6):
    """Halka: `normal` ekseni etrafında."""
    c, n = np.asarray(center, float), np.asarray(normal, float)
    n = n / np.linalg.norm(n)
    ref = np.array([0, 1.0, 0]) if abs(n[1]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(n, ref); u /= np.linalg.norm(u)
    v = np.cross(n, u)
    pos, uv = [], []
    for i in range(segments + 1):
        a = 2 * math.pi * i / segments
        ring = u * math.cos(a) + v * math.sin(a)
        for j in range(sides + 1):
            b = 2 * math.pi * j / sides
            pos.append(c + ring * (radius + tube_radius * math.cos(b)) + n * tube_radius * math.sin(b))
            uv.append((i / segments, j / sides))
    faces = []
    stride = sides + 1
    for i in range(segments):
        for j in range(sides):
            a = i * stride + j
            b, c2, d = a + 1, a + stride, a + stride + 1
            faces += [(a, b, c2), (b, d, c2)]
    m = Mesh(pos, uv, faces)
    # Dışa bakmıyorsa çevir (yön, u/v sırasına bağlı).
    a, b, c3 = m.p[m.f[:, 0]], m.p[m.f[:, 1]], m.p[m.f[:, 2]]
    centers = (a + b + c3) / 3
    rings = c + ((centers - c) - np.outer((centers - c) @ n, n))
    rings = c + (rings - c) / np.linalg.norm(rings - c, axis=1, keepdims=True) * radius
    if (np.einsum('ij,ij->i', np.cross(b - a, c3 - a), centers - rings) < 0).mean() > 0.5:
        m.f = m.f[:, [0, 2, 1]]
    return m
