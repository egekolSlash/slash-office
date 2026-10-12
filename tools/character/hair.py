# Saç modelleri: kafaya yakın oturan ince bir kabuk + alında düz kesilmiş kâkül paneli (tutamlar arasında ince V
# çentikler) + stile göre kuyruk, topuz, uzun arka panel. Açılar: phi yatay (0 = ön, +x'e doğru artar), polar kutuptan
# (0 = tepe, pi/2 = ekvator); saç çizgileri metre cinsinden yükseklikle verilir (`Head.polar_at`).
import math
import numpy as np
import geometry as G


class Head:
    """Kafa yüzeyi: süperelipsoit (yatay kesit daire; dikeyde alın ve çene düzleşir, tepe ve ense yuvarlak).
    `point(ph, polar, scale)`: parametre uzayında nokta, merkezden `scale` kat uzakta. Üst/alt yarıda ve önde/yanda/
    arkada üsler ayrı (önde büyük üs: düz yüz)."""
    def __init__(self, center, radii, exponents):
        self.c = np.array(center, float)
        self.r = np.array(radii, float)            # (yarı genişlik, yarı yükseklik, yarı derinlik)
        self.n = exponents                         # {"up": (yan, ön, arka), "down": (...)}

    def exponent(self, ph, polar):
        side, front, back = self.n["up" if polar < math.pi / 2 else "down"]
        s2, c = math.sin(ph) ** 2, math.cos(ph)
        return side * s2 + (front if c > 0 else back) * (1 - s2)

    def polar_at(self, ph, y):
        """Kafa yüzeyinde `ph` yönünde `y` yüksekliğine düşen kutup açısı."""
        lo, hi = 0.0, math.pi
        for _ in range(40):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if self.point(ph, mid)[1] > y else (lo, mid)
        return (lo + hi) / 2

    def point(self, ph, polar, scale=1.0):
        n = self.exponent(ph, polar)
        sp, cp = math.sin(polar), math.cos(polar)
        h = abs(sp) ** (2 / n)
        y = math.copysign(abs(cp) ** (2 / n), cp)
        d = np.array([h * math.sin(ph), y, h * math.cos(ph)])
        return self.c + self.r * scale * d

def cap(head, limit, scale_top=1.045, scale_edge=1.03, segments=32, rings=12, bump=0.0, bumps=0, flare=0.0):
    """Tepeden `limit(phi)` kutup açısına kadar saç kabuğu. `flare`: alt kenar dışa açılır (küt). Altta içe dönük kısa
    kenar (aşağıdan bakınca boşluk görünmesin)."""
    pos, uv = [], []
    for i in range(rings + 1):
        for s in range(segments + 1):
            ph = 2 * math.pi * s / segments - math.pi
            t = limit(ph) * i / rings
            scale = scale_top + (scale_edge - scale_top) * (i / rings) ** 1.5 + flare * (i / rings) ** 3
            if bumps:
                scale *= 1 + bump * math.cos(bumps * ph) * math.sin(t)
            pos.append(head.point(ph, t, scale))
            uv.append((3 * s / segments, 1 - i / rings))
    faces = []
    cols = segments + 1
    for i in range(rings):
        for s in range(segments):
            a = i * cols + s
            b, c, d = a + 1, a + cols, a + cols + 1
            faces += [(a, c, b), (b, c, d)]
    m = G.Mesh(pos, uv, faces)
    edge = m.p[rings * cols:]
    inner = head.c + (edge - head.c) * 0.96
    n = len(m.p)
    lip_faces = []
    for s in range(segments):
        a, b = rings * cols + s, rings * cols + s + 1
        lip_faces += [(a, b, n + s), (b, n + s + 1, n + s)]
    return G.Mesh(np.r_[m.p, inner], np.r_[m.uv, m.uv[rings * cols:]], np.r_[m.f, lip_faces])


