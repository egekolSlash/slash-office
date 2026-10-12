# Tasarım dokusu çizicisi. Her piksel için bölge (gövde, kol, bacak) ve metre cinsinden konum (X: ön ortadan çevre
# boyunca, karakterin solu +; Y: dünya yüksekliği, kolda omuzdan uzaklık) bulunur; desenler ve motifler bu
# koordinatlarda uzaklık alanı (sdf < 0 içeride) olarak çizilir.
# Çıktı: maske (R: ikinci renk, G: gölge, B: 0, A: 1) ve ayrıntı (önceden çarpılmamış RGBA; sabit renkler).
import math

import numpy as np

PX = 0.0035   # kenar yumuşatma (m)


class Painter:
    def __init__(self, layout, size=256, swatches=None):
        self.n = size
        h = w = size
        ys, xs = np.mgrid[0:h, 0:w]
        u = (xs + 0.5) / w
        v = 1 - (ys + 0.5) / h
        self.u, self.v = u, v
        self.X = np.zeros((h, w))
        self.Y = np.zeros((h, w))
        self.kind = np.full((h, w), "", dtype=object)
        for kind, u0, u1, v0, v1, y0, y1, circ in layout.regions:
            inside = (u >= u0) & (u < u1) & (v >= v0) & (v < v1)
            t = (v - v0) / (v1 - v0)
            Y = y0 + (y1 - y0) * t
            if kind == "body":
                C = np.vectorize(circ)(Y)
                X = (u - (u0 + u1) / 2) / (u1 - u0) * C
            else:
                C = circ(0)
                X = (u - (u0 + u1) / 2) / (u1 - u0) * C
            self.X = np.where(inside, X, self.X)
            self.Y = np.where(inside, Y, self.Y)
            self.kind = np.where(inside, kind, self.kind)
        self.layout = layout
        self.body = self.kind == "body"
        self.sleeves = (self.kind == "sleeveL") | (self.kind == "sleeveR")
        self.legs = (self.kind == "legL") | (self.kind == "legR")
        self.mask = np.zeros((h, w))       # ikinci renk kapsamı
        self.shade = np.ones((h, w))
        self.detail = np.zeros((h, w, 4))  # önceden çarpılmış
        self.swatches = dict(swatches or {})

    # ------------------------------------------------------------ kapsama
    @staticmethod
    def cov(sdf, px=PX):
        return np.clip(0.5 - sdf / px, 0, 1)

    def where(self, region):
        return {"body": self.body, "sleeves": self.sleeves, "legs": self.legs, "all": self.kind != ""}[region] \
            if isinstance(region, str) else region

    def second(self, sdf=None, region="all", amount=1.0):
        """İkinci renk: sdf içi (ya da bütün bölge)."""
        c = (np.ones_like(self.X) if sdf is None else self.cov(sdf)) * self.where(region) * amount
        self.mask = np.maximum(self.mask, c) if amount >= 0 else self.mask
        return self

    def first(self, sdf=None, region="all"):
        """Birinci renge geri çevir (ikinci rengin üstüne)."""
        c = (np.ones_like(self.X) if sdf is None else self.cov(sdf)) * self.where(region)
        self.mask = self.mask * (1 - c)
        return self

    def dark(self, sdf, value=0.82, region="all"):
        c = self.cov(sdf) * self.where(region)
        self.shade = self.shade * (1 - c) + np.minimum(self.shade, value) * c
        return self

    def paint(self, sdf, color, alpha=1.0, region="all"):
        """Sabit renk (ayrıntı katmanı)."""
        a = (self.cov(sdf) if sdf is not None else np.ones_like(self.X)) * self.where(region) * alpha
        col = np.asarray(color, float)
        self.detail[..., :3] = self.detail[..., :3] * (1 - a[..., None]) + col * a[..., None]
        self.detail[..., 3] = a + self.detail[..., 3] * (1 - a)
        return self

    def image_mask(self, img, cx, cy, width, height, region="body"):
        """Gri tonlu bir görüntüyü (0..1, satır 0 üst) gövdede (cx, cy) merkezli, width x height metrelik alana yerleştirir;
        kapsama döner."""
        h, w = img.shape
        fx = (self.X - (cx - width / 2)) / width
        fy = 1 - (self.Y - (cy - height / 2)) / height
        inside = (fx >= 0) & (fx < 1) & (fy >= 0) & (fy < 1) & self.where(region)
        ix = np.clip((fx * w).astype(int), 0, w - 1)
        iy = np.clip((fy * h).astype(int), 0, h - 1)
        return np.where(inside, img[iy, ix], 0.0)

    def text(self, s, cx, cy, height, color=None, second=False, font="/System/Library/Fonts/Supplemental/Arial Black.ttf",
             outline=None, region="body", stretch=1.0):
        """Yazı (PIL ile çizilip yerleştirilir): renkli (ayrıntı) ya da ikinci renk."""
        from PIL import Image, ImageDraw, ImageFont
        try:
            f = ImageFont.truetype(font, 200)
        except OSError:
            f = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 200)
        box = f.getbbox(s)
        w, h = box[2] - box[0] + 40, box[3] - box[1] + 40
        im = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(im)
        d.text((20 - box[0], 20 - box[1]), s, fill=255, font=f, stroke_width=0)
        arr = np.asarray(im, float) / 255
        width = height * w / h * stretch
        if outline is not None:
            im2 = Image.new("L", (w, h), 0)
            ImageDraw.Draw(im2).text((20 - box[0], 20 - box[1]), s, fill=255, font=f, stroke_width=14)
            o = self.image_mask(np.asarray(im2, float) / 255, cx, cy, width, height, region)
            self._apply(o, outline)
        c = self.image_mask(arr, cx, cy, width, height, region)
        if second:
            self.mask = np.maximum(self.mask, c)
        else:
            self._apply(c, color)
        return self

    def _apply(self, a, color):
        col = np.asarray(color, float)
        self.detail[..., :3] = self.detail[..., :3] * (1 - a[..., None]) + col * a[..., None]
        self.detail[..., 3] = a + self.detail[..., 3] * (1 - a)

    # ------------------------------------------------------------ çıktı
    def images(self, swatch_colors):
        """(maske, ayrıntı) RGBA dizileri; renk örnekleri satırı (yaka vb.) da yazılır."""
        from garments import SWATCH_U, SWATCH_V
        mask = np.zeros((self.n, self.n, 4))
        mask[..., 0] = self.mask
        mask[..., 1] = self.shade
        mask[..., 3] = 1
        detail = self.detail.copy()
        # Önceden çarpılmamış (PNG): renk / alfa.
        a = detail[..., 3:4]
        detail[..., :3] = np.where(a > 1e-4, detail[..., :3] / np.maximum(a, 1e-4), 0)
        for name, spec in swatch_colors.items():
            u = SWATCH_U[name]
            sel = (np.abs(self.u - u) < 0.025) & (np.abs(self.v - SWATCH_V) < 0.012)
            kind, color = spec
            if kind == "second":
                mask[..., 0] = np.where(sel, 1.0, mask[..., 0])
            elif kind == "first":
                mask[..., 0] = np.where(sel, 0.0, mask[..., 0])
            else:
                detail[sel] = (*color, 1.0)
            mask[..., 1] = np.where(sel, 1.0, mask[..., 1])
        return mask, detail


