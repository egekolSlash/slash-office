# Karakter paketini (character.json) okuma + FK/skinning (numpy). Blender'a bağlı değil (clips.py ve preview.py kullanır).
import base64, json, math
import numpy as np


class Pack:
    def __init__(self, path):
        self.path = path
        self.data = json.load(open(path))
        self.bones = self.data["bones"]
        self.index = {n: i for i, n in enumerate(self.bones)}
        self.parents = self.data["parents"]
        rest = np.frombuffer(base64.b64decode(self.data["rest"]), dtype="<f4").reshape(-1, 4, 4)
        self.rest = np.transpose(rest, (0, 2, 1)).astype(np.float64)  # sütun-öncelikli -> satır
        self.joint = self.rest[:, :3, 3].copy()

    def mesh(self, mid):
        m = self.data["meshes"][mid]
        arr = lambda k, t, n: np.frombuffer(base64.b64decode(m[k]), dtype=t).reshape(-1, n)
        return {"positions": arr("positions", "<f4", 3).astype(np.float64), "normals": arr("normals", "<f4", 3),
                "uvs": arr("uvs", "<f4", 2), "joints": arr("joints", "u1", 4).astype(np.int64),
                "weights": arr("weights", "u1", 4).astype(np.float64) / 255.0,
                "indices": np.frombuffer(base64.b64decode(m["indices"]), dtype="<u4").reshape(-1, 3)}

    def save(self):
        json.dump(self.data, open(self.path, "w"))


# ---------------------------------------------------------------- dönüşler
def euler(x=0.0, y=0.0, z=0.0):
    """Derece; model eksenleri (Y yukarı, Z ileri, X karakterin solu). R = Ry · Rx · Rz."""
    x, y, z = (math.radians(a) for a in (x, y, z))
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return ry @ rx @ rz


def quat(m):
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def quat_matrix(q):
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        q = a + (b - a) * t
        return q / np.linalg.norm(q)
    th = math.acos(d)
    return (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)


# ---------------------------------------------------------------- poz -> skinning
class Pose:
    """Kemik başına dönüş (3x3, model eksenlerinde, ebeveynin pozlu çerçevesine göre) + kalça ötelemesi +
    isteğe bağlı kol IK hedefleri: ik[side] = (el hedefi, dirsek yönü), model uzayında (metre)."""
    def __init__(self, rot=None, offset=(0.0, 0.0, 0.0), ik=None):
        self.rot = rot or {}
        self.offset = np.array(offset, dtype=np.float64)
        self.ik = ik or {}


def align(a, b):
    """a'yı b'ye döndüren en küçük dönüş (birim vektörler)."""
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v, c = np.cross(a, b), float(np.dot(a, b))
    if c < -0.9999:
        axis = np.cross(a, [0, 1, 0] if abs(a[1]) < 0.9 else [1, 0, 0])
        axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1 + c)


def two_bone(s, t, l1, l2, pole):
    """Omuz s, hedef t: (üst kol yönü, ön kol yönü) dünya uzayında; dirsek pole tarafına."""
    d = t - s
    dist = float(np.clip(np.linalg.norm(d), abs(l1 - l2) + 1e-4, l1 + l2 - 1e-4))
    dirv = d / (np.linalg.norm(d) or 1)
    pp = pole - np.dot(pole, dirv) * dirv
    pp = pp / (np.linalg.norm(pp) or 1)
    a = math.acos(float(np.clip((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)))
    e = s + l1 * (math.cos(a) * dirv + math.sin(a) * pp)
    t2 = s + dirv * dist
    return (e - s) / l1, (t2 - e) / np.linalg.norm(t2 - e)


def skinning(pack, pose, translate_bone="Hips", resolved=None):
    """S_b = S_parent · T(j_b) · D_b · T(-j_b); öteleme `translate_bone`'da. Satır-öncelikli 4x4 dizisi.
    `resolved` sözlüğü verilirse IK'nin çözdüğü kol dönüşleri (UpperArm_*, ForeArm_*) oraya yazılır."""
    n = len(pack.bones)
    out = np.zeros((n, 4, 4))
    tb = pack.index[translate_bone]
    pending = {}
    for b in range(n):  # ebeveynler önce gelir (Collada sırası)
        local = np.eye(4)
        name = pack.bones[b]
        d = pose.rot.get(name)
        side = name[-1]
        if name in ("UpperArm_L", "UpperArm_R") and side in pose.ik:
            target, pole = pose.ik[side]
            j1, j2, jh = (pack.joint[pack.index[k + "_" + side]] for k in ("UpperArm", "ForeArm", "Hand"))
            parent = out[pack.parents[b]]
            rp = parent[:3, :3]
            s = (parent @ np.r_[j1, 1])[:3]
            u, f = two_bone(s, np.asarray(target, float), np.linalg.norm(j2 - j1), np.linalg.norm(jh - j2), np.asarray(pole, float))
            d = align(j2 - j1, rp.T @ u)
            pending["ForeArm_" + side] = align(jh - j2, (rp @ d).T @ f)
            if resolved is not None:
                resolved[name] = d
        elif name in pending:
            d = pending.pop(name)
            if resolved is not None:
                resolved[name] = d
        if d is not None:
            j = pack.joint[b]
            local[:3, :3] = d
            local[:3, 3] = j - d @ j
        if b == tb:
            local[:3, 3] += pose.offset
        p = pack.parents[b]
        out[b] = (out[p] if p >= 0 else np.eye(4)) @ local
    return out


def skin_vertices(mesh, mats):
    p = np.c_[mesh["positions"], np.ones(len(mesh["positions"]))]
    out = np.zeros((len(p), 3))
    for k in range(4):
        m = mats[mesh["joints"][:, k]]                     # (v, 4, 4)
        out += mesh["weights"][:, k:k + 1] * np.einsum("vij,vj->vi", m, p)[:, :3]
    return out
