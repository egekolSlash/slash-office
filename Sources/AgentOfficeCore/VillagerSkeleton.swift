import Foundation
import simd

/// Köylünün iskeleti (spec v4 §5): klip + zaman (+ geçiş) → kemik başına skinning matrisi.
/// Klipler 24 fps; dönem (kare − 1) / 24 (son kare ilkine eşittir, RealityKit'teki kırpmayla aynı).
/// Kareler ve geçişler arası dönme quaternion ile, öteleme doğrusal karışır (kemikler katıdır).
public struct VillagerSkeleton: Sendable {
    struct Joint: Sendable {
        var rotation: simd_quatf
        var translation: SIMD3<Float>
    }

    public let boneCount: Int
    /// Klip → kare → kemik.
    private let clips: [AvatarClip: [[Joint]]]

    public init(art: OfficeArtFile) {
        self.init(boneCount: art.bones.count, clips: art.clips)
    }

    /// Kemik ağacı (karakter iskeleti): ebeveyn indeksi (önce ebeveyn gelir, kökte -1) ve dinlenme
    /// pozunun dünya matrisleri.
    public struct Hierarchy: Sendable {
        public var parents: [Int]
        public var rest: [simd_float4x4]
        public init(parents: [Int], rest: [simd_float4x4]) { self.parents = parents; self.rest = rest }
    }

    let hierarchy: Hierarchy?

    /// Kemik sayısı ve klipler (ad → kare × kemik × 16 sütun sıralı matris); karakter paketi de bunu kullanır.
    public init(boneCount: Int, clips raw: [String: ArtClip], hierarchy: Hierarchy? = nil) {
        self.hierarchy = hierarchy
        self.boneCount = boneCount
        var clips: [AvatarClip: [[Joint]]] = [:]
        for clip in AvatarClip.allCases {
            guard let data = raw[clip.rawValue], data.frames > 0,
                  data.matrices.count == data.frames * boneCount * 16 else { continue }
            clips[clip] = (0..<data.frames).map { f in
                let m = data.matrices
                let skin: [simd_float4x4] = (0..<boneCount).map { b in
                    let o = (f * boneCount + b) * 16
                    return simd_float4x4(SIMD4(m[o], m[o + 1], m[o + 2], m[o + 3]), SIMD4(m[o + 4], m[o + 5], m[o + 6], m[o + 7]),
                                         SIMD4(m[o + 8], m[o + 9], m[o + 10], m[o + 11]), SIMD4(m[o + 12], m[o + 13], m[o + 14], m[o + 15]))
                }
                guard let hierarchy else { return skin.map(Self.joint) }
                // Ağaçlı iskelet: ebeveyne göre yerel dönüşüm (karışım bu uzayda kemik boyunu korur).
                let world = zip(skin, hierarchy.rest).map { $0 * $1 }
                return (0..<boneCount).map { b in
                    let p = hierarchy.parents[b]
                    return Self.joint(p >= 0 ? world[p].inverse * world[b] : world[b])
                }
            }
        }
        self.clips = clips
        restInverse = hierarchy?.rest.map(\.inverse) ?? []
    }

    private let restInverse: [simd_float4x4]

    static func joint(_ m: simd_float4x4) -> Joint {
        let basis = simd_float3x3(simd_make_float3(m.columns.0), simd_make_float3(m.columns.1), simd_make_float3(m.columns.2))
        return Joint(rotation: simd_quatf(basis), translation: simd_make_float3(m.columns.3))
    }

    /// Eklemler → skinning matrisleri (ağaçlı iskelette ileri kinematik: dünya · dinlenme⁻¹).
    func skinning(_ joints: [Joint]) -> [simd_float4x4] {
        guard let hierarchy, joints.count == boneCount else { return joints.map(Self.matrix) }
        var world = [simd_float4x4](repeating: matrix_identity_float4x4, count: boneCount)
        for b in 0..<boneCount {
            let p = hierarchy.parents[b]
            world[b] = p >= 0 ? world[p] * Self.matrix(joints[b]) : Self.matrix(joints[b])
        }
        return (0..<boneCount).map { world[$0] * restInverse[$0] }
    }

    static let fps = 24.0