def line(head, front, side, back):
    """Saç çizgisi: önde, yanlarda (kulak üstü) ve arkada bu yükseklikler (m); arası yumuşak."""
    sm = lambda a, b, t: float(np.clip((t - a) / (b - a), 0, 1) ** 2 * (3 - 2 * np.clip((t - a) / (b - a), 0, 1)))

    def y(ph):
        a = abs(ph)
        return front + (side - front) * sm(0.45, 1.35, a) + (back - side) * sm(1.7, 2.9, a)
    return lambda ph: head.polar_at(ph, y(ph))


def bangs(head, span, tip_y, side_y, locks=5, start=0.0, top=0.45, notch=0.045, scale=(1.035, 1.10), thickness=0.020,
          sweep=0.0, cols_per_lock=6, rows=7):
    """Kâkül paneli: tepeden (kabuğun altından) alına iner; alt kenarı düz kesik, tutamlar arasında V çentik. Uçta
    `tip_y` (ortada) ile `side_y` (kenarda) arası; `sweep` uçları yana kaydırır (yandan taranmış)."""
    cols = locks * cols_per_lock
    outer, inner, uv = [], [], []
    for i in range(rows + 1):
        t = i / rows
        for j in range(cols + 1):
            u = j / cols
            ph = start - span / 2 + span * u + sweep * t * t
            edge = abs(2 * u - 1)
            y_tip = tip_y + (side_y - tip_y) * edge ** 2
            k = (u * locks) % 1
            boundary = min(k, 1 - k) * locks if 0 < j < cols else 1.0   # 0: iki tutamın arası
            y_tip += notch * max(0.0, 1 - boundary * 6.0) ** 0.7   # dar, derin yarık
            polar = top + (head.polar_at(ph, y_tip) - top) * t
            sc = scale[0] + (scale[1] - scale[0]) * math.sin(math.pi / 2 * t) ** 1.5
            sc += 0.012 * math.sin(math.pi * k) * t     # tutamlar hafif dolgun
            outer.append(head.point(ph, polar, sc))
            inner.append(head.point(ph, polar, sc - thickness / head.r[1] * (0.4 + 0.6 * t)))
            uv.append((u * locks * 0.5, 1 - t))
    stride = cols + 1
    n = len(outer)
    faces = []
    for i in range(rows):
        for j in range(cols):
            a = i * stride + j
            b, c, d = a + 1, a + stride, a + stride + 1
            faces += [(a, c, b), (b, c, d)]
            faces += [(n + a, n + b, n + c), (n + b, n + d, n + c)]
    for j in range(cols):                                           # alt kenar (kesik)
        a, b = rows * stride + j, rows * stride + j + 1
        faces += [(a, b, n + a), (b, n + b, n + a)]
    for i in range(rows):                                           # yan kenarlar
        for j in (0, cols):
            a, c = i * stride + j, (i + 1) * stride + j
            faces += [(a, n + a, c), (c, n + a, n + c)] if j == 0 else [(a, c, n + a), (c, n + c, n + a)]
    return G.Mesh(np.r_[outer, inner], np.r_[uv, uv], faces)


