# Gardırop tasarımları: her biri bir kalıp (+ kol boyu), iki varsayılan renk (kullanıcı değiştirebilir), sabit renkli
# ayrıntılar ve kendi çizdiğimiz motifler. Referans katalogdaki her parçaya bir karşılık; logolar, markalar ve başka
# yapımların karakterleri yerine genel motifler.
import math

import numpy as np
from painter import (checks, circle, diamond, ellipse, flower, heart, leaf, polygon, rect, segment, star, stripes,
                     subtract, tile, union, waves, zigzag)


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255 for i in (0, 2, 4))


WHITE, BLACK, GOLD, CREAM = hx("ffffff"), hx("222222"), hx("e8b84a"), hx("f6efdc")
TOPS, BOTTOMS, SHOES = [], [], []


def top(id, kind, sleeve, en, tr, c1, c2, **kw):
    def reg(fn):
        TOPS.append(dict(id=id, kind=kind, sleeve=sleeve, en=en, tr=tr, colors=(hx(c1), hx(c2)), paint=fn, **kw))
        return fn
    return reg


def bottom(id, kind, en, tr, c1, c2, **kw):
    def reg(fn):
        BOTTOMS.append(dict(id=id, kind=kind, en=en, tr=tr, colors=(hx(c1), hx(c2)), paint=fn, **kw))
        return fn
    return reg


def shoe(id, kind, en, tr, c1, c2, sole="f2f0ea", **kw):
    def reg(fn):
        SHOES.append(dict(id=id, kind=kind, en=en, tr=tr, colors=(hx(c1), hx(c2)), sole=hx(sole), paint=fn, **kw))
        return fn
    return reg


# ---------------------------------------------------------------- yardımcılar
def hem_band(p, h, color=None, region="body"):
    d = p.Y - (p.layout.hem + h)
    if color is None:
        p.second(d, region)
    else:
        p.paint(d, color, region=region)


def cuffs(p, w, color=None):
    d = (p.layout.sleeve - w) - p.Y
    if color is None:
        p.second(d, "sleeves")
    else:
        p.paint(d, color, region="sleeves")


def neck_band(p, h=0.018, color=None):
    d = (0.605 - h) - p.Y
    if color is None:
        p.second(d, "body")
    else:
        p.paint(d, color, region="body")


def buttons(p, ys, color, x=0.0, r=0.0075):
    for y in ys:
        p.paint(circle(p.X, p.Y, x, y, r), color, region="body")


def vneck(p, depth, color, w=0.05):
    tri = polygon(p.X, p.Y, [(-w, 0.62), (w, 0.62), (0, 0.62 - depth)])
    p.paint(tri, color, region="body")


def collar_flaps(p, color, w=0.045, depth=0.04):
    for s in (-1, 1):
        p.paint(polygon(p.X, p.Y, [(0, 0.585), (s * w, 0.612), (s * w * 1.1, 0.575)]), color, region="body")
    p.paint(segment(p.X, p.Y, 0, 0.58, 0, 0.58 - depth, 0.004), color, region="body")


def belt(p, y, h, color=None, buckle=None):
    d = np.abs(p.Y - y) - h / 2
    if color is None:
        p.second(d, "body")
    else:
        p.paint(d, color, region="body")
    if buckle:
        p.paint(rect(p.X, p.Y, -0.014, 0.014, y - h / 2 - 0.002, y + h / 2 + 0.002, 0.002), buckle, region="body")


def pocket(p, x, y, w, h, color=None, second=False):
    d = rect(p.X, p.Y, x - w / 2, x + w / 2, y - h / 2, y + h / 2, 0.004)
    if second:
        p.second(d, "body")
    elif color is not None:
        p.paint(d, color, region="body")
    p.dark(np.abs(d) - 0.0012, 0.8, "body")


def allover(p, sdf, region="all", color=None):
    if color is None:
        p.second(sdf, region)
    else:
        p.paint(sdf, color, region=region)


def skirt_folds(p, n=10, depth=0.9):
    """Etek kıvrımları: dikey yumuşak gölge."""
    below = p.Y < 0.40
    t = np.cos(2 * math.pi * n * p.u) * 0.5 + 0.5
    k = np.clip((0.40 - p.Y) / 0.15, 0, 1)
    p.shade = np.where(p.body & below, p.shade * (1 - (1 - depth) * t * k), p.shade)


def legs_second(p):
    p.second(None, "legs")


def overall_bib(p, color=None, strap=0.016):
    """Salopet: göğüs önlüğü + askılar (bacaklar ve bel altı ikinci renk)."""
    bib = union(rect(p.X, p.Y, -0.055, 0.055, 0.36, 0.50, 0.006), p.Y - 0.37)
    straps = union(segment(p.X, p.Y, -0.045, 0.50, -0.06, 0.62, strap), segment(p.X, p.Y, 0.045, 0.50, 0.06, 0.62, strap))
    back = np.where(np.abs(p.X) > 0.18, segment(p.X, p.Y, p.X, 0.45, p.X, 0.62, 0.0) + 1, 1.0)
    d = union(bib, straps)
    if color is None:
        p.second(d, "body")
        p.second(None, "legs")
    else:
        p.paint(d, color, region="body")
        p.paint(None, color, region="legs")
    return back


# ================================================================ ÜSTLER: mayo ve dalgıç
@top("wetsuit.reef", "wetsuit", "L", "Reef Wetsuit", "Resif Dalgıç Kıyafeti", "1f2a2e", "1a9a86")
def _(p):
    side = np.abs(np.abs(p.X) - 0.20) - 0.035
    p.second(side, "body"); p.second(np.abs(p.X - 0.0) - 0.012, "sleeves")
    p.second(np.abs(np.abs(p.X) - 0.05) - 0.012, "legs")
    p.paint(circle(p.X, p.Y, 0, 0.50, 0.022), hx("1a9a86"), region="body")
    p.paint(leaf(p.X, p.Y, 0, 0.50, 0.026, 0.014, 0.6), hx("1f2a2e"), region="body")


@top("rashguard.palm", "rashguard", "L", "Palm Rash Guard", "Palmiye Sörf Tişörtü", "2c7fb8", "8fdccd",
     legs_to=0.24)
def _(p):
    def palm(lx, ly, i, j):
        a = 0.5 * np.sin(i * 1.7 + j)
        return union(leaf(lx, ly, 0, 0, 0.07, 0.022, a), leaf(lx, ly, 0.02, 0.01, 0.06, 0.018, a + 1.2))
    allover(p, tile(p.X, p.Y, 0.08, 0.07, palm), region=p.body | p.sleeves)
    p.paint(None, hx("1d2b33"), region="legs")
    p.paint(np.abs(p.Y - 0.12) - 0.004, hx("55c7c0"), region="legs")


@top("swimsuit.sailor", "swimsuit", "N", "Sailor Swimsuit", "Denizci Mayo", "ffffff", "d8333a", legs_to=0.28)
def _(p):
    allover(p, stripes(p.Y, 0.05, 0.025), region=p.body | p.legs)
    p.paint(union(segment(p.X, p.Y, 0, 0.53, 0, 0.47, 0.006), segment(p.X, p.Y, -0.015, 0.495, 0.015, 0.495, 0.005),
                  subtract(circle(p.X, p.Y, 0, 0.475, 0.016), circle(p.X, p.Y, 0, 0.482, 0.012))), hx("1f3c88"), region="body")


# ================================================================ A kesim elbise
@top("aline.cafe", "aline", "H", "Café Dress", "Kafe Elbisesi", "e8607a", "ffffff")
def _(p):
    apron = rect(p.X, p.Y, -0.08, 0.08, 0.15, 0.45, 0.01)
    p.second(subtract(apron, np.abs(np.mod(p.X, 0.03) - 0.015) - 0.006), "body")
    p.second(p.Y - 0.59, "body") if False else None
    p.paint(rect(p.X, p.Y, -0.05, 0.05, 0.45, 0.53, 0.008), WHITE, region="body")
    cuffs(p, 0.025, WHITE)
    hem_band(p, 0.02, hx("c94862"))
    skirt_folds(p)


@top("aline.folk", "aline", "H", "Folk Dress", "Halk Elbisesi", "b8322b", "e98a3c")
def _(p):
    def motif(lx, ly, i, j):
        return union(diamond(lx, ly, 0, 0, 0.012, 0.016), rect(lx, ly, -0.016, 0.016, -0.002, 0.002))
    allover(p, tile(p.X, p.Y, 0.04, 0.045, motif), region=p.body)
    allover(p, tile(p.X, p.Y, 0.03, 0.03, motif), region=p.sleeves)
    hem_band(p, 0.015, hx("f2c14e"))
    skirt_folds(p)


@top("aline.bolero", "aline", "L", "Bolero Dress", "Bolerolu Elbise", "e6a6e9", "ffffff")
def _(p):
    # Bolero: omuzlar ve kollar beyaz kısa ceket; önü açık.
    p.second(None, "sleeves")
    p.second(np.maximum(0.48 - p.Y, 0.05 - np.abs(p.X)), "body")
    p.paint(np.abs(p.Y - 0.405) - 0.006, hx("c77ccc"), region="body")
    skirt_folds(p)