# ---------------------------------------------------------------- şekiller (koordinat dizileri → sdf)
def circle(x, y, cx, cy, r):
    return np.hypot(x - cx, y - cy) - r


def ellipse(x, y, cx, cy, rx, ry, angle=0.0):
    ca, sa = np.cos(angle), np.sin(angle)
    dx, dy = x - cx, y - cy
    px, py = dx * ca + dy * sa, -dx * sa + dy * ca
    return (np.hypot(px / rx, py / ry) - 1) * min(rx, ry)


def rect(x, y, x0, x1, y0, y1, r=0.0):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = np.abs(x - cx) - hx, np.abs(y - cy) - hy
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def segment(x, y, ax, ay, bx, by, w):
    dx, dy = bx - ax, by - ay
    t = np.clip(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy + 1e-12), 0, 1)
    return np.hypot(x - ax - t * dx, y - ay - t * dy) - w / 2


def polygon(x, y, pts):
    """Dışbükey ya da değil, kapalı çokgen (çift-tek kuralı ile işaret)."""
    d = np.full(x.shape, 1e9)
    inside = np.zeros(x.shape, bool)
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        d = np.minimum(d, segment(x, y, ax, ay, bx, by, 0))
        cond = ((ay > y) != (by > y)) & (x < (bx - ax) * (y - ay) / (by - ay + 1e-12) + ax)
        inside ^= cond
    return np.where(inside, -d, d)


