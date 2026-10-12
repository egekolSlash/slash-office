# Karakter dokuları (kendi çizimimiz, numpy ile kenar yumuşatmalı): göz ve ağız ifadeleri, yanak allığı, saç teli,
# kıyafet desenleri. Görüntüler (yükseklik, genişlik, 4) RGBA, satır 0 = üst; düz (önceden çarpılmamış) alfa.
import math
import numpy as np

INK = (0.20, 0.13, 0.10)        # göz/ağız çizgisi: koyu kahve
MOUTH_IN = (0.86, 0.30, 0.30)   # ağız içi
TONGUE = (0.98, 0.55, 0.55)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgba = np.zeros((h, w, 4))
        ys, xs = np.mgrid[0:h, 0:w]
        # Normalize koordinatlar: x 0..1 soldan sağa, y 0..1 aşağıdan yukarı (çizim kolaylığı).
        self.x = (xs + 0.5) / w
        self.y = 1 - (ys + 0.5) / h
        self.px = 1.0 / h   # kenar yumuşatma genişliği (y biriminde)

    def paint(self, sdf, color, alpha=1.0):
        """sdf < 0 içerisi. Üstüne düz alfa ile boyar."""
        cov = np.clip(0.5 - sdf / (1.5 * self.px), 0, 1) * alpha
        c = np.asarray(color, float)
        a0 = self.rgba[..., 3:4]
        a = cov[..., None]
        out_a = a + a0 * (1 - a)
        rgb = (c * a + self.rgba[..., :3] * a0 * (1 - a)) / np.where(out_a == 0, 1, out_a)
        self.rgba[..., :3] = rgb
        self.rgba[..., 3:4] = out_a

    # Uzaklık alanları (y birimi; x en-boy oranına göre ölçeklenir).
    def ellipse(self, cx, cy, rx, ry, angle=0.0):
        k = self.w / self.h
        dx, dy = (self.x - cx) * k, self.y - cy
        ca, sa = math.cos(angle), math.sin(angle)
        u, v = dx * ca + dy * sa, -dx * sa + dy * ca
        r = np.sqrt((u / rx) ** 2 + (v / ry) ** 2)
        return (r - 1) * min(rx, ry)

    def segment(self, ax, ay, bx, by, width):
        k = self.w / self.h
        px, py = self.x * k, self.y
        ax, bx = ax * k, bx * k
        dx, dy = bx - ax, by - ay
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy + 1e-12), 0, 1)
        return np.hypot(px - ax - t * dx, py - ay - t * dy) - width / 2

    def polyline(self, pts, width):
        d = None
        for a, b in zip(pts, pts[1:]):
            s = self.segment(a[0], a[1], b[0], b[1], width)
            d = s if d is None else np.minimum(d, s)
        return d

    def arc(self, cx, cy, rx, ry, a0, a1, width, n=24):
        k = self.w / self.h
        pts = [(cx + rx * math.cos(a0 + (a1 - a0) * i / n) / k, cy + ry * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
        return self.polyline(pts, width)


# ---------------------------------------------------------------- gözler (256 x 128, iki göz u=0.30 / 0.70)
EYE_EXPRESSIONS = ["normal", "happy", "wide", "sleepy", "worried", "side", "closed", "focused"]
EYE_STYLES = 6


def eye_texture(style, expression):
    c = Canvas(256, 128)
    for side, cx in ((-1, 0.25), (1, 0.75)):
        cy = 0.50
        if expression in ("happy", "closed"):
            # Mutlu: yukarı kavis (^), kapalı: aşağı kavis.
            up = expression == "happy"
            a0, a1 = (math.pi * 0.15, math.pi * 0.85) if up else (math.pi * 1.15, math.pi * 1.85)
            c.paint(c.arc(cx, cy - (0.12 if up else -0.10), 0.24, 0.26, a0, a1, 0.09), INK)
            continue
        if expression == "sleepy":
            c.paint(c.segment(cx - 0.085, cy - 0.04, cx + 0.085, cy - 0.04, 0.08), INK)
            continue
        size = {0: (0.11, 0.27), 1: (0.135, 0.29), 2: (0.11, 0.26), 3: (0.13, 0.20), 4: (0.15, 0.31), 5: (0.10, 0.25)}[style]
        rx, ry = size
        if expression == "wide":
            # Beyazı büyük, bebeği küçük.
            c.paint(c.ellipse(cx, cy, rx * 1.35, ry * 1.25), INK)
            c.paint(c.ellipse(cx, cy, rx * 1.35 - 0.035, ry * 1.25 - 0.035), (1, 1, 1))
            c.paint(c.ellipse(cx, cy, 0.05, 0.09), INK)
            continue
        if expression == "focused":
            ry *= 0.6
        dx = 0.045 * side if expression == "side" else 0.0
        if style == 1:     # renkli göz bebeği
            c.paint(c.ellipse(cx + dx, cy, rx, ry), INK)
            c.paint(c.ellipse(cx + dx, cy - 0.01, rx * 0.72, ry * 0.72), (0.45, 0.28, 0.16))
            c.paint(c.ellipse(cx + dx, cy - 0.01, rx * 0.40, ry * 0.40), INK)
        else:
            c.paint(c.ellipse(cx + dx, cy, rx, ry), INK)
        # Parlama.
        c.paint(c.ellipse(cx + dx + rx * 0.35 / (256 / 128), cy + ry * 0.35, rx * 0.30, ry * 0.25), (1, 1, 1))
        if style == 4:
            c.paint(c.ellipse(cx + dx - rx * 0.25 / 2, cy - ry * 0.40, rx * 0.15, ry * 0.12), (1, 1, 1))
        if style == 2:     # kirpik
            c.paint(c.segment(cx + side * 0.06, cy + ry * 0.75, cx + side * 0.09, cy + ry * 1.10, 0.035), INK)
        if style == 3 and expression != "focused":   # sakin: üst kapak
            c.paint(c.segment(cx - 0.075, cy + ry * 0.50, cx + 0.075, cy + ry * 0.50, 0.06), INK)
        if style == 5 or expression == "worried":     # kaş
            tilt = 0.05 if expression == "worried" else 0.0
            c.paint(c.segment(cx - 0.07, cy + 0.40 - tilt * side, cx + 0.07, cy + 0.40 + tilt * side, 0.05), INK)
    return c.rgba


# ---------------------------------------------------------------- ağız (128 x 128, ortada)
MOUTH_EXPRESSIONS = ["smile", "open", "laugh", "frown", "worried", "scared", "flat", "o", "wow"]


def mouth_texture(expression):
    c = Canvas(128, 128)
    cx, cy = 0.5, 0.55
    if expression == "smile":
        c.paint(c.arc(cx, cy + 0.06, 0.16, 0.12, math.pi * 1.15, math.pi * 1.85, 0.05), INK)
    elif expression in ("open", "laugh"):
        h = 0.12 if expression == "open" else 0.20
        d = np.maximum(c.ellipse(cx, cy, 0.18, h), c.y - cy - 0.0)   # yarım elips (üst düz)
        c.paint(d - 0.025, INK)
        c.paint(d, MOUTH_IN)
        c.paint(np.maximum(c.ellipse(cx, cy - h * 0.75, 0.10, h * 0.45), d), TONGUE)
    elif expression == "frown":
        c.paint(c.arc(cx, cy - 0.10, 0.15, 0.10, math.pi * 0.2, math.pi * 0.8, 0.05), INK)
    elif expression == "worried":
        pts = [(cx - 0.14 + 0.07 * i, cy + (0.02 if i % 2 else -0.02)) for i in range(5)]
        c.paint(c.polyline(pts, 0.045), INK)
    elif expression == "scared":
        d = c.ellipse(cx, cy, 0.10, 0.13)
        c.paint(d - 0.025, INK); c.paint(d, MOUTH_IN)
    elif expression == "flat":
        c.paint(c.segment(cx - 0.08, cy, cx + 0.08, cy, 0.045), INK)
    elif expression in ("o", "wow"):
        r = 0.05 if expression == "o" else 0.075
        d = c.ellipse(cx, cy, r, r * 1.25)
        c.paint(d - 0.022, INK); c.paint(d, MOUTH_IN)
    return c.rgba


def blush_texture():
    c = Canvas(256, 64)
    for cx in (0.24, 0.76):
        d = c.ellipse(cx, 0.60, 0.075, 0.20)
        c.paint(d, (1.0, 0.55, 0.55), alpha=0.55)
    return c.rgba


# ---------------------------------------------------------------- saç ve desenler (gri; renk ton ile çarpılır)
def hair_texture():
    c = Canvas(128, 128)
    u, v = c.x, c.y
    strands = 0.86 + 0.05 * np.sin(u * 2 * math.pi * 10 + 1.2 * np.sin(v * 5)) + 0.03 * np.sin(u * 2 * math.pi * 23)
    shine = 0.14 * np.exp(-((v - 0.74) / 0.07) ** 2) * (0.7 + 0.3 * np.sin(u * 2 * math.pi * 10))
    g = np.clip(strands + shine, 0, 1)
    c.rgba[..., :3] = g[..., None]
    c.rgba[..., 3] = 1
    return c.rgba


PATTERNS = ["plain", "stripes", "dots", "plaid", "check", "hearts"]


def pattern_texture(name):
    c = Canvas(128, 128)
    u, v = c.x, c.y
    g = np.ones_like(u)
    if name == "stripes":
        g = np.where((v * 4) % 1 < 0.5, 1.0, 0.72)
    elif name == "dots":
        d = np.hypot((u * 4) % 1 - 0.5, (v * 4 + 0.5 * np.floor(u * 4)) % 1 - 0.5)
        g = np.where(d < 0.18, 1.0, 0.78) + 0 * u
        g = 0.78 + 0.22 * np.clip((0.2 - d) / 0.03, 0, 1)
    elif name == "plaid":
        a = np.abs(((u * 2) % 1) - 0.5) < 0.12
        b = np.abs(((v * 2) % 1) - 0.5) < 0.12
        g = 1.0 - 0.18 * a - 0.18 * b - 0.06 * (np.abs(((u * 8) % 1) - 0.5) < 0.06)
    elif name == "check":
        g = np.where((np.floor(u * 4) + np.floor(v * 4)) % 2 == 0, 1.0, 0.74)
    elif name == "hearts":
        # Küçük kalpler: iki daire + üçgen yaklaşık.
        cu, cv = (u * 3) % 1 - 0.5, (v * 3) % 1 - 0.5
        d = np.minimum(np.hypot(cu - 0.09, cv - 0.05), np.hypot(cu + 0.09, cv - 0.05)) - 0.11
        tri = np.maximum(np.abs(cu) * 1.1 + cv * 0.9 - 0.11, -cv - 0.25)
        heart = np.minimum(d, tri)
        g = 1.0 - 0.25 * np.clip(-heart / 0.02, 0, 1)
    c.rgba[..., :3] = g[..., None]
    c.rgba[..., 3] = 1
    return c.rgba


def shoe_texture():
    """Ayakkabı: üst kısım (beyaz = ton), taban bandı açık gri, bağcık çizgileri."""
    c = Canvas(128, 64)
    g = np.ones_like(c.x)
    g = np.where(c.y < 0.28, 0.55, g)   # taban (koyu: tonla çarpılınca koyu ton)
    laces = (np.abs(((c.x * 6) % 1) - 0.5) < 0.08) & (c.y > 0.55) & (np.abs(c.x - 0.5) < 0.2)
    g = np.where(laces, 0.85, g)
    c.rgba[..., :3] = g[..., None]
    c.rgba[..., 3] = 1
    return c.rgba


def knit_texture():
    """Bere örgüsü: dikey sıra sıra V'ler."""
    c = Canvas(128, 128)
    u, v = c.x, c.y
    col = (u * 16) % 1
    row = (v * 12 + np.abs(col - 0.5) * 1.2) % 1
    g = 0.80 + 0.20 * np.clip(np.sin(row * math.pi), 0, 1) - 0.10 * (np.abs(col - 0.5) > 0.44)
    c.rgba[..., :3] = g[..., None]
    c.rgba[..., 3] = 1
    return c.rgba
