import AgentOfficeCore
import CoreGraphics

/// Swift ile çizilen desen dokuları (v3 spec §2): zemin, duvar kâğıdı, lambri, halı, çimen, toprak, patika ve tişört.
/// Renkli desenler (parke, duvar kâğıdı) kendi rengini taşır; halı ve tişört beyaz-gri desendir, rengi köşe ya da
/// instance renginden (tint) gelir. Katman numaraları `OfficeTextureLayer` (Core) ile aynıdır.
enum OfficePatterns {
    static let size = 256

    /// Doku dizisinin bir katmanı (0: düz beyaz).
    static func image(layer: Int) -> CGImage {
        let s = size
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(layer: layer, ctx, s)
        return ctx.makeImage()!
    }

    static func draw(layer: Int, _ ctx: CGContext, _ s: Int) {
        let L = OfficeTextureLayer.self
        for i in 0..<RoomStyle.floorCount where layer == Int(L.floor(i)) {
            switch i {
            case 0: planks(ctx, s, light: (0.86, 0.62, 0.38), dark: (0.78, 0.54, 0.31))
            case 1: planks(ctx, s, light: (0.55, 0.36, 0.22), dark: (0.48, 0.30, 0.18))
            default: checks(ctx, s, (0.97, 0.93, 0.84), (0.86, 0.55, 0.40), count: 2)
            }
            return
        }
        for i in 0..<RoomStyle.wallpaperCount where layer == Int(L.wallpaper(i)) {
            switch i {
            case 0: stripes(ctx, s, (0.99, 0.94, 0.82), (0.96, 0.86, 0.70), count: 8, vertical: true)
            case 1: stripes(ctx, s, (0.86, 0.96, 0.90), (0.76, 0.90, 0.82), count: 8, vertical: true)
            case 2: dots(ctx, s, base: (0.99, 0.86, 0.88), dot: (1, 1, 1), count: 4)
            case 3: fill(ctx, s, (0.84, 0.92, 0.99)); grid(ctx, s, (0.78, 0.87, 0.96), count: 4)
            default: checks(ctx, s, (1.0, 0.95, 0.75), (0.99, 0.89, 0.62), count: 4)
            }
            return
        }
        for p in RoomStyle.RugPattern.allCases where layer == Int(L.rug(p)) {
            switch p {
            case .dots: dots(ctx, s, base: (0.82, 0.82, 0.82), dot: (1, 1, 1), count: 5)
            case .stripes: stripes(ctx, s, (1, 1, 1), (0.78, 0.78, 0.78), count: 6, vertical: false)
            case .plain: fill(ctx, s, (0.92, 0.92, 0.92))
            }
            return
        }
        for p in AvatarLook.ShirtPattern.allCases where layer == Int(L.shirt(p)) {
            switch p {
            case .plain: fill(ctx, s, (1, 1, 1))
            case .stripes: stripes(ctx, s, (1, 1, 1), (0.72, 0.72, 0.72), count: 8, vertical: false)
            case .dots: dots(ctx, s, base: (1, 1, 1), dot: (0.70, 0.70, 0.70), count: 6)
            }
            return
        }
        switch UInt16(layer) {
        case L.wainscot: stripes(ctx, s, (0.62, 0.42, 0.26), (0.56, 0.37, 0.23), count: 6, vertical: true)
        case L.grass: speckle(ctx, s, base: (0.40, 0.74, 0.30), spots: [(0.34, 0.68, 0.26), (0.47, 0.80, 0.34)], seed: 7)
        case L.dirt: speckle(ctx, s, base: (0.62, 0.42, 0.26), spots: [(0.56, 0.37, 0.22)], seed: 3)
        case L.path: speckle(ctx, s, base: (0.92, 0.89, 0.82), spots: [(0.86, 0.83, 0.76)], seed: 11)
        default: fill(ctx, s, (1, 1, 1))
        }
    }

    typealias RGB = (Double, Double, Double)
    static func set(_ ctx: CGContext, _ c: RGB) { ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: 1) }

    static func fill(_ ctx: CGContext, _ s: Int, _ c: RGB) {
        set(ctx, c); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    }

    static func stripes(_ ctx: CGContext, _ s: Int, _ a: RGB, _ b: RGB, count: Int, vertical: Bool) {
        fill(ctx, s, a); set(ctx, b)
        let w = CGFloat(s) / CGFloat(count * 2)
        for i in 0..<count {
            let o = CGFloat(i * 2 + 1) * w
            ctx.fill(vertical ? CGRect(x: o, y: 0, width: w, height: CGFloat(s)) : CGRect(x: 0, y: o, width: CGFloat(s), height: w))
        }
    }

    static func dots(_ ctx: CGContext, _ s: Int, base: RGB, dot: RGB, count: Int) {
        fill(ctx, s, base); set(ctx, dot)
        let step = CGFloat(s) / CGFloat(count), r = step * 0.16
        for i in 0..<count {
            for j in 0..<count {
                let offset = j % 2 == 0 ? 0 : step / 2
                ctx.fillEllipse(in: CGRect(x: CGFloat(i) * step + step / 2 + offset - r, y: CGFloat(j) * step + step / 2 - r, width: 2 * r, height: 2 * r))
            }
        }
    }

    static func checks(_ ctx: CGContext, _ s: Int, _ a: RGB, _ b: RGB, count: Int) {
        fill(ctx, s, a); set(ctx, b)
        let step = CGFloat(s) / CGFloat(count)
        for i in 0..<count {
            for j in 0..<count where (i + j) % 2 == 1 {
                ctx.fill(CGRect(x: CGFloat(i) * step, y: CGFloat(j) * step, width: step, height: step))
            }
        }
    }

    static func grid(_ ctx: CGContext, _ s: Int, _ c: RGB, count: Int) {
        set(ctx, c)
        let step = CGFloat(s) / CGFloat(count)
        for i in 0..<count {
            ctx.fill(CGRect(x: CGFloat(i) * step, y: 0, width: 2, height: CGFloat(s)))
            ctx.fill(CGRect(x: 0, y: CGFloat(i) * step, width: CGFloat(s), height: 2))
        }
    }

    /// Parke: dört tahta, iki ton, tahta araları ince koyu çizgi, ekler kaydırmalı.
    static func planks(_ ctx: CGContext, _ s: Int, light: RGB, dark: RGB) {
        let w = CGFloat(s) / 4
        for i in 0..<4 {
            set(ctx, i % 2 == 0 ? light : dark)
            ctx.fill(CGRect(x: CGFloat(i) * w, y: 0, width: w, height: CGFloat(s)))
            set(ctx, (dark.0 * 0.8, dark.1 * 0.8, dark.2 * 0.8))
            ctx.fill(CGRect(x: CGFloat(i) * w, y: 0, width: 2, height: CGFloat(s)))
            ctx.fill(CGRect(x: CGFloat(i) * w, y: CGFloat((i * 97) % s), width: w, height: 2))
        }
    }

    /// Benekli yüzey (çimen, toprak, taş): sabit tohumlu küçük daireler.
    static func speckle(_ ctx: CGContext, _ s: Int, base: RGB, spots: [RGB], seed: UInt64) {
        fill(ctx, s, base)
        var state = seed
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
        }
        for _ in 0..<260 {
            set(ctx, spots[Int(next() * CGFloat(spots.count)) % spots.count])
            let r = 3 + next() * 9
            ctx.fillEllipse(in: CGRect(x: next() * CGFloat(s) - r, y: next() * CGFloat(s) - r, width: 2 * r, height: 2 * r))
        }
    }
}