@top("aline.tartan", "aline", "L", "Tartan Dress", "Tartan Elbise", "f2c230", "2f7d3a")
def _(p):
    a = stripes(p.X, 0.07, 0.016)
    b = stripes(p.Y, 0.07, 0.016)
    allover(p, np.minimum(a, b))
    p.paint(np.minimum(stripes(p.X, 0.07, 0.005, 0.5), stripes(p.Y, 0.07, 0.005, 0.5)), hx("c63a2c"))
    p.paint(np.abs(p.Y - 0.60) - 0.012, WHITE, region="body")
    skirt_folds(p)


@top("aline.apple", "aline", "N", "Apple Dress", "Elma Elbise", "f4eeb0", "d6363a")
def _(p):
    hem_band(p, 0.03)
    p.paint(circle(p.X, p.Y, 0, 0.47, 0.045), hx("f8f3dc"), region="body")
    p.paint(np.abs(circle(p.X, p.Y, 0, 0.47, 0.045)) - 0.004, hx("d6363a"), region="body")
    for s in (-1, 1):
        p.paint(ellipse(p.X, p.Y, s * 0.012, 0.475, 0.006, 0.011, 0.3 * s), hx("4b2a1a"), region="body")
    skirt_folds(p)


@top("aline.harlequin", "aline", "N", "Harlequin Dress", "Arlekin Elbise", "f26fb0", "f7e05a")
def _(p):
    def cell(lx, ly, i, j):
        return diamond(lx, ly, 0, 0, 0.025, 0.035)
    d = tile(p.X, p.Y, 0.05, 0.07, cell)
    alt = tile(p.X, p.Y, 0.05, 0.07, lambda lx, ly, i, j: np.where(np.mod(i + j, 2) == 0, -1.0, 1.0) * 0.01)
    p.second(np.maximum(d, alt))
    p.paint(np.maximum(d, -alt), hx("8b6fe8"), alpha=0.9)
    skirt_folds(p)


# ================================================================ uzun A kesim
@top("along.buttercup", "along", "H", "Buttercup Dress", "Düğünçiçeği Elbise", "f3d23d", "ffffff")
def _(p):
    def fl(lx, ly, i, j):
        return flower(lx, ly, 0, 0, 0.011, 5)
    allover(p, tile(p.X, p.Y, 0.04, 0.04, fl))
    p.paint(tile(p.X, p.Y, 0.04, 0.04, lambda lx, ly, i, j: circle(lx, ly, 0, 0, 0.003)), hx("e08a1e"))
    p.paint(segment(p.X, p.Y, -0.06, 0.60, 0.05, 0.42, 0.006), hx("d9b21c"), region="body")
    skirt_folds(p)


@top("along.maple", "along", "H", "Maple Dress", "Akçaağaç Elbise", "ffffff", "b52d2b")
def _(p):
    p.second(p.Y - 0.39, "body")
    p.paint(star(p.X, p.Y, 0.03, 0.50, 0.025, 5, 0.5), hx("e4823a"), region="body")
    def m(lx, ly, i, j):
        return star(lx, ly, 0, 0, 0.012, 5, 0.5, 0.3)
    p.paint(np.maximum(tile(p.X, p.Y, 0.05, 0.05, m), p.Y - 0.38), hx("e05a3a"), region="body")
    hem_band(p, 0.012, hx("6b1612"))
    skirt_folds(p)


@top("along.evening", "along", "L", "Evening Dress", "Gece Elbisesi", "2b3566", "151515")
def _(p):
    p.second(None, "sleeves")
    p.second(np.abs(p.Y - 0.405) - 0.008, "body")
    p.paint(np.abs(p.Y - 0.6) - 0.005, hx("c9b27a"), region="body")
    skirt_folds(p, 12)


@top("along.witch", "along", "L", "Witch Dress", "Cadı Elbisesi", "1b1b1f", "4b2b7a")
def _(p):
    p.second(np.maximum(np.abs(p.X) - (0.03 + (0.40 - p.Y) * 0.3), p.Y - 0.40), "body")
    p.paint(polygon(p.X, p.Y, [(-0.04, 0.615), (0.04, 0.615), (0, 0.565)]), hx("2a2a30"), region="body")
    skirt_folds(p, 12)


@top("along.zigzag", "along", "N", "Zigzag Dress", "Zikzak Elbise", "7a3fb8", "45c1d6")
def _(p):
    allover(p, zigzag(p.X, p.Y, 0.05, 0.012, 0.012))
    p.paint(zigzag(p.X, p.Y + 0.025, 0.05, 0.012, 0.006), hx("f47db4"))
    skirt_folds(p, 10)


@top("along.candy", "along", "N", "Candy Stripe Dress", "Şeker Çizgili Elbise", "ffffff", "e35a5a")
def _(p):
    k = np.mod(np.floor(p.X / 0.02), 4)
    p.second(np.where(k == 0, -1.0, 1.0) * 0.01)
    p.paint(np.where(k == 2, -1.0, 1.0) * 0.01, hx("4f8ad6"))
    skirt_folds(p, 10)


# ================================================================ balon etek
@top("balloon.cloud", "balloon", "H", "Cloud Dress", "Bulut Elbise", "cfe8f3", "ffffff")
def _(p):
    cuffs(p, 0.02)
    p.second(np.abs(p.Y - 0.405) - 0.006, "body")
    p.dark(np.abs(p.Y - 0.17) - 0.004, 0.9, "body")
    skirt_folds(p, 8, 0.85)


@top("balloon.dream", "balloon", "H", "Dreamy Dress", "Rüya Elbisesi", "f6b7d9", "c9a3f2")
def _(p):
    for k, (x, y, c) in enumerate([(-0.06, 0.26, "f7d64a"), (0.05, 0.22, "8fd7f2"), (0.09, 0.31, "f7d64a"), (-0.1, 0.33, "a6e3a1"),
                                   (0.0, 0.50, "f7d64a"), (0.13, 0.24, "f49ac1"), (-0.15, 0.22, "8fd7f2")]):
        p.paint(star(p.X, p.Y, x, y, 0.022 if k == 4 else 0.014, 5, 0.5), hx(c), region="body")
    p.second(None, "sleeves")
    hem_band(p, 0.03)
    skirt_folds(p, 8, 0.85)


@top("balloon.gothic", "balloon", "L", "Gothic Dress", "Gotik Elbise", "6c3d93", "1d1424")
def _(p):
    p.second(rect(p.X, p.Y, -0.035, 0.035, 0.40, 0.56), "body")
    for y in np.arange(0.42, 0.56, 0.018):
        p.paint(segment(p.X, p.Y, -0.03, y, 0.03, y + 0.009, 0.003), hx("c7a6e8"), region="body")
    hem_band(p, 0.025)
    cuffs(p, 0.03)
    skirt_folds(p, 8, 0.8)


@top("balloon.lolita", "balloon", "L", "Frilly Dress", "Fırfırlı Elbise", "f6a9cc", "ffffff")
def _(p):
    for y in (0.20, 0.26):
        p.second(np.abs(p.Y - y) - 0.01, "body")
        p.paint(stripes(p.X, 0.012, 0.004), hx("f6a9cc"), region=p.body & (np.abs(p.Y - y) < 0.004))
    p.second(rect(p.X, p.Y, -0.04, 0.04, 0.42, 0.56), "body")
    p.paint(heart(p.X, p.Y, 0, 0.58, 0.016), hx("e2508e"), region="body")
    cuffs(p, 0.02)
    skirt_folds(p, 8, 0.85)


@top("balloon.tutu", "balloon", "N", "Tutu Dress", "Tütü Elbise", "f2627a", "f9b1a9")
def _(p):
    p.second(np.maximum(p.Y - 0.36, 0.20 - p.Y), "body")
    p.second(waves(p.X, p.Y, 0.08, 0.008, 0.01, 0.06), p.body & (p.Y < 0.2))
    p.paint(flower(p.X, p.Y, 0, 0.50, 0.018, 6), hx("ffd36b"), region="body")
    skirt_folds(p, 8, 0.85)


@top("balloon.sunflower", "balloon", "N", "Sunflower Dress", "Ayçiçeği Elbise", "f8f1d4", "f2b72f")
def _(p):
    def sf(lx, ly, i, j):
        return flower(lx, ly, 0, 0, 0.022, 10)
    allover(p, tile(p.X, p.Y, 0.065, 0.065, sf))
    p.paint(tile(p.X, p.Y, 0.065, 0.065, lambda lx, ly, i, j: circle(lx, ly, 0, 0, 0.009)), hx("7a4a1a"))
    skirt_folds(p, 8, 0.85)


@top("balloon.moss", "balloon", "H", "Moss Dress", "Yosun Elbise", "3f8c46", "1f5a2c")
def _(p):
    p.second(waves(p.X, p.Y, 0.07, 0.01, 0.02, 0.09), p.body & (p.Y < 0.38))
    cuffs(p, 0.02)
    p.paint(np.abs(p.Y - 0.405) - 0.007, hx("2a6a33"), region="body")
    skirt_folds(p, 8, 0.85)


# ================================================================ düz uzun (kolon)
@top("column.saree", "column", "H", "Drape Dress", "Drapeli Elbise", "a72424", "e3b24a")
def _(p):
    drape = segment(p.X, p.Y, -0.12, 0.60, 0.12, 0.20, 0.06)
    p.second(np.abs(drape) - 0.006, "body")
    allover(p, tile(p.X, p.Y, 0.035, 0.05, lambda lx, ly, i, j: diamond(lx, ly, 0, 0, 0.004, 0.007)), region=p.body, color=hx("e3b24a"))
    hem_band(p, 0.02)
    cuffs(p, 0.015)


