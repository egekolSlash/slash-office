# Klip denetimi: her klipte ve klipler arası geçişlerde (çalışma anının ebeveyn uzaylı karışımı) el-el, el-kafa,
# el-gövde çakışması ve kol sıçraması. Blender -b --factory-startup --python tools/character/probe.py -- <character.json> tools/character
import sys, base64, json, math
argv = sys.argv[sys.argv.index("--") + 1:]
sys.path.insert(0, argv[1])
import numpy as np
import pack as acpack

pack = acpack.Pack(argv[0])
B = pack.index
nb = len(pack.bones)
clips = {}
for name, c in pack.data["clips"].items():
    m = np.frombuffer(base64.b64decode(c["matrices"]), dtype="<f4").reshape(c["frames"], nb, 4, 4)
    clips[name] = np.transpose(m, (0, 1, 3, 2)).astype(np.float64)  # satır-öncelikli

def joint_world(S, b):
    return (S[b] @ np.r_[pack.joint[b], 1])[:3]

def decompose(M):
    return acpack.quat(M[:3, :3]), M[:3, 3].copy()

def runtime_mix(Sa, Sb, t):
    """VillagerSkeleton.mix: kemik başına skinning matrisinin dönüşü slerp, ötelemesi lerp."""
    out = np.zeros_like(Sa)
    for b in range(nb):
        qa, ta = decompose(Sa[b]); qb, tb = decompose(Sb[b])
        out[b] = np.eye(4)
        out[b][:3, :3] = acpack.quat_matrix(acpack.slerp(qa, qb, t))
        out[b][:3, 3] = ta + (tb - ta) * t
    return out

L1 = {s: np.linalg.norm(pack.joint[B["ForeArm_" + s]] - pack.joint[B["UpperArm_" + s]]) for s in "LR"}
L2 = {s: np.linalg.norm(pack.joint[B["Hand_" + s]] - pack.joint[B["ForeArm_" + s]]) for s in "LR"}

def metrics(S):
    hand = {s: joint_world(S, B["Hand_" + s]) for s in "LR"}
    sh = {s: joint_world(S, B["UpperArm_" + s]) for s in "LR"}
    el = {s: joint_world(S, B["ForeArm_" + s]) for s in "LR"}
    # Gövde ekseni: Spine1 → Neck.
    a, b = joint_world(S, B["Spine1"]), joint_world(S, B["Neck"])
    def axis_dist(p):
        d = b - a; t = np.clip(np.dot(p - a, d) / np.dot(d, d), 0, 1)
        return np.linalg.norm(p - (a + t * d)), t
    out = {"handgap": np.linalg.norm(hand["L"] - hand["R"])}
    # El kafanın içinde mi: baş elipsoidi (dinlenme: merkez (0, 0.84, -0.03), yarıçap 0.25/0.23/0.23), başın pozlu çerçevesinde.
    inv = np.linalg.inv(S[B["Head"]])
    for s in "LR":
        q = (inv @ np.r_[hand[s], 1])[:3] - np.array([0, 0.845, -0.03])
        out["head" + s] = float(np.sum((q / np.array([0.272, 0.236, 0.25])) ** 2))
    for s in "LR":
        dist, t = axis_dist(hand[s])
        out["torso" + s] = dist if 0.02 < t < 0.98 else 9
        out["elbowTorso" + s] = axis_dist(el[s])[0]
        out["len" + s] = abs(np.linalg.norm(el[s] - sh[s]) - L1[s]) + abs(np.linalg.norm(hand[s] - el[s]) - L2[s])
        out["upper" + s] = (el[s] - sh[s]) / L1[s]
    return out

print("== klip içi: el-el < 0.075, el gövdeye < 0.10, dirsek gövdeye < 0.08, dirsek sıçraması > 25°/kare")
for name, frames in sorted(clips.items()):
    issues = []
    prev = None
    for f in range(len(frames)):
        m = metrics(frames[f])
        if m["handgap"] < 0.075: issues.append(f"f{f} el-el {m['handgap']:.3f}")
        for s in "LR":
            if m["torso" + s] < 0.10: issues.append(f"f{f} el{s}-gövde {m['torso' + s]:.3f}")
            if m["elbowTorso" + s] < 0.08: issues.append(f"f{f} dirsek{s}-gövde {m['elbowTorso' + s]:.3f}")
            if m["head" + s] < 1.0: issues.append(f"f{f} el{s} kafada")
            if prev is not None:
                ang = math.degrees(math.acos(np.clip(np.dot(m["upper" + s], prev["upper" + s]), -1, 1)))
                if ang > 25: issues.append(f"f{f} kol{s} sıçrama {ang:.0f}°")
        prev = m
    print(f"{name:13s}", "OK" if not issues else f"{len(issues)} sorun: " + "; ".join(issues[:6]))

def local_mix(Sa, Sb, t):
    """Yeni çalışma anı: W = S·Rest, yerel = W_p⁻¹·W; yerel dönüş slerp + öteleme lerp; FK; S = W·Rest⁻¹."""
    def locals_(S):
        W = S @ pack.rest
        return [np.linalg.inv(W[p]) @ W[b] if p >= 0 else W[b] for b, p in enumerate(pack.parents)]
    la, lb = locals_(Sa), locals_(Sb)
    W = np.zeros_like(Sa)
    for b, p in enumerate(pack.parents):
        qa, ta = decompose(la[b]); qb, tb = decompose(lb[b])
        L = np.eye(4); L[:3, :3] = acpack.quat_matrix(acpack.slerp(qa, qb, t)); L[:3, 3] = ta + (tb - ta) * t
        W[b] = W[p] @ L if p >= 0 else L
    return W @ np.linalg.inv(pack.rest)


print("\n== yeni karışımla geçişler (t=.25/.5/.75): el-el, el-kafa, el-gövde sorunları")
from itertools import product
names = sorted(clips)
bad = 0
for a, b in product(names, names):
    if a == b: continue
    for t in (0.25, 0.5, 0.75):
        m = metrics(local_mix(clips[a][-1], clips[b][0], t))
        probs = [k for k in ("L", "R") if m["head" + k] < 1.0 or m["torso" + k] < 0.10] + (["el-el"] if m["handgap"] < 0.075 else [])
        if probs:
            bad += 1; print(f"  {a} → {b} t={t}: {probs}"); break
print("sorunlu geçiş:", bad, "/", len(names) * (len(names) - 1))