    func joints(clip: AvatarClip, time: Double) -> [Joint] {
        guard let frames = clips[clip] else {
            return Array(repeating: Joint(rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), translation: .zero), count: boneCount)
        }
        guard frames.count > 1 else { return frames[0] }
        let period = Double(frames.count - 1)
        var p: Double
        if clip.loops {
            p = (time * Self.fps).truncatingRemainder(dividingBy: period)
            if p < 0 { p += period }
        } else {
            // Tek seferlik klip bitince son karede kalır (geçiş sırasında başa sarıp ters poza sıçramasın).
            p = min(max(time * Self.fps, 0), period)
        }
        let i = min(Int(p), frames.count - 2)
        return Self.mix(frames[i], frames[i + 1], Float(p - Double(i)))
    }

    /// Geçiş ağırlığı yumuşak başlar ve yumuşak biter (smoothstep).
    static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    static func mix(_ a: [Joint], _ b: [Joint], _ t: Float) -> [Joint] {
        zip(a, b).map { a, b in
            Joint(rotation: simd_slerp(a.rotation, b.rotation, t), translation: a.translation + (b.translation - a.translation) * t)
        }
    }

    static func matrix(_ j: Joint) -> simd_float4x4 {
        var m = simd_float4x4(j.rotation)
        m.columns.3 = SIMD4(j.translation, 1)
        return m
    }

    public func matrices(clip: AvatarClip, time: Double) -> [simd_float4x4] {
        skinning(joints(clip: clip, time: time))
    }

    /// Köylünün o anki pozu: geçiş varsa öncekinden (ya da kesilen geçişin dondurulmuş pozundan) şimdikine.
    public func pose(of a: AvatarInstance) -> [simd_float4x4] {
        skinning(poseJoints(of: a))
    }

    func poseJoints(of a: AvatarInstance) -> [Joint] {
        let current = joints(clip: a.clip, time: a.clipTime)
        guard a.blend < 1 else { return current }
        let from: [Joint]
        if let frozen = a.frozen, frozen.count == boneCount {
            from = frozen
        } else if let previous = a.previousClip {
            from = joints(clip: previous, time: a.previousTime)
        } else {
            return current
        }
        return Self.mix(from, current, Float(Self.ease(a.blend)))
    }
}

/// Çizilecek bir köylünün anlık durumu (instance verisi + animasyon).
public struct AvatarInstance: Sendable {
    public static let fade = 0.25

    public var id: String
    public var position: SIMD3<Float> = .zero
    /// y ekseni etrafında radyan; 0 = +z (kameraya doğru).
    public var facing: Float = 0
    public var clip: AvatarClip
    public var clipTime: Double = 0
    public var previousClip: AvatarClip?
    public var previousTime: Double = 0
    /// 0 → önceki poz, 1 → şimdiki klip.
    public var blend: Double = 1
    /// Geçiş yarıda kesilince o anki karışık poz (sıçramasın diye buradan devam edilir).
    var frozen: [VillagerSkeleton.Joint]?
    public var look: AvatarLook
    /// Doğrusal değil, sRGB (editördeki renklerle aynı).
    public var shirtColor: SIMD3<Float> = SIMD3(0.5, 0.5, 0.5)
    public var waving = false
    /// Şimdiki geçişin süresi (`AvatarClip.fade`).
    public var fadeDuration = AvatarInstance.fade
    /// Dönülecek yön (radyan): köylü bu yöne birkaç karede yumuşakça döner; nil: dönüş yok.
    public var facingGoal: Float?
    /// Klip oynatma hızı (yürüyüş hızlanırken/yavaşlarken ayak kaymasın).
    public var clipRate = 1.0
    /// Beklerken neyi beklediği (izin / soru): ifade, tepki ve efekt buna göre.
    public var waitReason: WaitReason?

    public enum WaitReason: Equatable, Sendable { case permission, question }

    public init(id: String, clip: AvatarClip, look: AvatarLook? = nil) {
        self.id = id
        self.clip = clip
        self.look = look ?? AvatarLook.default(for: id)
    }

    public mutating func play(_ next: AvatarClip, skeleton: VillagerSkeleton) {
        guard next != clip else { return }
        if blend < 1 {
            frozen = skeleton.poseJoints(of: self)
            previousClip = nil
        } else {
            frozen = nil
            previousClip = clip
            previousTime = clipTime
        }
        fadeDuration = AvatarClip.fade(from: clip, to: next)
        clip = next
        clipTime = 0
        blend = 0
        clipRate = 1
    }

    /// Yeni yöne yumuşak dönüş başlat.
    public mutating func turn(to angle: Float) { facingGoal = angle }

    /// Dönüş: kalan açının her saniye ~%99'u (üstel), en fazla 12 rad/sn; en kısa yönden.
    mutating func advanceTurn(dt: Double) {
        guard let goal = facingGoal else { return }
        let delta = remainderf(goal - facing, 2 * .pi)
        if abs(delta) < 0.002 {
            facing = goal
            facingGoal = nil
            return
        }
        let step = delta * Float(1 - exp(-dt * 14))
        let maxStep = Float(12 * dt)
        facing += min(max(step, -maxStep), maxStep)
    }

    public mutating func advance(dt: Double) {
        clipTime += dt * clipRate
        advanceTurn(dt: dt)
        guard blend < 1 else { return }
        previousTime += dt
        blend = min(1, blend + dt / max(fadeDuration, 0.01))
        if blend >= 1 {
            frozen = nil
            previousClip = nil
        }
    }
}