def star(x, y, cx, cy, r, points=5, inner=0.45, rot=0.0):
    pts = []
    for k in range(points * 2):
        rr = r if k % 2 == 0 else r * inner
        a = rot + math.pi / 2 + math.pi * k / points
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return polygon(x, y, pts)


def heart(x, y, cx, cy, r):
    a = circle(x, y, cx - r * 0.5, cy + r * 0.25, r * 0.55)
    b = circle(x, y, cx + r * 0.5, cy + r * 0.25, r * 0.55)
    tri = polygon(x, y, [(cx - r * 1.02, cy + r * 0.12), (cx + r * 1.02, cy + r * 0.12), (cx, cy - r * 1.05)])
    return np.minimum(np.minimum(a, b), tri)


def leaf(x, y, cx, cy, length, width, angle=0.0):
    return ellipse(x, y, cx, cy, length / 2, width / 2, angle)


def flower(x, y, cx, cy, r, petals=5):
    d = np.full(x.shape, 1e9)
    for k in range(petals):
        a = 2 * math.pi * k / petals
        d = np.minimum(d, circle(x, y, cx + r * 0.55 * math.cos(a), cy + r * 0.55 * math.sin(a), r * 0.45))
    return d


def diamond(x, y, cx, cy, rx, ry):
    return (np.abs(x - cx) / rx + np.abs(y - cy) / ry - 1) * min(rx, ry) * 0.7


def union(*ds):
    out = ds[0]
    for d in ds[1:]:
        out = np.minimum(out, d)
    return out


def subtract(a, b):
    return np.maximum(a, -b)


# ---------------------------------------------------------------- tekrarlar
def tile(x, y, px, py, fn, stagger=0.5, jitter=0.0, seed=0):
    """Desen döşemesi: her hücrede fn(lx, ly, i, j) (hücre merkezine göre yerel koordinatlar)."""
    j = np.floor(y / py)
    xs = x + j * px * stagger
    i = np.floor(xs / px)
    lx = xs - (i + 0.5) * px
    ly = y - (j + 0.5) * py
    return fn(lx, ly, i, j)


def stripes(t, period, width, phase=0.0):
    """Çizgiler (t yönünde): sdf."""
    k = np.mod(t / period + phase, 1.0) * period
    return np.abs(k - period / 2) - width / 2


def checks(x, y, size):
    a = np.floor(x / size) + np.floor(y / size)
    return np.where(np.mod(a, 2) == 0, -1.0, 1.0) * 0.01


def zigzag(x, y, period, amp, width, phase=0.0):
    k = np.mod(x / period + phase, 1.0)
    tri = (np.abs(k - 0.5) * 2 - 0.5) * 2 * amp
    return stripes(y - tri, period * 1.0, width)


def waves(x, y, period, amp, width, wavelength):
    return stripes(y - amp * np.sin(2 * math.pi * x / wavelength), period, width)
