# Slash Office karakteri (21 kemik) için ofis klipleri.
# Pakete yazmak: Blender -b --factory-startup --python tools/character/clips.py -- <character.json>
# (numpy gerektiği için Blender'ın Python'u; Blender API'si kullanılmaz.)
#
# Poz dili: {kemik: (x, y, z) derece} model eksenlerinde (Y yukarı, Z ileri, X karakterin solu), ebeveynin pozlu
# çerçevesinde; R = Ry·Rx·Rz. "_off": (dx, dy, dz) metre, kalçaya (Hips) öteleme.
# Dinlenme pozu T-pozu: kollar ±X boyunca. İşaretler:
#   kolu indir      UpperArm_L z<0, UpperArm_R z>0      kolu öne kaldır (indirilmiş koldan)  UpperArm_* x<0
#   dirseği bük (öne)  ForeArm_L y<0, ForeArm_R y>0   öne eğil (gövde/baş)  Spine_*/Neck/Head x>0
#   bacağı öne kaldır Thigh_* x<0                  dizi bük  Shin_* x>0
#   başı sola çevir   Head y>0
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack as acpack  # noqa: E402
import numpy as np  # noqa: E402

FPS = 24
# AvatarClip ile aynı ad ve kare sayısı (AvatarPlanner.swift: frames.count).
FRAMES = dict(idle=24, walk=24, sitType=24, sitDoze=48, wave=24, lookAround=48, sitSip=48, sitThink=48, sitStretch=36,
              stretch=36, waitTap=24, cheer=24, inspect=48, drink=36, sitDown=12, standUp=12, sofaSit=48, sitDraw=48,
              sitWrite=48, sitRead=48, readBook=72, playArcade=48, drawBoard=48, stepBackLook=48, brewCoffee=48,
              scratchHead=48, notice=18)
CLIPS = {}


def merge(*poses):
    out = {}
    for p in poses:
        for k, v in p.items():
            if k in out and not k.startswith("_"):
                out[k] = tuple(a + b for a, b in zip(out[k], v))
            else:
                out[k] = v
    return out


def clip(name):
    def register(fn):
        CLIPS[name] = fn
        return fn
    return register


def ease(t):
    return t * t * (3 - 2 * t)


POLE = {"L": (0.6, -1.0, -0.5), "R": (-0.6, -1.0, -0.5)}


def to_pose(spec):
    rot = {b: acpack.euler(*v) for b, v in spec.items() if not b.startswith("_")}
    ik = {}
    for side in "LR":
        if "_ik" + side in spec:
            ik[side] = (np.array(spec["_ik" + side], float), np.array(spec.get("_pole" + side, POLE[side]), float))
    return acpack.Pose(rot, spec.get("_off", (0, 0, 0)), ik)


def resolved(spec):
    """Anahtar pozu: IK yalnız burada çözülür, kol dönüşlerine (FK) çevrilir."""
    pose = to_pose(spec)
    if not pose.ik:
        return pose
    rot = {}
    acpack.skinning(PACK, pose, resolved=rot)
    return acpack.Pose(dict(pose.rot, **rot), pose.offset)


def keys_at(keys, f):
    """keys: [(kare, poz)], kare 0…n-1. Aradaki kareler ease ile; kemik dönüşleri slerp. IK hedefleri düz çizgide
    kaydırılmaz (çizgi omzun içinden geçince dirsek ters dönüp kol gövdeye giriyordu): anahtarlarda çözülüp dönüş olarak
    karışır, kol omzun çevresinde yay çizer."""
    if f <= keys[0][0]:
        return resolved(keys[0][1])
    for (f0, a), (f1, b) in zip(keys, keys[1:]):
        if f <= f1:
            t = ease((f - f0) / (f1 - f0)) if f1 > f0 else 1.0
            pa, pb = resolved(a), resolved(b)
            rot = {}
            for bone in set(pa.rot) | set(pb.rot):
                qa = acpack.quat(pa.rot.get(bone, np.eye(3)))
                qb = acpack.quat(pb.rot.get(bone, np.eye(3)))
                rot[bone] = acpack.quat_matrix(acpack.slerp(qa, qb, t))
            return acpack.Pose(rot, pa.offset + (pb.offset - pa.offset) * t)
    return resolved(keys[-1][1])


PACK = None


def sample(pack, name, t):
    """t: 0…1 klip boyunca; 'rest' T-pozu."""
    global PACK
    PACK = pack
    if name == "rest":
        return acpack.skinning(pack, acpack.Pose())
    n = FRAMES.get(name, 24)
    return acpack.skinning(pack, keys_at(CLIPS[name](n), t * (n - 1)))