def lock(head, ph, width, polar_top, polar_tip, scale=1.085, thickness=0.018, curl=0.0, sweep=0.0, rows=7, cols=4):
    """Bir tutam: üstte `width` (radyan) genişliğinde, uca doğru sivrilir. `curl`: uç dışa kıvrılır, `sweep`: uç yana
    kayar (radyan). Dış ve iç yüz + kenarlar (kapalı, her açıdan görünür)."""
    outer, inner, uv = [], [], []
    for i in range(rows + 1):
        t = i / rows
        polar = polar_top + (polar_tip - polar_top) * t
        half = width / 2 * (1 - t) ** 0.85 + 1e-4
        center = ph + sweep * t * t
        bulge = 0.012 * math.sin(math.pi * min(1, t * 1.3))
        for j in range(cols + 1):
            u = j / cols
            a = center - half + 2 * half * u
            puff = scale + bulge / head.r[1] * math.sin(math.pi * u) + curl * t ** 2
            p = head.point(a, polar, puff)
            q = head.point(a, polar, puff - thickness / head.r[1] * (1 - 0.7 * t))
            outer.append(p); inner.append(q)
            uv.append((u * 0.3 + ph, 1 - t))
    stride = cols + 1
    n = len(outer)
    faces = []
    for i in range(rows):
        for j in range(cols):
            a = i * stride + j
            b, c, d = a + 1, a + stride, a + stride + 1
            faces += [(a, c, b), (b, c, d)]                         # dış
            faces += [(n + a, n + b, n + c), (n + b, n + d, n + c)]  # iç (ters)
    for i in range(rows):                                           # yan kenarlar
        for j in (0, cols):
            a, c = i * stride + j, (i + 1) * stride + j
            faces += [(a, n + a, c), (c, n + a, n + c)] if j == 0 else [(a, c, n + a), (c, n + c, n + a)]
    for j in range(cols):                                           # üst kenar
        a, b = j, j + 1
        faces += [(a, b, n + a), (b, n + b, n + a)]
    return G.Mesh(np.r_[outer, inner], np.r_[uv, uv], faces)


def tail(p0, p1, r0, r1, bend=(0, 0, 0)):
    """Kuyruk (at kuyruğu, örgü): ortası `bend` kadar eğik tüp, uçta sivri."""
    p0, p1, bend = (np.asarray(v, float) for v in (p0, p1, bend))
    mid = (p0 + p1) / 2 + bend
    return G.tube(p0, mid, r0, (r0 + r1) / 2 * 1.08, 10, 3, cap0=True, cap1=False, u_repeat=2, v_scale=4) + \
        G.tube(mid, p1, (r0 + r1) / 2 * 1.08, r1, 10, 3, cap0=False, cap1=True, u_repeat=2, v_scale=4)


def band(center, radius, axis=(0, 0, 1)):
    """Saç lastiği: kısa, kalın halka (tüp)."""
    c, a = np.asarray(center, float), np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    return G.tube(c - a * 0.012, c + a * 0.012, radius, radius, 12, 1, cap0=True, cap1=True)