@top("column.toga", "column", "H", "Toga", "Toga", "eef0f2", "b42b2b")
def _(p):
    p.second(np.abs(segment(p.X, p.Y, -0.07, 0.62, 0.11, 0.05, 0.0)) - 0.035, "body")
    p.paint(np.abs(p.Y - 0.405) - 0.005, GOLD, region="body")
    skirt_folds(p, 6, 0.85)


@top("column.aodai", "column", "L", "Long Tunic Dress", "Uzun Tunik Elbise", "a9d3e0", "e8f4f8")
def _(p):
    def lv(lx, ly, i, j):
        return union(*[leaf(lx, ly, 0.012 * math.cos(a), 0.012 * math.sin(a), 0.024, 0.009, a) for a in (0.5, 1.6, 2.6)])
    allover(p, tile(p.X, p.Y, 0.08, 0.09, lv), color=hx("5f8fa4"))
    hem_band(p, 0.06)
    neck_band(p, 0.015)


@top("column.shirtdress", "column", "L", "Plaid Shirt Dress", "Ekoseli Gömlek Elbise", "8a5a2b", "e0a43a")
def _(p):
    a = stripes(p.X, 0.05, 0.012)
    b = stripes(p.Y, 0.05, 0.012)
    allover(p, np.minimum(a, b))
    p.paint(np.minimum(stripes(p.X, 0.05, 0.004, 0.5), stripes(p.Y, 0.05, 0.004, 0.5)), hx("3a2414"))
    buttons(p, np.arange(0.30, 0.60, 0.05), hx("f2e6c8"))
    collar_flaps(p, hx("6d4320"))


@top("column.slip", "column", "N", "Slip Dress", "Askılı Elbise", "28367a", "1c2552")
def _(p):
    p.second(np.abs(p.Y - 0.56) - 0.006, "body")
    skirt_folds(p, 6, 0.85)


# ================================================================ kutu
@top("box.jumper", "box", "H", "Denim Jumper Dress", "Kot Jile Elbise", "2f4f8f", "ffffff",
     sleeve_stripes=True)
def _(p):
    p.paint(np.minimum(np.abs(p.Y - 0.53) - 0.0 + 10, 1), WHITE, alpha=0.0)
    p.paint(np.maximum(p.Y - 0.62, 0.50 - p.Y) * (np.abs(p.X) > 0.08) + (np.abs(p.X) <= 0.08) * 1.0, WHITE, region="body")
    p.paint(stripes(p.Y, 0.03, 0.015), hx("d93a3a"), region=p.body & (p.Y > 0.50) & (np.abs(p.X) > 0.08))
    p.paint(None, WHITE, region="sleeves")
    p.paint(stripes(p.Y, 0.03, 0.015), hx("d93a3a"), region="sleeves")
    pocket(p, 0, 0.44, 0.06, 0.04, hx("3a5c9e"))
    p.dark(np.abs(stripes(p.X, 0.008, 0.002)) * 0 + np.abs(np.abs(p.X) - 0.085) - 0.0015, 0.75, "body")


@top("box.tee", "box", "H", "Whale Tee Dress", "Balinalı Tişört Elbise", "1d1d22", "ffffff")
def _(p):
    p.second(union(ellipse(p.X, p.Y, 0, 0.50, 0.04, 0.022), polygon(p.X, p.Y, [(0.03, 0.50), (0.065, 0.53), (0.065, 0.47)])), "body")
    p.paint(circle(p.X, p.Y, -0.022, 0.505, 0.004), hx("1d1d22"), region="body")
    p.text("SLASH", 0, 0.455, 0.018, second=True)


@top("box.attendant", "box", "L", "Attendant Uniform", "Görevli Üniforması", "1f2a55", "c8202f")
def _(p):
    vneck(p, 0.05, WHITE)
    p.paint(polygon(p.X, p.Y, [(-0.01, 0.585), (0.01, 0.585), (0.02, 0.56), (-0.02, 0.56)]), hx("c8202f"), region="body")
    buttons(p, (0.44, 0.48), GOLD, x=-0.02)
    buttons(p, (0.44, 0.48), GOLD, x=0.02)
    p.paint(rect(p.X, p.Y, 0.035, 0.06, 0.52, 0.528), GOLD, region="body")


@top("box.blazer", "box", "L", "Blazer Dress", "Blazer Elbise", "2a2f45", "3d4466")
def _(p):
    p.second(polygon(p.X, p.Y, [(-0.06, 0.61), (0.0, 0.47), (0.06, 0.61)]), "body")
    p.dark(segment(p.X, p.Y, 0, 0.47, 0, 0.17, 0.002), 0.75, "body")
    buttons(p, (0.42, 0.36), hx("1a1d2a"), x=0.006)
    pocket(p, 0.07, 0.30, 0.05, 0.03)
    p.paint(np.abs(p.X) - 0.05 + 0 * p.Y + 10, WHITE)


@top("box.towel", "box", "N", "Bath Towel Wrap", "Havlu Sargı", "e8a0e4", "f5d0f2")
def _(p):
    p.second(stripes(p.Y, 0.04, 0.006), "body")
    p.dark(segment(p.X, p.Y, 0.08, 0.56, 0.06, 0.30, 0.004), 0.82, "body")


@top("box.rose", "box", "N", "Rose Dress", "Gül Elbise", "8f1531", "c43a5a")
def _(p):
    def rose(lx, ly, i, j):
        return union(circle(lx, ly, 0, 0, 0.012), *[circle(lx, ly, 0.01 * math.cos(a), 0.01 * math.sin(a), 0.007) for a in np.linspace(0, 6, 5)])
    allover(p, tile(p.X, p.Y, 0.06, 0.06, rose))
    p.paint(tile(p.X, p.Y, 0.06, 0.06, lambda lx, ly, i, j: np.abs(circle(lx, ly, 0, 0, 0.006)) - 0.0015), hx("5a0a1e"))
    hem_band(p, 0.012, hx("e7a9b5"))


# ================================================================ abiye (balo)
@top("gown.dutch", "gown", "H", "Folk Gown", "Halk Balo Elbisesi", "1d1d1d", "f05a2a")
def _(p):
    p.second(np.maximum(p.Y - 0.36, 0.06 - p.Y), "body")
    p.paint(rect(p.X, p.Y, -0.05, 0.05, 0.42, 0.58, 0.004), hx("2e5aa8"), region="body")
    p.paint(tile(p.X, p.Y, 0.02, 0.02, lambda lx, ly, i, j: rect(lx, ly, -0.006, 0.006, -0.006, 0.006)), hx("f2c14e"),
            region=p.body & (np.abs(p.X) < 0.045) & (p.Y > 0.43) & (p.Y < 0.57))
    p.paint(stripes(p.X, 0.03, 0.008), hx("f2c14e"), region=p.body & (p.Y < 0.09))
    skirt_folds(p, 12, 0.85)


@top("gown.blossom", "gown", "H", "Blossom Gown", "Çiçek Balo Elbisesi", "f17ab6", "c94a8e")
def _(p):
    for s in (-1, 1):
        p.second(np.maximum(np.abs(p.X - s * 0.13) - (0.02 + (0.40 - p.Y) * 0.25), p.Y - 0.40), "body")
    p.second(np.abs(p.Y - 0.40) - 0.01, "body")
    p.paint(np.abs(p.Y - 0.05) - 0.012, hx("fbd3e8"), region="body")
    cuffs(p, 0.025, hx("fbd3e8"))
    skirt_folds(p, 12, 0.85)


@top("gown.mint", "gown", "L", "Mint Victorian Gown", "Nane Viktorya Elbisesi", "8fd3b4", "e8f6ee")
def _(p):
    p.second(np.maximum(np.abs(p.X) - (0.02 + (0.40 - p.Y) * 0.35), p.Y - 0.42), "body")
    for y in (0.08, 0.16, 0.24, 0.32):
        p.paint(np.abs(p.Y - y) - 0.004, hx("5ca88a"), region=p.body & (np.abs(p.X) < 0.02 + (0.40 - y) * 0.35))
    p.paint(np.abs(np.abs(p.X) - (0.02 + (0.40 - p.Y) * 0.35)) - 0.004, hx("3c8f6c"), region=p.body & (p.Y < 0.42))
    cuffs(p, 0.03)
    skirt_folds(p, 12, 0.85)


@top("gown.noir", "gown", "L", "Lace Noir Gown", "Dantelli Siyah Elbise", "1a1f33", "2f3655")
def _(p):
    for y in (0.08, 0.17, 0.26):
        p.second(waves(p.X, p.Y - y, 10, 0.006, 0.012, 0.03) + (np.abs(p.Y - y) > 0.02) * 1.0, "body")
    p.paint(np.abs(p.Y - 0.40) - 0.008, hx("101320"), region="body")
    cuffs(p, 0.025)
    skirt_folds(p, 12, 0.85)


@top("gown.sky", "gown", "L", "Sky Gown", "Gökyüzü Balo Elbisesi", "4f8de8", "9cc6f6")
def _(p):
    for s in (-1, 1):
        p.second(np.maximum(np.abs(p.X - s * 0.12) - (0.03 + (0.40 - p.Y) * 0.2), p.Y - 0.40), "body")
    p.second(np.maximum(p.Y - 0.08, 0.0 - p.Y), "body")
    p.paint(np.abs(p.Y - 0.6) - 0.008, WHITE, region="body")
    cuffs(p, 0.05)
    skirt_folds(p, 12, 0.85)