# ---------------------------------------------------------------- temel pozlar
# Sahne (avatar uzayı, metre): tabure üstü 0,46 (merkez z≈+0,08), masa üstü 0,565, klavye z≈+0,22; ağız ayakta y≈0,70,
# otururken ≈0,86 (yüz önü z≈0,18). L = karakterin solu (+x), R = sağı (-x).
STAND = {"UpperArm_L": (0, 0, -74), "UpperArm_R": (0, 0, 74), "ForeArm_L": (0, -12, 0), "ForeArm_R": (0, 12, 0)}
SIT = merge(STAND, {"Thigh_L": (-86, 0, 0), "Thigh_R": (-86, 0, 0), "Shin_L": (80, 0, 0), "Shin_R": (80, 0, 0),
                    "Foot_L": (-8, 0, 0), "Foot_R": (-8, 0, 0), "Spine1": (3, 0, 0), "_off": (0, 0.16, 0.02)})
LAP = {"_ikL": (0.08, 0.53, 0.13), "_ikR": (-0.08, 0.53, 0.13)}
KEYS = {"_ikL": (0.085, 0.615, 0.23), "_ikR": (-0.085, 0.615, 0.23)}
TYPE = merge(SIT, KEYS, {"Head": (9, 0, 0), "Spine2": (4, 0, 0)})
HIPS = {"_ikL": (0.165, 0.37, -0.01), "_ikR": (-0.165, 0.37, -0.01), "_poleL": (1, -0.2, -1), "_poleR": (-1, -0.2, -1)}


def loop(keys, n):
    """Son kare ilkinin kopyası (döngü dikişsiz)."""
    return keys + [(n - 1, keys[0][1])]