def styles(head):
    """Ad → (taban mesh'i, tepe mesh'i ya da None, lastik mesh'i ya da None). Şapka takılınca tepe (diken, topuz,
    bukle) çizilmez; taban şapkanın altında kalır."""
    L = lambda f, sd, b: line(head, f, sd, b)
    out = {}
    # Kısa: kulak üstüne inen yanlar, ensede kısa; 5 tutamlı düz kâkül.
    out["short"] = (cap(head, L(0.96, 0.80, 0.66)) + bangs(head, 2.3, 0.880, 0.80), None, None)
    # Küt: yanlar çene hizasında dışa açılır; 6 tutamlı kâkül.
    out["bob"] = (cap(head, L(0.96, 0.66, 0.64), scale_edge=1.06, flare=0.05)
                  + bangs(head, 2.0, 0.875, 0.82, locks=6, notch=0.030), None, None)
    # At kuyruğu: yana taranmış kâkül + ensenin üstünden sarkan kuyruk + lastik.
    out["ponytail"] = (cap(head, L(0.96, 0.80, 0.80)) + bangs(head, 2.2, 0.885, 0.80, locks=4, start=0.1, sweep=-0.12)
                       + tail((0, 0.97, -0.29), (0, 0.66, -0.43), 0.068, 0.020, bend=(0, 0.02, -0.07)), None,
                       band((0, 0.97, -0.29), 0.040, axis=(0, 0.35, -1)))
    # İki at kuyruğu: kulakların üstünden.
    out["pigtails"] = (cap(head, L(0.96, 0.80, 0.70)) + bangs(head, 2.3, 0.880, 0.80)
                       + tail((0.24, 0.86, -0.12), (0.31, 0.60, -0.10), 0.056, 0.018, bend=(0.05, 0, 0))
                       + tail((-0.24, 0.86, -0.12), (-0.31, 0.60, -0.10), 0.056, 0.018, bend=(-0.05, 0, 0)), None,
                       band((0.24, 0.86, -0.12), 0.032, axis=(1, -0.3, 0)) + band((-0.24, 0.86, -0.12), 0.032, axis=(-1, -0.3, 0)))
    # Diken: kısa kâkül + tepede yukarı-dışa kalkık tutamlar.
    spikes = G.Mesh()
    for k, (ph, polar) in enumerate([(a, 0.62) for a in np.linspace(-2.6, 2.6, 7)] + [(-0.4, 0.62), (0.4, 0.62), (0.0, 0.25)]):
        base = head.point(ph, polar, 1.0)
        normal = base - head.c
        normal /= np.linalg.norm(normal)
        d = normal * 0.8 + np.array([0.0, 0.6, 0.0])
        d /= np.linalg.norm(d)
        length = 0.090 + 0.02 * (k % 2)
        spikes = spikes + G.tube(base, base + d * length, 0.062, 0.006, 8, 2, cap0=False, cap1=False, u_repeat=1, v_scale=4)
    out["spiky"] = (cap(head, L(0.97, 0.82, 0.68)) + bangs(head, 2.0, 0.900, 0.84, locks=6, notch=0.045), spikes, None)
    # Uzun: yanlar ve arka omuza kadar (arka panel), düz kâkül.
    back = G.lathe([(0.46, 0.215), (0.56, 0.240), (0.66, 0.250), (0.76, 0.252)], segments=20, center=(0, 0, -0.06),
                   zscale=0.96, u_repeat=3, v_scale=4)
    back = back.transformed(lambda q: np.where((q[:, 2] > -0.02)[:, None], q * [1, 1, 0] + [0, 0, -0.02], q))
    out["long"] = (cap(head, L(0.96, 0.70, 0.70), scale_edge=1.05) + back
                   + bangs(head, 2.5, 0.880, 0.62, locks=5), None, None)
    # Topuz: geriye taranmış (kâküksüz, alın açık), tepede topuz + lastik.
    out["bun"] = (cap(head, L(0.955, 0.80, 0.66), scale_top=1.04),
                  G.ellipsoid((0, 1.115, -0.10), (0.080, 0.070, 0.080), 14, 9) + band((0, 1.06, -0.10), 0.048, axis=(0, 1, -0.3)), None)
    # Kazıma: başa yapışık ince kabuk.
    out["buzz"] = (cap(head, L(0.95, 0.82, 0.70), scale_top=1.018, scale_edge=1.012), None, None)
    # Kıvırcık: kabuk + üstüne serpilmiş küçük bukleler.
    curls = G.Mesh()
    curly_line = L(0.95, 0.76, 0.66)
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(90):
        y = 1 - 2 * (k + 0.5) / 90
        polar, ph = math.acos(y), (k * golden) % (2 * math.pi) - math.pi
        if polar > curly_line(ph) - 0.10:
            continue
        p = head.point(ph, polar, 1.05)
        c = G.ellipsoid(tuple(p), (0.044, 0.040, 0.044), 6, 4)
        c.uv[:] = (0.5, 0.75)   # düz ton (tel deseni bukleyi kavun gibi çizgili gösteriyordu)
        curls = curls + c
    out["curly"] = (cap(head, curly_line, scale_top=1.06, scale_edge=1.05), curls, None)
    # Yandan ayrık: kâkül bir yana taranır, ayrık tarafı kısa.
    out["sidepart"] = (cap(head, L(0.97, 0.80, 0.66)) + bangs(head, 2.0, 0.890, 0.80, locks=4, start=0.25, sweep=0.35,
                                                               notch=0.03, scale=(1.04, 1.11)), None, None)
    return out
