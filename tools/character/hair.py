# Saç modelleri: kafayı saran hacimli bir kapak + tutamlar. Tutam: kafa yüzeyini izleyen, kalınlığı olan, uca doğru
# sivrilen kavisli bir şerit (alında kâkül, kulak önünde yan tutam, ensede kısa tutam). Açılar: phi yatay (0 = ön,
# +x'e doğru artar), polar kutuptan (0 = tepe, pi/2 = ekvator).
import math
import numpy as np
import geometry as G


class Head:
    def __init__(self, center, radii, shape):
        self.c = np.array(center, float)
        self.r = np.array(radii, float)
        self.shape = shape

    def point(self, ph, polar, scale):
        d = np.array([math.sin(polar) * math.sin(ph), math.cos(polar), math.sin(polar) * math.cos(ph)])
        p = self.c + self.r * scale * d
        return self.shape(p[None])[0]


def cap(head, limit, scale_top=1.10, scale_edge=1.055, segments=28, rings=12, bump=0.0, bumps=0):
    """Tepeden `limit(phi)` kutup açısına kadar saç kapağı; tepede daha hacimli. Altta içe dönük kısa kenar."""
    pos, uv = [], []
    for i in range(rings + 1):
        for s in range(segments + 1):
            ph = 2 * math.pi * s / segments - math.pi
            t = limit(ph) * i / rings
            scale = scale_top + (scale_edge - scale_top) * (i / rings) ** 1.5
            if bumps:
                scale *= 1 + bump * math.cos(bumps * ph) * math.sin(t)
            pos.append(head.point(ph, t, scale))
            uv.append((2 * s / segments, 1 - i / rings))
    faces = []
    cols = segments + 1
    for i in range(rings):
        for s in range(segments):
            a = i * cols + s
            b, c, d = a + 1, a + cols, a + cols + 1
            faces += [(a, c, b), (b, c, d)]
    m = G.Mesh(pos, uv, faces)
    # İç kenar: kalınlık hissi (aşağıdan bakınca boşluk görünmesin).
    edge = m.p[rings * cols:]
    inner = head.c + (edge - head.c) * 0.95
    n = len(m.p)
    lip_faces = []
    for s in range(segments):
        a, b = rings * cols + s, rings * cols + s + 1
        lip_faces += [(a, b, n + s), (b, n + s + 1, n + s)]
    return G.Mesh(np.r_[m.p, inner], np.r_[m.uv, m.uv[rings * cols:]], np.r_[m.f, lip_faces])


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