@top("gown.ice", "gown", "N", "Ice Gown", "Buz Balo Elbisesi", "dff1fa", "a9d8ef")
def _(p):
    def flake(lx, ly, i, j):
        return union(*[segment(lx, ly, 0, 0, 0.012 * math.cos(a), 0.012 * math.sin(a), 0.002) for a in np.arange(0, 6.28, 1.047)])
    allover(p, tile(p.X, p.Y, 0.07, 0.07, flake), color=WHITE)
    p.second(waves(p.X, p.Y, 0.1, 0.01, 0.02, 0.05) + (p.Y > 0.15) * 1.0, "body")
    skirt_folds(p, 12, 0.88)


@top("gown.coral", "gown", "N", "Coral Gown", "Mercan Balo Elbisesi", "f48e9c", "5fd1c9")
def _(p):
    scallop = tile(p.X, p.Y, 0.05, 1.0, lambda lx, ly, i, j: circle(lx, ly + 0.5 - 0.19, 0, 0, 0.03), stagger=0)
    p.second(union(scallop, p.Y - 0.16), p.body)
    p.paint(np.abs(p.Y - 0.405) - 0.006, hx("fff1d6"), region="body")
    for k in range(9):
        a = -0.08 + 0.02 * k
        p.paint(circle(p.X, p.Y, a, 0.585 - 0.03 * (1 - abs(k - 4) / 4), 0.005), CREAM, region="body")
    skirt_folds(p, 12, 0.85)


# ================================================================ kimono
@top("kimono.glory", "kimono", "L", "Morning Glory Kimono", "Gündüzsefası Kimono", "a9d9ec", "2f6fc4")
def _(p):
    def g(lx, ly, i, j):
        return union(star(lx, ly, 0, 0, 0.03, 5, 0.75), circle(lx, ly, 0, 0, 0.012))
    allover(p, tile(p.X, p.Y, 0.11, 0.11, g))
    p.paint(tile(p.X, p.Y, 0.11, 0.11, lambda lx, ly, i, j: star(lx, ly, 0, 0, 0.012, 5, 0.5)), WHITE)
    belt(p, 0.42, 0.06, hx("ec8b2c"))
    p.paint(polygon(p.X, p.Y, [(-0.05, 0.62), (0.05, 0.62), (0.0, 0.46)]), hx("e9f5fa"), region="body")


@top("kimono.plum", "kimono", "L", "Plum Yukata", "Mürdüm Yukata", "5a2f45", "7b4a62")
def _(p):
    allover(p, stripes(p.X, 0.03, 0.01))
    p.paint(tile(p.X, p.Y, 0.03, 0.025, lambda lx, ly, i, j: rect(lx, ly, -0.002, 0.002, -0.006, 0.006)), hx("c9a7b8"))
    belt(p, 0.42, 0.045, hx("8a8a80"))
    p.paint(polygon(p.X, p.Y, [(-0.05, 0.62), (0.05, 0.62), (0.0, 0.48)]), hx("3a1d2c"), region="body")


# ================================================================ tulum
@top("jumpsuit.aerobic", "jumpsuit", "H", "Aerobics Suit", "Aerobik Kıyafeti", "1e5c46", "77c8a6", legs_to=0.22,
     legs_r=(0.056, 0.050))
def _(p):
    p.second(np.abs(segment(p.X, p.Y, -0.12, 0.33, 0.10, 0.58, 0.0)) - 0.015, "body")
    p.paint(np.abs(segment(p.X, p.Y, -0.10, 0.36, 0.12, 0.60, 0.0)) - 0.004, WHITE, region="body")
    cuffs(p, 0.015)


@top("jumpsuit.workman", "jumpsuit", "H", "Workman Overalls", "İşçi Tulumu", "f2c21e", "6b2fa0")
def _(p):
    overall_bib(p)
    buttons(p, (0.49,), GOLD, x=-0.045, r=0.009)
    buttons(p, (0.49,), GOLD, x=0.045, r=0.009)


@top("jumpsuit.baseball", "jumpsuit", "L", "Baseball Uniform", "Beyzbol Forması", "f4f4f2", "c8202f")
def _(p):
    p.second(None, "sleeves")
    cuffs(p, 0.02, WHITE)
    p.text("S", 0.04, 0.50, 0.035, color=hx("c8202f"), font="/System/Library/Fonts/Supplemental/Georgia Bold Italic.ttf")
    buttons(p, (0.45, 0.50, 0.55), hx("c8202f"), x=0.0, r=0.005)
    p.paint(np.abs(p.X) - 0.004, hx("c8202f"), region="legs")
    belt(p, 0.40, 0.02, BLACK)
    p.paint(p.Y - 0.14, hx("c8202f"), region="legs")


@top("jumpsuit.coverall", "jumpsuit", "L", "Coverall", "İş Tulumu", "d4592a", "b2471f")
def _(p):
    pocket(p, -0.06, 0.50, 0.04, 0.035, second=True)
    p.dark(segment(p.X, p.Y, 0, 0.36, 0, 0.60, 0.002), 0.75, "body")
    belt(p, 0.40, 0.02)
    p.paint(rect(p.X, p.Y, 0.04, 0.08, 0.49, 0.51), hx("2a2a2a"), region="body")


@top("jumpsuit.genie", "jumpsuit", "N", "Genie Outfit", "Lamba Cini Kıyafeti", "f2ead2", "5e3a98", legs_r=(0.062, 0.052))
def _(p):
    p.second(np.maximum(np.abs(p.X) - 0.20, 0.36 - p.Y), "body")
    p.first(np.maximum(np.abs(p.X) - 0.035, 0.40 - p.Y), "body")
    p.paint(np.abs(np.abs(p.X) - 0.035) - 0.004, GOLD, region=p.body & (p.Y > 0.40))
    belt(p, 0.38, 0.03, hx("d43a3a"))


@top("jumpsuit.wrestler", "jumpsuit", "N", "Wrestler Suit", "Güreşçi Kıyafeti", "c22a2a", "2f6fd0")
def _(p):
    p.second(None, "legs")
    p.paint(polygon(p.X, p.Y, [(-0.06, 0.52), (0.06, 0.52), (0.0, 0.45)]), hx("f2c21e"), region="body")
    p.paint(polygon(p.X, p.Y, [(-0.02, 0.50), (0.03, 0.50), (0.0, 0.42)]), hx("c22a2a"), region="body")
    belt(p, 0.39, 0.035, hx("f2c21e"))
    p.paint(circle(p.X, p.Y, 0, 0.20, 0.025), hx("c22a2a"), region="legs")


# ================================================================ uzun kazak / kapüşonlu elbise
@top("hoodie.mint", "knitdress", "L", "Hoodie Dress", "Kapüşonlu Elbise", "6fcfae", "4aa98b", hood=True)
def _(p):
    pocket(p, 0, 0.36, 0.11, 0.05, second=True)
    for s in (-1, 1):
        p.paint(segment(p.X, p.Y, s * 0.02, 0.60, s * 0.022, 0.52, 0.004), WHITE, region="body")
    hem_band(p, 0.02)
    cuffs(p, 0.025)


@top("hoodie.nordic", "knitdress", "L", "Nordic Knit Dress", "İskandinav Örgü Elbise", "a32a2a", "f2e6d0")
def _(p):
    def flake(lx, ly, i, j):
        return union(*[segment(lx, ly, 0, 0, 0.012 * math.cos(a), 0.012 * math.sin(a), 0.003) for a in np.arange(0, 6.28, 0.785)])
    p.second(np.maximum(tile(p.X, p.Y, 0.05, 0.06, flake), np.abs(p.Y - 0.47) - 0.04), "body")
    p.second(zigzag(p.X, p.Y, 0.03, 0.006, 0.006) + (np.abs(p.Y - 0.29) > 0.015) * 1.0, "body")
    p.second(zigzag(p.X, p.Y, 0.03, 0.006, 0.006) + (np.abs(p.Y - 0.08) > 0.015) * 1.0, "sleeves")
    p.text("❄", 0, 0.47, 0.04, second=True, font="/System/Library/Fonts/Apple Symbols.ttf") if False else None


@top("knitdress.stripe", "knitdress", "N", "Caterpillar Knit", "Tırtıl Örgü", "5cc16a", "2f8a46")
def _(p):
    allover(p, stripes(p.Y, 0.05, 0.025))
    p.dark(stripes(p.Y, 0.05, 0.003, 0.25), 0.85, "body")


@top("knitdress.sheep", "knitdress", "N", "Fleecy Sheep", "Kuzucuk", "f6ecd2", "f4a6b0")
def _(p):
    p.second(ellipse(p.X, p.Y, 0, 0.40, 0.055, 0.08), "body")
    def puff(lx, ly, i, j):
        return np.abs(circle(lx, ly, 0, 0, 0.012)) - 0.0015
    p.dark(tile(p.X, p.Y, 0.03, 0.03, puff), 0.9, p.body)
    p.paint(ellipse(p.X, p.Y, 0, 0.60, 0.02, 0.012), hx("d9b16a"), region="body")


