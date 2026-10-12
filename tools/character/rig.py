# İskelet (21 kemik, kendi adlarımız, dinlenme T-pozu) ve deri ağırlıkları: karakter ve kıyafet paketleri ortak.
# Blender'a bağlı değil (numpy).
import base64, struct

import numpy as np

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
def b64(fmt, values):
    return base64.b64encode(struct.pack("<%d%s" % (len(values), fmt), *values)).decode()


def mesh_json(mesh, region, normals=None):
    """Mesh → paket kaydı (base64 diziler); köşe başına en fazla 4 kemik, ağırlıklar u8 (toplam 255)."""
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
    return {"vertexCount": len(mesh.p), "positions": b64("f", mesh.p.ravel().tolist()),
            "normals": b64("f", n.ravel().tolist()), "uvs": b64("f", mesh.uv.ravel().tolist()),
            "joints": b64("B", joints), "weights": b64("B", wts), "indices": b64("I", mesh.f.ravel().tolist()),
            "triangles": mesh.triangles}
