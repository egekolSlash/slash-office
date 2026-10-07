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
        boneCount = art.bones.count
        var clips: [AvatarClip: [[Joint]]] = [:]
        for clip in AvatarClip.allCases {
            guard let data = art.clips[clip.rawValue], data.frames > 0,
                  data.matrices.count == data.frames * art.bones.count * 16 else { continue }
            clips[clip] = (0..<data.frames).map { f in
                (0..<art.bones.count).map { b in
                    let o = (f * art.bones.count + b) * 16
                    let m = data.matrices
                    let basis = simd_float3x3(SIMD3(m[o], m[o + 1], m[o + 2]), SIMD3(m[o + 4], m[o + 5], m[o + 6]),
                                              SIMD3(m[o + 8], m[o + 9], m[o + 10]))
                    return Joint(rotation: simd_quatf(basis), translation: SIMD3(m[o + 12], m[o + 13], m[o + 14]))
                }
            }
        }
        self.clips = clips
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
        joints(clip: clip, time: time).map(Self.matrix)
    }

    /// Köylünün o anki pozu: geçiş varsa öncekinden (ya da kesilen geçişin dondurulmuş pozundan) şimdikine.
    public func pose(of a: AvatarInstance) -> [simd_float4x4] {
        poseJoints(of: a).map(Self.matrix)
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
        return Self.mix(from, current, Float(a.blend))
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
        clip = next
        clipTime = 0
        blend = 0
    }

    public mutating func advance(dt: Double) {
        clipTime += dt
        guard blend < 1 else { return }
        previousTime += dt
        blend = min(1, blend + dt / Self.fade)
        if blend >= 1 {
            frozen = nil
            previousClip = nil
        }
    }
}