# ================================================================ cüppe
@top("robe.cloak", "robe", "L", "Pumpkin Cloak", "Bal Kabağı Pelerini", "c9611f", "b88a5a")
def _(p):
    p.second(np.maximum(np.abs(p.X) - (0.03 + (0.50 - p.Y) * 0.12), p.Y - 0.50), "body")
    belt(p, 0.40, 0.018, hx("5a3216"))
    for s in (-1, 1):
        p.paint(segment(p.X, p.Y, 0, 0.60, s * 0.03, 0.57, 0.004), hx("3a1d0e"), region="body")


@top("robe.wizard", "robe", "L", "Wizard Robe", "Büyücü Cüppesi", "22306b", "f2b32b")
def _(p):
    allover(p, tile(p.X, p.Y, 0.07, 0.07, lambda lx, ly, i, j: star(lx, ly, 0, 0, 0.012, 5, 0.45)), color=hx("f2d36b"))
    p.second(np.abs(np.abs(p.X) - 0.03) - 0.008, "body")
    cuffs(p, 0.03)
    p.paint(polygon(p.X, p.Y, [(-0.03, 0.60), (0.03, 0.60), (0.0, 0.56)]), hx("f2b32b"), region="body")


# ================================================================ salopet
@top("dungaree.frog", "dungaree", "H", "Frog Dungarees", "Kurbağa Salopet", "ffffff", "3f9c4a")
def _(p):
    overall_bib(p)
    p.paint(stripes(p.X, 0.03, 0.008), hx("b8e3b0"), region=p.legs)
    buttons(p, (0.48,), hx("d93a3a"), x=-0.045, r=0.009)
    buttons(p, (0.48,), hx("d93a3a"), x=0.045, r=0.009)
    p.paint(union(polygon(p.X, p.Y, [(0, 0.585), (-0.025, 0.6), (-0.025, 0.57)]), polygon(p.X, p.Y, [(0, 0.585), (0.025, 0.6), (0.025, 0.57)])), hx("d93a3a"), region="body")


@top("dungaree.sport", "dungaree", "H", "Sport Suit", "Spor Takımı", "d8262c", "1d1d1d", legs_to=0.22, legs_r=(0.058, 0.052))
def _(p):
    p.second(np.abs(np.abs(p.X) - 0.16) - 0.03, "body")
    p.second(None, "sleeves")
    p.second(None, "legs")
    p.paint(np.abs(np.abs(p.X) - 0.06) - 0.006, WHITE, region="legs")
    p.text("Z", 0.0, 0.50, 0.04, color=WHITE, font="/System/Library/Fonts/Supplemental/Impact.ttf")


@top("dungaree.suit", "dungaree", "L", "Vest Suit", "Yelekli Takım", "f4f4f4", "1e1e22")
def _(p):
    p.second(polygon(p.X, p.Y, [(-0.14, 0.36), (0.14, 0.36), (0.14, 0.60), (0.03, 0.60), (0, 0.50), (-0.03, 0.60), (-0.14, 0.60)]), "body")
    p.second(np.abs(p.X) - 0.13 + 0 * p.Y if False else (0.36 - p.Y), "body")
    p.second(None, "legs")
    buttons(p, (0.45, 0.42, 0.39), hx("555555"), r=0.005)
    p.paint(polygon(p.X, p.Y, [(-0.006, 0.585), (0.006, 0.585), (0.01, 0.50), (0, 0.49), (-0.01, 0.50)]), hx("7a1f2a"), region="body")


@top("dungaree.clover", "dungaree", "L", "Clover Suit", "Yonca Takımı", "2f8a3e", "f2c21e")
def _(p):
    belt(p, 0.40, 0.03, BLACK, buckle=hx("f2c21e"))
    p.paint(polygon(p.X, p.Y, [(-0.05, 0.61), (0.05, 0.61), (0.0, 0.50)]), WHITE, region="body")
    buttons(p, (0.47, 0.44), hx("f2c21e"), r=0.005)
    cuffs(p, 0.02)


@top("dungaree.romper", "dungaree", "N", "Romper", "Tulum Şort", "6b3a24", "4f2a1a", legs_to=0.24, legs_r=(0.058, 0.054))
def _(p):
    pocket(p, 0, 0.47, 0.07, 0.05, second=True)
    for s in (-1, 1):
        p.paint(circle(p.X, p.Y, s * 0.045, 0.53, 0.006), hx("e0b27a"), region="body")


@top("dungaree.camo", "dungaree", "L", "Camo Suit", "Kamuflaj Takım", "6e9b4a", "3d6a2e")
def _(p):
    def blob(lx, ly, i, j):
        return union(ellipse(lx, ly, 0, 0, 0.03, 0.018, 0.7 * np.sin(i + j)), ellipse(lx, ly, 0.02, 0.01, 0.018, 0.012))
    allover(p, tile(p.X, p.Y, 0.09, 0.07, blob))
    p.paint(tile(p.X + 0.04, p.Y + 0.035, 0.09, 0.07, lambda lx, ly, i, j: ellipse(lx, ly, 0, 0, 0.016, 0.01, 0.4)), hx("2c3e1f"))


# ================================================================ tunik (üst)
@top("tunic.apron", "tunic", "H", "Shop Apron", "Dükkân Önlüğü", "e4672b", "9ec9e6")
def _(p):
    p.second(np.maximum(-np.maximum(np.abs(p.X) - 0.11, p.Y - 0.53), -1), "body")
    p.second(None, "sleeves")
    pocket(p, 0.0, 0.36, 0.08, 0.035)
    p.paint(np.abs(p.Y - 0.53) - 0.004, WHITE, region=p.body & (np.abs(p.X) < 0.11))


@top("tunic.tied", "tunic", "H", "Tied Flannel", "Bele Bağlı Ekose", "f3e8c9", "4a6a2c")
def _(p):
    a = stripes(p.X, 0.04, 0.01)
    b = stripes(p.Y, 0.04, 0.01)
    p.second(np.maximum(np.minimum(a, b), p.Y - 0.36), "body")
    p.second(np.maximum(np.minimum(a, b), np.abs(p.Y - 0.37) - 0.012), "body")
    collar_flaps(p, hx("e2d2a8"))


@top("tunic.academic", "tunic", "L", "Academic Robe", "Akademik Cüppe", "1c1c20", "b02233")
def _(p):
    p.paint(polygon(p.X, p.Y, [(-0.04, 0.61), (0.04, 0.61), (0.0, 0.52)]), WHITE, region="body")
    p.second(polygon(p.X, p.Y, [(-0.008, 0.59), (0.008, 0.59), (0.012, 0.52), (0, 0.51), (-0.012, 0.52)]), "body")
    p.dark(np.abs(np.abs(p.X) - 0.04) - 0.002, 0.75, "body")


@top("tunic.workshop", "tunic", "L", "Workshop Apron", "Atölye Önlüğü", "7d4a2a", "6f8fc8")
def _(p):
    p.second(np.maximum(np.abs(p.X) - 0.11, 0.0) * 0 + (np.abs(p.X) > 0.11) * 1.0 - 0.5 + (p.Y > 0.53) * 1.0, "body")
    p.second(None, "sleeves")
    pocket(p, -0.04, 0.38, 0.05, 0.04)
    p.paint(rect(p.X, p.Y, 0.03, 0.04, 0.37, 0.43), hx("c0c0c0"), region="body")
    p.paint(circle(p.X, p.Y, -0.05, 0.31, 0.006), hx("e05a3a"), region="body")
    p.paint(circle(p.X, p.Y, 0.06, 0.29, 0.005), hx("f2c21e"), region="body")


@top("tunic.lips", "tunic", "N", "Lips Tunic", "Dudak Tunik", "f2f2f2", "d0202e")
def _(p):
    lips = union(ellipse(p.X, p.Y, 0, 0.47, 0.05, 0.02), ellipse(p.X, p.Y, -0.02, 0.485, 0.03, 0.015, 0.3),
                 ellipse(p.X, p.Y, 0.02, 0.485, 0.03, 0.015, -0.3))
    p.second(lips, "body")
    p.paint(np.abs(p.Y - 0.47) - 0.002, hx("7a0d16"), region=p.body & (np.abs(p.X) < 0.045))
    def sq(lx, ly, i, j):
        return circle(lx, ly, 0, 0, 0.002)
    p.dark(tile(p.X, p.Y, 0.012, 0.012, sq), 0.92, "body")


@top("tunic.bolt", "tunic", "N", "Bolt Tunic", "Şimşek Tunik", "e4e6ea", "e0353b")
def _(p):
    p.paint(rect(p.X, p.Y, -0.045, 0.045, 0.43, 0.53, 0.008), hx("1d1d22"), region="body")
    p.second(polygon(p.X, p.Y, [(0.01, 0.52), (-0.025, 0.47), (0.0, 0.47), (-0.012, 0.44), (0.028, 0.49), (0.004, 0.49), (0.02, 0.52)]), "body")


# ================================================================ kazak ve yelek
@top("sweater.cable", "sweater", "L", "Cable Sweater", "Burgu Kazak", "9e2328", "861c21")
def _(p):
    for x in (-0.05, 0.0, 0.05):
        p.second(np.abs(np.abs(np.mod(p.Y, 0.03) - 0.015) * 1.5 + np.abs(p.X - x) - 0.016) - 0.004, "body")
    hem_band(p, 0.02)
    cuffs(p, 0.02)
    neck_band(p)