def fringe(head, count, span, polar_top, polar_tip, start=0.0, scale=1.085, jitter=0.06, sweep=0.0, widen=1.35):
    """Alında yan yana tutamlar (kâkül): uçlar biraz farklı uzunlukta."""
    m = G.Mesh()
    width = span / count * widen
    for k in range(count):
        ph = start - span / 2 + span * (k + 0.5) / count
        tip = polar_tip + jitter * math.sin(k * 2.3 + 0.7)
        m = m + lock(head, ph, width, polar_top, tip, scale=scale + 0.004 * (k % 2), sweep=sweep)
    return m


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
    sm = lambda a, b, t: float(np.clip((t - a) / (b - a), 0, 1) ** 2 * (3 - 2 * np.clip((t - a) / (b - a), 0, 1)))

    def line(front, side, back):
        """Saç çizgisi (kapak sınırı): önde `front`, yanlarda `side`, arkada `back` kutup açısı."""
        return lambda ph: front + (side - front) * sm(0.5, 1.4, abs(ph)) + (back - side) * sm(1.6, 2.9, abs(ph))

    out = {}
    # Kısa: kâkül 5 tutam, kulak önünde yan tutamlar, ensede 3 kısa tutam.
    short = cap(head, line(1.02, 1.40, 2.00)) + fringe(head, 5, 1.55, 0.78, 1.36) \
        + lock(head, 1.18, 0.30, 1.05, 1.80, sweep=-0.10) + lock(head, -1.18, 0.30, 1.05, 1.80, sweep=0.10) \
        + fringe(head, 3, 0.9, 1.75, 2.18, start=math.pi, jitter=0.04)
    out["short"] = (short, None, None)
    # Küt: yanlar çeneye kadar, uçları hafif içe; düz kâkül.
    out["bob"] = (cap(head, line(1.02, 2.02, 2.15), scale_edge=1.10, bump=0.015, bumps=9)
                  + fringe(head, 6, 1.6, 0.80, 1.34, jitter=0.02, widen=1.25), None, None)
    # At kuyruğu: yana taranmış kâkül + arkadan sarkan kuyruk + lastik.
    out["ponytail"] = (cap(head, line(1.00, 1.45, 1.70)) + fringe(head, 4, 1.4, 0.78, 1.33, start=0.15, sweep=-0.18)
                       + tail((0, 0.95, -0.31), (0, 0.66, -0.43), 0.070, 0.022, bend=(0, 0, -0.05)), None,
                       band((0, 0.95, -0.31), 0.042, axis=(0, 0.35, -1)))
    # İki at kuyruğu: yanlardan.
    out["pigtails"] = (cap(head, line(1.02, 1.45, 1.85)) + fringe(head, 5, 1.5, 0.80, 1.35)
                       + tail((0.25, 0.84, -0.13), (0.33, 0.60, -0.10), 0.058, 0.020, bend=(0.04, 0, 0))
                       + tail((-0.25, 0.84, -0.13), (-0.33, 0.60, -0.10), 0.058, 0.020, bend=(-0.04, 0, 0)), None,
                       band((0.25, 0.84, -0.13), 0.034, axis=(1, -0.3, 0)) + band((-0.25, 0.84, -0.13), 0.034, axis=(-1, -0.3, 0)))
    # Diken: kısa sivri kâkül + tepede dışa kıvrık sivri tutamlar.
    spikes = G.Mesh()
    for k, (ph, polar) in enumerate([(a, 0.55) for a in np.linspace(-2.7, 2.7, 7)] + [(-0.35, 0.75), (0.35, 0.75), (0.0, 0.25)]):
        base = head.point(ph, polar, 1.04)
        normal = base - head.c
        normal /= np.linalg.norm(normal)
        up = np.array([0.0, 1.0, 0.0])
        d = normal * 0.85 + up * 0.55
        d /= np.linalg.norm(d)
        length = 0.085 + 0.02 * (k % 2)
        spikes = spikes + G.tube(base, base + d * length, 0.06, 0.005, 8, 2, cap0=False, cap1=False, u_repeat=1, v_scale=4)
    out["spiky"] = (cap(head, line(1.05, 1.42, 1.95)) + fringe(head, 6, 1.6, 0.78, 1.30, jitter=0.07), spikes, None)
    # Uzun: yanlar ve arka omuza kadar (arka panel), önde uzun yan tutamlar.
    back = G.lathe([(0.47, 0.215), (0.56, 0.245), (0.66, 0.262), (0.76, 0.27)], segments=18, center=(0, 0, -0.07),
                   zscale=0.82, u_repeat=2, v_scale=4)
    back = back.transformed(lambda q: np.where((q[:, 2] > -0.04)[:, None], q * [1, 1, 0] + [0, 0, -0.04], q))
    out["long"] = (cap(head, line(1.02, 2.10, 2.25), scale_edge=1.09, bump=0.012, bumps=11) + back
                   + fringe(head, 5, 1.45, 0.80, 1.34, jitter=0.03)
                   + lock(head, 1.05, 0.40, 1.0, 2.35) + lock(head, -1.05, 0.40, 1.0, 2.35), None, None)
    # Topuz: geriye taranmış (kısa yan tutamlar), tepede topuz + lastik.
    out["bun"] = (cap(head, line(0.95, 1.40, 1.80)) + lock(head, 0.45, 0.6, 0.6, 1.25, sweep=0.25)
                  + lock(head, -0.45, 0.6, 0.6, 1.25, sweep=-0.25),
                  G.ellipsoid((0, 1.11, -0.07), (0.085, 0.072, 0.085), 14, 9) + band((0, 1.05, -0.07), 0.05, axis=(0, 1, 0)), None)
    # Kazıma: başa yakın ince kapak.
    out["buzz"] = (cap(head, line(1.00, 1.30, 1.95), scale_top=1.03, scale_edge=1.02), None, None)
    # Kıvırcık: hacimli kapak + üstüne serpilmiş küçük bukleler.
    curls = G.Mesh()
    curly_line = line(1.00, 1.55, 2.00)
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(70):
        # Fibonacci küresi: kafa üstüne eşit dağılım; saç çizgisinin altındakiler atlanır.
        y = 1 - 2 * (k + 0.5) / 70
        polar, ph = math.acos(y), (k * golden) % (2 * math.pi) - math.pi
        if polar > curly_line(ph) - 0.12:
            continue
        p = head.point(ph, polar, 1.08)
        c = G.ellipsoid(tuple(p), (0.056, 0.050, 0.056), 8, 6)
        c.uv[:] = (0.5, 0.75)   # düz ton (tel deseni bukleyi kavun gibi çizgili gösteriyordu)
        curls = curls + c
    out["curly"] = (cap(head, curly_line, scale_top=1.10, scale_edge=1.07), curls, None)
    # Yandan ayrık: bir yandan öbür yana taranan büyük tutam + ayrık çizgisinin öbür yanında kısa tutamlar.
    out["sidepart"] = (cap(head, line(1.00, 1.45, 1.95)) + lock(head, -0.15, 1.15, 0.55, 1.30, sweep=0.55, scale=1.095)
                       + fringe(head, 2, 0.6, 0.85, 1.25, start=-0.80) + lock(head, 1.18, 0.30, 1.05, 1.75)
                       + lock(head, -1.18, 0.30, 1.05, 1.75), None, None)
    return out