@clip("idle")
def idle(n):
    breathe = merge(STAND, {"Spine2": (2, 0, 0), "Head": (-2, 0, 1), "UpperArm_L": (0, 0, 2), "UpperArm_R": (0, 0, -2),
                            "_off": (0, 0.006, 0)})
    return loop([(0, STAND), (n // 2, breathe)], n)


@clip("walk")
def walk(n):
    def step(side, h):
        a, b = ("L", "R") if side == "L" else ("R", "L")
        arm = {"L": 1, "R": -1}
        return merge(STAND, {
            "Thigh_" + a: (-30, 0, 0), "Shin_" + a: (6, 0, 0), "Foot_" + a: (-12, 0, 0),
            "Thigh_" + b: (24, 0, 0), "Shin_" + b: (22, 0, 0), "Foot_" + b: (14, 0, 0),
            "UpperArm_" + b: (-28, 0, 0), "UpperArm_" + a: (24, 0, 0), "ForeArm_" + b: (0, -14 * arm[b], 0),
            "Spine1": (5, 0, 0), "Spine3": (0, 5 * arm[a], 0), "Head": (-3, -3 * arm[a], 0), "_off": (0, h, 0)})
    def passing(h):
        return merge(STAND, {"Thigh_L": (-4, 0, 0), "Thigh_R": (-4, 0, 0), "Shin_L": (10, 0, 0), "Shin_R": (10, 0, 0),
                             "Spine1": (5, 0, 0), "Head": (-2, 0, 0), "_off": (0, h, 0)})
    q = (n - 1) / 4
    return [(0, step("L", -0.012)), (round(q), passing(0.012)), (round(2 * q), step("R", -0.012)),
            (round(3 * q), passing(0.012)), (n - 1, step("L", -0.012))]


@clip("sitType")
def sit_type(n):
    keys = []
    for i, f in enumerate(range(0, n - 1, 3)):
        t = 0.012 if i % 2 == 0 else -0.004
        keys.append((f, merge(TYPE, {"_ikL": (0.085, 0.615 + t, 0.23), "_ikR": (-0.085, 0.615 - t + 0.008, 0.23),
                                     "Head": (0, 2 * (i % 3) - 2, 0)})))
    return loop(keys, n)


@clip("sitDoze")
def sit_doze(n):
    base = merge(SIT, LAP, {"Spine2": (6, 0, 0)})
    nod = merge(base, {"Head": (22, 0, 4), "Neck": (8, 0, 0), "Spine3": (6, 0, 0), "_off": (0, 0.15, 0.02)})
    return loop([(0, base), (n // 2, nod)], n)


@clip("wave")
def wave(n):
    up = {"_poleR": (-1, -0.4, -0.4), "Head": (-4, -6, 0), "Spine3": (0, 0, 3)}
    a = merge(STAND, up, {"_ikR": (-0.29, 0.83, 0.12), "_off": (0, 0.01, 0)})
    b = merge(STAND, up, {"_ikR": (-0.36, 0.70, 0.06), "Head": (-4, -6, 6)})
    return loop([(0, a), (6, b), (12, a), (18, b)], n)


@clip("lookAround")
def look_around(n):
    l = merge(STAND, {"Head": (0, 38, 0), "Spine3": (0, 10, 0), "UpperArm_L": (0, 0, 3)})
    r = merge(STAND, {"Head": (0, -38, 0), "Spine3": (0, -10, 0), "UpperArm_R": (0, 0, -3)})
    return loop([(0, STAND), (10, l), (20, l), (28, STAND), (36, r), (44, r)], n)


def sip(base, mouth, head, n):
    cup = merge(base, {"_ikR": mouth, "_poleR": (-1, -0.6, -0.2), "Head": head})
    lift = merge(base, {"_ikR": (mouth[0] - 0.04, mouth[1] - 0.12, mouth[2])})
    return [(0, base), (round(0.2 * n), lift), (round(0.35 * n), cup), (round(0.62 * n), cup), (round(0.85 * n), base),
            (n - 1, base)]


@clip("sitSip")
def sit_sip(n):
    return sip(TYPE, (-0.05, 0.84, 0.21), (-12, 0, 0), n)


@clip("drink")
def drink(n):
    return sip(STAND, (-0.05, 0.68, 0.20), (-14, 0, 0), n)


@clip("sitThink")
def sit_think(n):
    think = merge(SIT, {"_ikR": (-0.06, 0.76, 0.27), "_poleR": (-0.5, -1, 0.3), "_ikL": (0.06, 0.62, 0.20),
                        "Head": (4, -6, 12), "Spine2": (6, 0, 0)})
    hmm = merge(think, {"Head": (8, 6, 6)})
    return [(0, TYPE), (8, think), (24, hmm), (38, think), (n - 1, TYPE)]


def stretch_keys(base, up_y, n):
    # Kollar kısa (0,29 m), kafa iri: eller başın üstünde buluşamaz (kafanın içine girer). yukarı-dışarı V.
    up = merge(base, {"_ikL": (0.31, up_y, -0.01), "_ikR": (-0.31, up_y, -0.01), "Spine2": (-8, 0, 0), "Head": (-14, 0, 0)})
    yawn = merge(up, {"Spine3": (-4, 0, 4), "Head": (-18, 0, -6)})
    return [(0, base), (9, up), (18, yawn), (26, up), (n - 1, base)]


@clip("sitStretch")
def sit_stretch(n):
    return stretch_keys(TYPE, 0.92, n)


@clip("stretch")
def stretch(n):
    return [(f, merge(p, {"_off": (0, 0.018, 0)}) if 0 < f < n - 1 else p) for f, p in stretch_keys(STAND, 0.77, n)]


@clip("waitTap")
def wait_tap(n):
    base = merge(STAND, HIPS, {"Head": (0, 0, 5), "Thigh_R": (-8, 0, 0), "Shin_R": (6, 0, 0)})
    tap = merge(base, {"Foot_R": (-24, 0, 0)})
    return loop([(0, base), (5, tap), (10, base), (15, tap), (20, base)], n)


@clip("cheer")
def cheer(n):
    crouch = merge(STAND, {"Thigh_L": (-20, 0, 0), "Thigh_R": (-20, 0, 0), "Shin_L": (40, 0, 0), "Shin_R": (40, 0, 0),
                           "Foot_L": (-18, 0, 0), "Foot_R": (-18, 0, 0), "Spine1": (10, 0, 0), "_off": (0, -0.035, 0),
                           "_ikL": (0.16, 0.42, 0.10), "_ikR": (-0.16, 0.42, 0.10)})
    up = {"_poleL": (1, -0.4, -0.3), "_poleR": (-1, -0.4, -0.3)}
    air = merge(STAND, up, {"_ikL": (0.33, 0.86, 0.05), "_ikR": (-0.33, 0.86, 0.05), "Spine2": (-6, 0, 0),
                            "Head": (-12, 0, 0), "Shin_L": (16, 0, 0), "Shin_R": (16, 0, 0), "Foot_L": (20, 0, 0),
                            "Foot_R": (20, 0, 0), "_off": (0, 0.10, 0)})
    land = merge(crouch, up, {"_ikL": (0.31, 0.71, 0.08), "_ikR": (-0.31, 0.71, 0.08), "_off": (0, -0.025, 0)})
    hold = merge(STAND, up, {"_ikL": (0.31, 0.75, 0.08), "_ikR": (-0.31, 0.75, 0.08)})
    return [(0, STAND), (4, crouch), (9, air), (14, land), (18, hold), (n - 1, STAND)]


@clip("inspect")
def inspect(n):
    lean = merge(STAND, {"Spine1": (18, 0, 0), "Spine2": (8, 0, 0), "Head": (10, 0, 0), "Shin_L": (8, 0, 0),
                         "Shin_R": (8, 0, 0), "_ikL": (0.10, 0.27, 0.16), "_ikR": (-0.10, 0.27, 0.16)})
    tilt = merge(lean, {"Head": (14, 14, 8)})
    return [(0, STAND), (10, lean), (22, tilt), (32, lean), (n - 1, STAND)]


@clip("sitDown")
def sit_down(n):
    mid = merge(STAND, {"Thigh_L": (-40, 0, 0), "Thigh_R": (-40, 0, 0), "Shin_L": (60, 0, 0), "Shin_R": (60, 0, 0),
                        "Spine1": (12, 0, 0), "_off": (0, 0.10, 0.03)})
    return [(0, STAND), (5, mid), (n - 1, merge(SIT, LAP))]


@clip("standUp")
def stand_up(n):
    return [(f, p) for f, p in reversed([(n - 1 - f, p) for f, p in sit_down(n)])]


@clip("sofaSit")
def sofa_sit(n):
    base = merge(SIT, LAP, {"Spine1": (-10, 0, 0), "Spine2": (-4, 0, 0), "Head": (6, 0, 0)})
    breathe = merge(base, {"Spine2": (-2, 0, 0), "Head": (4, 0, 3), "_off": (0, 0.166, 0.02)})
    return loop([(0, base), (n // 2, breathe)], n)


def desk_strokes(base, points, head, n):
    keys = []
    step = (n - 1) / len(points)
    for i, p in enumerate(points):
        keys.append((round(i * step), merge(base, {"_ikR": p, "Head": head})))
    return keys + [(n - 1, keys[0][1])]


@clip("sitDraw")
def sit_draw(n):
    base = merge(TYPE, {"_ikL": (0.10, 0.60, 0.22)})
    pts = [(-0.06 + 0.035 * math.cos(a), 0.60, 0.25 + 0.03 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 8, endpoint=False)]
    return desk_strokes(base, pts, (14, -4, 0), n)


@clip("sitWrite")
def sit_write(n):
    base = merge(TYPE, {"_ikL": (0.14, 0.60, 0.21)})
    pts = [(-0.11 + 0.015 * i, 0.598 + (0.006 if i % 2 else 0), 0.24 + 0.004 * (i % 3)) for i in range(8)]
    return desk_strokes(base, pts, (12, 2, 0), n)


@clip("sitRead")
def sit_read(n):
    hold = merge(SIT, {"_ikL": (0.075, 0.70, 0.22), "_ikR": (-0.075, 0.70, 0.22), "Head": (14, 0, 0), "Spine2": (5, 0, 0)})
    turn = merge(hold, {"_ikR": (-0.01, 0.74, 0.26)})
    return [(0, TYPE), (8, hold), (26, hold), (32, turn), (38, hold), (n - 1, TYPE)]


@clip("readBook")
def read_book(n):
    hold = merge(STAND, {"_ikL": (0.075, 0.52, 0.19), "_ikR": (-0.075, 0.52, 0.19), "Head": (16, 0, 0), "Spine2": (4, 0, 0)})
    turn = merge(hold, {"_ikR": (-0.01, 0.56, 0.23), "Head": (16, 6, 0)})
    sway = merge(hold, {"Head": (14, -4, 3)})
    return loop([(0, hold), (20, sway), (40, hold), (48, turn), (56, hold)], n)


@clip("playArcade")
def play_arcade(n):
    keys = []
    for i, f in enumerate(range(0, n - 1, 4)):
        j = 0.015 if i % 2 else -0.01
        keys.append((f, merge(STAND, {"_ikL": (0.10 + j * 0.6, 0.47 + j, 0.23), "_ikR": (-0.10, 0.47 - j, 0.23 + j * 0.5),
                                      "Spine1": (6, 0, 0), "Head": (6, 3 * (i % 3 - 1), 0),
                                      "_off": (0, 0.006 if i % 2 else 0, 0)})))
    return loop(keys, n)


@clip("drawBoard")
def draw_board(n):
    pts = [(-0.10 + 0.06 * math.cos(a), 0.74 + 0.05 * math.sin(2 * a), 0.24) for a in np.linspace(0, 2 * math.pi, 6, endpoint=False)]
    base = merge(STAND, {"Spine3": (0, -6, 0), "_poleR": (-1, -0.8, -0.2)})
    return desk_strokes(base, pts, (-4, -8, 0), n)


@clip("stepBackLook")
def step_back_look(n):
    back = merge(STAND, {"Thigh_R": (16, 0, 0), "Shin_R": (10, 0, 0), "Spine1": (-6, 0, 0), "_off": (0, -0.005, -0.06),
                         "_ikR": (-0.03, 0.66, 0.20), "_poleR": (-0.5, -1, 0.3), "_ikL": (0.10, 0.45, 0.14),
                         "Head": (-6, 0, 10)})
    nod = merge(back, {"Head": (6, 0, 6)})
    return [(0, STAND), (10, back), (24, back), (30, nod), (36, back), (n - 1, STAND)]


@clip("brewCoffee")
def brew_coffee(n):
    press = merge(STAND, {"_ikR": (-0.04, 0.62, 0.26), "_poleR": (-1, -1, 0), "Head": (6, 0, 0), "Spine1": (4, 0, 0)})
    wait = merge(STAND, {"_ikL": (0.12, 0.43, 0.20), "_ikR": (-0.12, 0.43, 0.20), "Head": (10, 0, 0), "Spine1": (4, 0, 0)})
    hum = merge(wait, {"Head": (8, 0, 8), "_off": (0, 0.006, 0)})
    return [(0, STAND), (8, press), (14, press), (22, wait), (30, hum), (38, wait), (n - 1, STAND)]


@clip("scratchHead")
def scratch_head(n):
    # Terleme: sağ el başın yanında kaşır, baş o yana eğik, sol el hafif önde.
    up = {"_poleR": (-1, -0.3, -0.4), "Head": (2, -6, 3), "Spine3": (0, -4, 1), "_ikL": (0.15, 0.33, 0.06)}
    a = merge(STAND, up, {"_ikR": (-0.31, 0.77, 0.03)})
    b = merge(STAND, up, {"_ikR": (-0.32, 0.73, 0.05), "Head": (2, -6, 4)})
    return [(0, STAND), (8, a), (14, b), (20, a), (26, b), (32, a), (40, a), (n - 1, STAND)]


@clip("notice")
def notice(n):
    # Fark etme: küçük çömelme, kollar hafif açık zıplama, baş geri.
    crouch = merge(STAND, {"Thigh_L": (-10, 0, 0), "Thigh_R": (-10, 0, 0), "Shin_L": (22, 0, 0), "Shin_R": (22, 0, 0),
                           "Foot_L": (-10, 0, 0), "Foot_R": (-10, 0, 0), "_off": (0, -0.02, 0)})
    air = merge(STAND, {"_ikL": (0.25, 0.45, 0.08), "_ikR": (-0.25, 0.45, 0.08), "Head": (-10, 0, 0), "Spine2": (-4, 0, 0),
                        "Foot_L": (16, 0, 0), "Foot_R": (16, 0, 0), "_off": (0, 0.06, 0)})
    land = merge(crouch, {"_ikL": (0.22, 0.40, 0.08), "_ikR": (-0.22, 0.40, 0.08), "_off": (0, -0.012, 0)})
    return [(0, STAND), (3, crouch), (7, air), (11, land), (n - 1, STAND)]


def export(pack):
    global PACK
    PACK = pack
    for name, n in FRAMES.items():
        if name not in CLIPS:
            continue
        mats = []
        for f in range(n):
            s = acpack.skinning(pack, keys_at(CLIPS[name](n), f))
            mats.append(np.transpose(s, (0, 2, 1)))  # satır -> sütun-öncelikli
        arr = np.array(mats, dtype="<f4").ravel()
        import base64
        pack.data["clips"][name] = {"frames": n, "matrices": base64.b64encode(arr.tobytes()).decode()}
    pack.save()
    print("CLIPS", sorted(pack.data["clips"]), "missing", sorted(set(FRAMES) - set(CLIPS)))


if __name__ == "__main__" and "--" in sys.argv:
    export(acpack.Pack(sys.argv[sys.argv.index("--") + 1]))