@top("sweater.pastel", "sweater", "L", "Pastel Star Sweater", "Pastel Yıldızlı Kazak", "f6b6dc", "9cd3f2")
def _(p):
    p.second(None, "sleeves")
    for k, (x, y, c) in enumerate([(-0.05, 0.50, "f7e06a"), (0.04, 0.44, "b6f0c0"), (0.07, 0.53, "ffffff"), (-0.08, 0.40, "ffffff")]):
        p.paint(star(p.X, p.Y, x, y, 0.016, 5, 0.5), hx(c), region="body")
    p.paint(np.abs(circle(p.X, p.Y, 0.0, 0.33, 0.12)) - 0.006, hx("f7a3a3"), region=p.body & (p.Y > 0.38))
    p.paint(np.abs(circle(p.X, p.Y, 0.0, 0.33, 0.108)) - 0.006, hx("f7e06a"), region=p.body & (p.Y > 0.38))
    p.paint(np.abs(circle(p.X, p.Y, 0.0, 0.33, 0.096)) - 0.006, hx("9cd3f2"), region=p.body & (p.Y > 0.38))
    hem_band(p, 0.02)


@top("vest.knit", "vest", "N", "Knit Vest", "Örgü Yelek", "a85a2a", "8f4a22")
def _(p):
    p.second(stripes(p.X, 0.012, 0.005), "body")
    hem_band(p, 0.025)
    neck_band(p, 0.02)


@top("vest.hoodie", "vest", "N", "Sleeveless Hoodie", "Kolsuz Kapüşonlu", "6ccf3c", "2f7a1e", hood=True)
def _(p):
    p.second(np.maximum(p.Y - 0.44, 0), "body") if False else None
    p.paint(segment(p.X, p.Y, 0, 0.60, 0, 0.36, 0.006), hx("2f7a1e"), region="body")
    p.paint(circle(p.X, p.Y, 0, 0.58, 0.007), hx("dcdcdc"), region="body")
    hem_band(p, 0.02)


# ================================================================ kabarık kollu
@top("puff.gingham", "puff", "H", "Gingham Puff Top", "Pötikare Balon Kollu", "4f95e0", "a8cdf3")
def _(p):
    a = stripes(p.X, 0.03, 0.015)
    b = stripes(p.Y, 0.03, 0.015)
    p.second(np.minimum(a, b))
    p.paint(np.maximum(a, b), WHITE, alpha=0.85)
    cloud = union(circle(p.X, p.Y, -0.02, 0.47, 0.022), circle(p.X, p.Y, 0.015, 0.475, 0.026), circle(p.X, p.Y, 0.04, 0.465, 0.018),
                  rect(p.X, p.Y, -0.035, 0.05, 0.45, 0.47))
    p.paint(cloud, WHITE, region="body")
    p.paint(np.abs(cloud) - 0.002, hx("6aa6e8"), region="body")


@top("puff.madras", "puff", "H", "Madras Puff Top", "Madras Balon Kollu", "8ed6c5", "f7b3c2")
def _(p):
    a = stripes(p.X, 0.05, 0.018)
    b = stripes(p.Y, 0.05, 0.018)
    p.second(np.minimum(a, b))
    p.paint(np.minimum(stripes(p.X, 0.05, 0.006, 0.5), stripes(p.Y, 0.05, 0.006, 0.5)), hx("f2e27a"), alpha=0.9)


# ================================================================ tişört
@top("tee.letter", "tee", "H", "Letter Tee", "Harfli Tişört", "2b5cc8", "ffffff")
def _(p):
    p.text("S", 0, 0.47, 0.085, second=True)


@top("tee.kanji", "tee", "H", "Sky Kanji Tee", "Gök Yazılı Tişört", "9ee6cf", "2f6a4f")
def _(p):
    p.text("空", 0, 0.48, 0.07, second=True, font="/System/Library/Fonts/Hiragino Sans GB.ttc")
    p.paint(rect(p.X, p.Y, 0.04, 0.052, 0.40, 0.412, 0.001), hx("d83a3a"), region="body")


@top("tee.number", "tee", "H", "Number Tee", "Numaralı Tişört", "2a52d9", "ffffff")
def _(p):
    p.text("7", 0, 0.47, 0.08, color=WHITE, outline=hx("d83a3a"))


@top("tee.sheer", "tee", "L", "Sheer Layer Top", "Tül Katmanlı Bluz", "f4f6fa", "dfe6f0")
def _(p):
    p.second(None, "sleeves")
    p.dark(np.abs(p.Y - 0.56) - 0.003, 0.9, "body")


@top("tee.loose", "tee", "L", "Loose Tee", "Bol Tişört", "8c949c", "7a8188")
def _(p):
    neck_band(p, 0.015)
    cuffs(p, 0.015)


@top("tee.vneck", "tee", "L", "V-Neck Sweater", "V Yaka Kazak", "2b3aa8", "1f2c86")
def _(p):
    vneck(p, 0.06, hx("1f2c86"))
    p.paint(np.abs(polygon(p.X, p.Y, [(-0.05, 0.62), (0.05, 0.62), (0, 0.56)])) - 0.004, hx("3b4cc0"), region="body")
    hem_band(p, 0.02)
    cuffs(p, 0.02)


@top("tee.jersey", "tee", "N", "Basketball Jersey", "Basketbol Forması", "5a2f9c", "f2c21e")
def _(p):
    p.text("23", 0, 0.45, 0.06, color=WHITE, outline=hx("f2c21e"))
    p.text("SLASH", 0, 0.535, 0.022, second=True)
    p.paint(np.abs(np.abs(p.X) - 0.16) - 0.008, hx("f2c21e"), region="body")


@top("tee.lei", "tee", "N", "Lei Tank", "Çiçek Kolyeli Atlet", "b52a2f", "f2c21e")
def _(p):
    for k in range(13):
        a = math.pi * (0.05 + 0.9 * k / 12)
        x, y = 0.075 * math.cos(a), 0.60 - 0.07 * math.sin(a)
        p.paint(flower(p.X, p.Y, x, y, 0.011, 5), hx("fbe7a0") if k % 2 else WHITE, region="body")
        p.paint(circle(p.X, p.Y, x, y, 0.003), hx("f2c21e"), region="body")


@top("tee.argyletank", "tee", "N", "Argyle Tank", "Ekoseli Atlet", "1d1d1d", "c72a2a")
def _(p):
    def cell(lx, ly, i, j):
        return diamond(lx, ly, 0, 0, 0.03, 0.04)
    d = tile(p.X, p.Y, 0.06, 0.08, cell, stagger=0.5)
    p.second(np.maximum(d, np.where(np.mod(np.floor(p.Y / 0.08), 2) == 0, -1, 1) * 0.01))
    hem_band(p, 0.03, hx("f2c21e"))


@top("tee.band", "tee", "L", "Band Tee", "Grup Tişörtü", "1d1d22", "4fc3e8")
def _(p):
    p.text("LOFI", 0, 0.48, 0.035, second=True, font="/System/Library/Fonts/Supplemental/Impact.ttf")
    p.paint(np.abs(p.Y - (p.layout.sleeve - 0.02)) - 0.006, hx("f04fa0"), region="sleeves")
    p.paint(np.abs(p.Y - (p.layout.sleeve - 0.035)) - 0.005, hx("7ae36a"), region="sleeves")


@top("tee.patchwork", "tee", "N", "Patchwork Top", "Yama İşi Bluz", "e07a2c", "6a3f8f")
def _(p):
    p.second(np.where((p.X > 0.0) ^ (p.Y > 0.45), -1.0, 1.0) * 0.01, "body")
    p.paint(np.where((p.X < -0.06) & (p.Y < 0.40), -1.0, 1.0) * 0.01, hx("3f8f5a"), region="body")
    for k in range(9):
        a = math.pi * (0.1 + 0.8 * k / 8)
        p.paint(circle(p.X, p.Y, 0.05 * math.cos(a), 0.59 - 0.05 * math.sin(a), 0.005), hx("f45aa0"), region="body")


@top("tee.paisley", "tee", "N", "Paisley Tank", "Şal Desenli Atlet", "6a3fa8", "f087c3")
def _(p):
    def pz(lx, ly, i, j):
        return union(circle(lx, ly, 0, 0, 0.012), leaf(lx, ly, 0.012, 0.012, 0.03, 0.012, 0.8))
    allover(p, tile(p.X, p.Y, 0.06, 0.06, pz))
    p.paint(tile(p.X, p.Y, 0.06, 0.06, lambda lx, ly, i, j: circle(lx, ly, 0, 0, 0.004)), hx("8fe08a"))


# ================================================================ yakalı gömlek
@top("shirt.aloha", "shirt", "H", "Pineapple Aloha", "Ananaslı Aloha", "1f4fa0", "4fb0e8")
def _(p):
    def pa(lx, ly, i, j):
        return union(ellipse(lx, ly, 0, 0, 0.011, 0.016), *[leaf(lx, ly, s * 0.006, 0.02, 0.016, 0.005, 1.57 + s * 0.4) for s in (-1, 0, 1)])
    allover(p, tile(p.X, p.Y, 0.06, 0.06, pa))
    p.paint(tile(p.X, p.Y, 0.06, 0.06, lambda lx, ly, i, j: leaf(lx, ly, 0.02, -0.02, 0.03, 0.01, 0.6)), hx("2e9a5a"))
    buttons(p, np.arange(0.36, 0.58, 0.05), WHITE, r=0.005)


@top("shirt.leaf", "shirt", "H", "Leaf Print Shirt", "Yaprak Desenli Gömlek", "e3f2e8", "4aa37a")
def _(p):
    def lv(lx, ly, i, j):
        a = 0.8 * np.sin(i * 2.1 + j * 1.3)
        return leaf(lx, ly, 0, 0, 0.04, 0.016, a)
    allover(p, tile(p.X, p.Y, 0.05, 0.05, lv))
    p.paint(tile(p.X, p.Y, 0.05, 0.05, lambda lx, ly, i, j: segment(lx, ly, -0.015, -0.006, 0.015, 0.006, 0.002)), hx("2a7a52"))
    buttons(p, np.arange(0.36, 0.58, 0.05), hx("8a5a2b"), r=0.005)


@top("shirt.batik", "shirt", "H", "Batik Shirt", "Batik Gömlek", "b8272b", "e2843a")
def _(p):
    allover(p, zigzag(p.Y, p.X, 0.04, 0.008, 0.008))
    p.paint(tile(p.X, p.Y, 0.04, 0.04, lambda lx, ly, i, j: diamond(lx, ly, 0, 0, 0.005, 0.008)), hx("f2d36b"))


@top("shirt.argyle", "shirt", "L", "Argyle Vest Shirt", "Ekose Yelekli Gömlek", "9ec4ec", "2a3d78")
def _(p):
    vest = np.maximum(np.abs(p.X) - 0.20, 0) * 0 + np.where(p.Y < 0.56, -1.0, 1.0) * 0.01
    d = tile(p.X, p.Y, 0.05, 0.065, lambda lx, ly, i, j: diamond(lx, ly, 0, 0, 0.025, 0.0325))
    p.second(np.maximum(vest, -0.02 + 0 * d), "body")
    p.paint(np.maximum(np.maximum(d, vest), np.where(np.mod(np.floor(p.Y / 0.065), 2) == 0, -1, 1) * 0.01), hx("6f86c8"), region="body")
    p.paint(np.maximum(np.minimum(stripes(p.X - p.Y * 0.77, 0.05, 0.002), stripes(p.X + p.Y * 0.77, 0.05, 0.002)), vest), hx("dfe6f5"), region="body")
    p.paint(polygon(p.X, p.Y, [(-0.04, 0.56), (0.04, 0.56), (0, 0.50)]), hx("9ec4ec"), region="body")


@top("shirt.polo", "shirt", "L", "Layered Polo", "Katmanlı Polo", "26336e", "141a3a")
def _(p):
    p.second(None, "sleeves")
    p.paint(circle(p.X, p.Y, 0.05, 0.52, 0.008), hx("d0d4e8"), region="body")
    buttons(p, (0.56, 0.535), hx("d0d4e8"), r=0.004)


@top("shirt.work", "shirt", "L", "Work Shirt", "İş Gömleği", "c9792a", "a8601e")
def _(p):
    pocket(p, -0.055, 0.50, 0.045, 0.045, second=True)
    pocket(p, 0.055, 0.50, 0.045, 0.045, second=True)
    buttons(p, np.arange(0.36, 0.58, 0.05), hx("f2d6a8"), r=0.005)
    buttons(p, (0.515,), hx("f2d6a8"), x=-0.055, r=0.004)
    buttons(p, (0.515,), hx("f2d6a8"), x=0.055, r=0.004)


@top("shirt.denimvest", "shirt", "N", "Denim Vest", "Kot Yelek", "5f87b8", "3f6a9c")
def _(p):
    pocket(p, -0.055, 0.50, 0.04, 0.035, second=True)
    pocket(p, 0.055, 0.50, 0.04, 0.035, second=True)
    p.dark(np.abs(np.abs(p.X) - 0.012) - 0.0012, 0.7, "body")
    buttons(p, np.arange(0.38, 0.58, 0.045), hx("c9cbd0"), x=0.018, r=0.004)


@top("shirt.polkacami", "shirt", "N", "Polka Camisole", "Puantiyeli Askılı", "ffffff", "1d1d1d")
def _(p):
    allover(p, tile(p.X, p.Y, 0.026, 0.026, lambda lx, ly, i, j: circle(lx, ly, 0, 0, 0.0065)))
    p.paint(np.abs(p.Y - 0.58) - 0.005, hx("1d1d1d"), region="body")


@top("shirt.plain", "shirt", "N", "Sleeveless Shirt", "Kolsuz Gömlek", "f6f6f4", "e6e6e2")
def _(p):
    pocket(p, -0.055, 0.51, 0.04, 0.04, second=True)
    buttons(p, np.arange(0.36, 0.58, 0.05), hx("d8d8d0"), r=0.005)


# ================================================================ ALTLAR
@bottom("knee.pineapple", "knee", "Pineapple Shorts", "Ananaslı Diz Altı Şort", "1d3a6e", "f2c21e")
def _(p):
    def pa(lx, ly, i, j):
        return ellipse(lx, ly, 0, 0, 0.008, 0.012)
    allover(p, tile(p.X, p.Y, 0.04, 0.04, pa))
    p.paint(tile(p.X, p.Y, 0.04, 0.04, lambda lx, ly, i, j: leaf(lx, ly, 0, 0.016, 0.012, 0.005, 1.57)), hx("2e9a5a"))


@bottom("knee.track", "knee", "Track Shorts", "Eşofman Şort", "9b2328", "ffffff")
def _(p):
    p.second(np.abs(np.abs(p.X) - 0.075) - 0.008, "legs")


@bottom("knee.sport", "knee", "Sport Shorts", "Spor Şort", "1d1d22", "e0353b")
def _(p):
    p.second(np.abs(np.abs(p.X) - 0.075) - 0.012, "legs")
    p.second(p.Y - 0.19, "legs")


@bottom("hot.denim", "hot", "Denim Shorts", "Kot Şort", "6d8fbf", "4f72a8")
def _(p):
    p.second(p.Y - 0.285, "legs")
    p.dark(np.abs(p.X - 0.0) - 0.0015, 0.75, "body")


@bottom("hot.studded", "hot", "Studded Shorts", "Zımbalı Şort", "1c1c1f", "2c2c30")
def _(p):
    p.paint(tile(p.X, p.Y, 0.02, 0.5, lambda lx, ly, i, j: circle(lx, ly, 0, 0, 0.004), stagger=0), hx("c8c8cc"),
            region=p.body & (np.abs(p.Y - 0.38) < 0.01))
    p.second(np.abs(p.Y - 0.38) - 0.012, "body")


@bottom("hot.lemon", "hot", "Lemon Shorts", "Limonlu Şort", "2a8f86", "f2d63a")
def _(p):
    allover(p, tile(p.X, p.Y, 0.04, 0.035, lambda lx, ly, i, j: ellipse(lx, ly, 0, 0, 0.012, 0.008, 0.4)))


@bottom("pants.forest", "pants", "Forest Pants", "Orman Yeşili Pantolon", "1f3d2c", "17301f")
def _(p):
    p.second(np.abs(np.abs(p.X) - 0.075) - 0.004, "legs")


@bottom("pants.ripped", "pants", "Ripped Jeans", "Yırtık Kot", "3f5f8f", "c9d6e8")
def _(p):
    for y in (0.20, 0.27):
        p.second(ellipse(p.X, p.Y, 0.0, y, 0.018, 0.006), "legs")
        p.paint(stripes(p.Y, 0.004, 0.0015), hx("eef2f8"), region=p.legs & (ellipse(p.X, p.Y, 0.0, y, 0.018, 0.006) < 0))
    p.second(p.Y - 0.09, "legs")


@bottom("pants.training", "pants", "Training Pants", "Antrenman Pantolonu", "1d1d1d", "7ac84a")
def _(p):
    p.second(np.abs(p.Y - 0.17) - 0.035, "legs")


@bottom("wide.bell", "wide", "Bell Bottoms", "İspanyol Paça", "a24a24", "86391b")
def _(p):
    buttons(p, (0.38,), hx("e0b27a"), r=0.006)
    p.dark(np.abs(p.X) - 0.0015, 0.75, "legs")


@bottom("wide.stripe", "wide", "Multi-Stripe Pants", "Çok Çizgili Pantolon", "d6c23a", "4f6fb8")
def _(p):
    k = np.mod(np.floor(p.X / 0.012), 4)
    p.second(np.where(k == 1, -1.0, 1.0) * 0.01, "legs")
    p.paint(np.where(k == 3, -1.0, 1.0) * 0.01, hx("8a8a8a"), region="legs")


@bottom("wide.dream", "wide", "Dreamy Pants", "Rüya Pantolonu", "e8a3e0", "ffffff")
def _(p):
    def cl(lx, ly, i, j):
        return union(circle(lx, ly, -0.008, 0, 0.008), circle(lx, ly, 0.006, 0.003, 0.01), circle(lx, ly, 0.018, 0, 0.007))
    allover(p, tile(p.X, p.Y, 0.05, 0.05, cl))
    p.paint(tile(p.X + 0.025, p.Y + 0.025, 0.05, 0.05, lambda lx, ly, i, j: star(lx, ly, 0, 0, 0.008)), hx("f7e06a"))


@bottom("askirt.dots", "askirt", "Dotted Skirt", "Puantiyeli Etek", "8f5a3c", "e8c8a8")
def _(p):
    allover(p, tile(p.X, p.Y, 0.025, 0.025, lambda lx, ly, i, j: circle(lx, ly, 0, 0, 0.005)))
    skirt_folds(p, 10, 0.88)


@bottom("askirt.patch", "askirt", "Patchwork Skirt", "Yama İşi Etek", "3a5a9a", "a85a3a")
def _(p):
    p.second(np.where(np.mod(np.floor(p.X / 0.08) + np.floor(p.Y / 0.07), 2) == 0, -1.0, 1.0) * 0.01)
    p.paint(np.where(np.mod(np.floor(p.X / 0.08) * 3 + np.floor(p.Y / 0.07), 5) == 0, -1.0, 1.0) * 0.01, hx("6a2a3a"))
    skirt_folds(p, 10, 0.88)


@bottom("askirt.tweed", "askirt", "Tweed Skirt", "Tüvit Etek", "3a3230", "6a5a52")
def _(p):
    allover(p, np.minimum(stripes(p.X, 0.03, 0.006), stripes(p.Y, 0.03, 0.006)))
    hem_band(p, 0.012, hx("1d1816"))
    skirt_folds(p, 10, 0.88)


@bottom("boxskirt.lace", "boxskirt", "Lace Hem Skirt", "Dantel Etekli", "9a9a9e", "c8a8e8")
def _(p):
    p.second(waves(p.X, p.Y - p.layout.hem, 10, 0.004, 0.024, 0.02) + (p.Y > p.layout.hem + 0.02) * 1.0)


@bottom("boxskirt.fringe", "boxskirt", "Fringe Skirt", "Saçaklı Etek", "8a4a24", "6a3618")
def _(p):
    p.second(np.maximum(stripes(p.X, 0.008, 0.003), p.Y - (p.layout.hem + 0.04)))


@bottom("boxskirt.rose", "boxskirt", "Rose Skirt", "Güllü Etek", "1d1d1f", "c84a5a")
def _(p):
    def r(lx, ly, i, j):
        return union(circle(lx, ly, 0, 0, 0.012), leaf(lx, ly, 0.015, -0.01, 0.018, 0.008, -0.5))
    allover(p, tile(p.X, p.Y, 0.05, 0.045, r))
    p.paint(tile(p.X, p.Y, 0.05, 0.045, lambda lx, ly, i, j: leaf(lx, ly, 0.015, -0.01, 0.018, 0.008, -0.5)), hx("3f8a4a"))


@bottom("longskirt.tartan", "longskirt", "Tartan Maxi Skirt", "Tartan Uzun Etek", "b0202a", "1d1d2a")
def _(p):
    allover(p, np.minimum(stripes(p.X, 0.05, 0.014), stripes(p.Y, 0.05, 0.014)))
    p.paint(np.minimum(stripes(p.X, 0.05, 0.003, 0.5), stripes(p.Y, 0.05, 0.003, 0.5)), hx("f2c21e"))
    skirt_folds(p, 10, 0.88)


@bottom("longskirt.olive", "longskirt", "Olive Maxi Skirt", "Zeytin Uzun Etek", "b8b23a", "9a9430")
def _(p):
    buttons(p, (0.34, 0.30), hx("f2f0e0"), x=0.0, r=0.006)
    skirt_folds(p, 10, 0.88)


@bottom("longskirt.wrap", "longskirt", "Wrap Maxi Skirt", "Kruvaze Uzun Etek", "6f7684", "2a2c32")
def _(p):
    p.second(np.abs(p.X - 0.15) - 0.06)
    buttons(p, (0.35, 0.29, 0.23, 0.17), BLACK, x=0.09, r=0.006)


# ================================================================ AYAKKABILAR
def toe_cap(p, color=None):
    d = (p.v - 0.30) + 0 * p.u
    front = np.abs(p.u - 0.5) < 0.18
    if color is None:
        p.second(np.where(front, d, 1.0), "all")
    else:
        p.paint(np.where(front, d, 1.0), color)


@shoe("hightop.classic", "hightop", "Classic High-Tops", "Klasik Bilekli", "d8262c", "1d1d1d")
def _(p):
    p.second(np.where((np.abs(p.u - 0.5) > 0.22) & (p.v < 0.6), -1.0, 1.0) * 0.01)
    p.paint(np.where((np.abs(p.u - 0.5) < 0.08) & (p.v > 0.45) & (p.v < 0.75), -1.0, 1.0) * 0.01, WHITE)


@shoe("ankle.mouton", "ankle", "Fleece Boots", "Kürklü Bot", "8a5a34", "e8d8b8")
def _(p):
    p.second(np.where(p.v > 0.92, -1.0, 1.0) * 0.01)
    p.dark(np.abs(p.v - 0.30) * 0.2 - 0.002 + 0 * p.u, 0.85)


@shoe("cast.leg", "cast", "Leg Cast", "Alçı Bot", "c9ced2", "8f979e", sole="9aa0a6")
def _(p):
    p.dark(stripes(p.v * 0.6 + p.u * 0.05, 0.02, 0.002), 0.9)


@shoe("knee.snow", "knee", "Snow Boots", "Kar Botu", "a3232a", "6a1218", sole="3a3a3a")
def _(p):
    p.second(np.where(p.v > 0.93, -1.0, 1.0) * 0.01)
    p.paint(np.where((np.abs(p.u - 0.25) < 0.04) & (p.v > 0.8) & (p.v < 0.88), -1.0, 1.0) * 0.01, hx("8f979e"))


@shoe("knee.western", "western", "Western Boots", "Kovboy Çizmesi", "9a5a2a", "6a3a18", sole="4a2a14")
def _(p):
    p.second(np.where(p.v > 0.93, -1.0, 1.0) * 0.01)
    p.paint(tile(p.u * 0.2, p.v * 0.2, 0.02, 0.02, lambda lx, ly, i, j: circle(lx, ly, 0, 0, 0.003)), hx("e8c88a"),
            region=(p.v > 0.75) & (p.v < 0.97))


@shoe("slipper.room", "slipper", "Room Slippers", "Ev Terliği", "2f6fb0", "d8e8f8", sole="e8e8e8")
def _(p):
    p.paint(np.where((np.abs(p.u - 0.5) < 0.1) & (np.abs(p.v - 0.55) < 0.08), -1.0, 1.0) * 0.01, WHITE)


@shoe("flat.embroidered", "flat", "Embroidered Flats", "Nakışlı Babet", "8a1f3a", "d84a8a", sole="3a1d1d")
def _(p):
    p.second(np.where((np.abs(p.u - 0.5) < 0.12) & (np.abs(p.v - 0.45) < 0.12), -1.0, 1.0) * 0.01)
    p.paint(np.where((np.abs(p.u - 0.5) < 0.04) & (np.abs(p.v - 0.45) < 0.04), -1.0, 1.0) * 0.01, hx("f2c21e"))


@shoe("lowtop.canvas", "lowtop", "Canvas Shoes", "Kanvas Ayakkabı", "8f949a", "6f7478")
def _(p):
    toe_cap(p)
    p.paint(np.where((np.abs(p.u - 0.75) < 0.03) & (np.abs(p.v - 0.45) < 0.08), -1.0, 1.0) * 0.01, GOLD)


@shoe("loafer.brown", "loafer", "Loafers", "Loafer", "5a3020", "3a1d12", sole="2a1a12")
def _(p):
    p.second(np.where((np.abs(p.u - 0.5) < 0.12) & (np.abs(p.v - 0.55) < 0.03), -1.0, 1.0) * 0.01)


@shoe("flat.pointed", "flat", "Pointed Flats", "Sivri Babet", "c22a2a", "8a1a1a", sole="5a1010")
def _(p):
    p.dark(np.abs(p.v - 0.65) - 0.01 + 0 * p.u, 0.85)


@shoe("maryjane.black", "maryjane", "Mary Janes", "Bantlı Babet", "1d1d1f", "3a3a3e", sole="111111")
def _(p):
    p.second(np.where((np.abs(p.u - 0.5) > 0.15) & (np.abs(p.u - 0.5) < 0.32) & (p.v > 0.5), -1.0, 1.0) * 0.01)
    p.paint(np.where((np.abs(p.u - 0.8) < 0.025) & (np.abs(p.v - 0.6) < 0.04), -1.0, 1.0) * 0.01, hx("c8c8cc"))


@shoe("slipper.babouche", "slipper", "Babouche Slippers", "Babuş Terlik", "2a8a8f", "a8e0d8", sole="d8c8a8")
def _(p):
    for k in range(6):
        a = 2 * math.pi * k / 6
        p.second(np.where(np.hypot(p.u - 0.5 - 0.04 * math.cos(a), (p.v - 0.5 - 0.06 * math.sin(a)) * 0.7) < 0.02, -1.0, 1.0) * 0.01)


@shoe("slide.leaf", "slide", "Leaf Slides", "Yapraklı Terlik", "b8b8b0", "3f8a4a", sole="8a8a84")
def _(p):
    p.second(np.where(np.hypot((p.u - 0.5) * 1.6, p.v - 0.55) < 0.07, -1.0, 1.0) * 0.01)


@shoe("sandal.zori", "zori", "Zori Sandals", "Zori Sandalet", "7a1f2a", "1d1d1d", sole="f2e8d0")
def _(p):
    pass


from fallbacks import FALLBACKS  # noqa: E402,F401
