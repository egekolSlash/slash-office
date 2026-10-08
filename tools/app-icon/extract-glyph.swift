// Koyu zeminli kaynak resimden "/o" katmanı: parlaklıktan alfa çıkarılır, glif 1024'lük şeffaf tuvalde
// `width` genişliğe büyütülür ve göz için `lift` kadar yukarı alınır (alttaki mavi kalınlık glifi aşağıda gösterir).
// Kullanım: swift tools/app-icon/extract-glyph.swift <kaynak.png> <çıktı.png> [width=0.62] [lift=0.025]
import AppKit

let args = CommandLine.arguments
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[1])))!
let width = args.count > 3 ? Double(args[3])! : 0.62, lift = args.count > 4 ? Double(args[4])! : 0.025
let w = rep.pixelsWide, h = rep.pixelsHigh
var minX = w, maxX = 0, minY = h, maxY = 0
var pixels = [UInt8](repeating: 0, count: w * h * 4)
func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
for y in 0..<h {
    for x in 0..<w {
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        let a = smooth(0.17, 0.32, c.brightnessComponent)
        let i = (y * w + x) * 4
        // Kenarda zeminle karışan renk: koyu zemini çıkarıp aydınlat (alfa ile ön çarpımlı).
        pixels[i] = UInt8(min(255, c.redComponent * 255 * a / max(a, 0.001) * a))
        pixels[i + 1] = UInt8(min(255, c.greenComponent * 255 * a))
        pixels[i + 2] = UInt8(min(255, c.blueComponent * 255 * a))
        pixels[i + 3] = UInt8(a * 255)
        if a > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    }
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let full = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
// colorAt'in y'si yukarıdan; CGImage kırpması da yukarıdan.
let pad = 6
let crop = full.cropping(to: CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad))!
let S = 1024.0
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
let gw = S * width, gh = gw * Double(crop.height) / Double(crop.width)
ctx.draw(crop, in: CGRect(x: (S - gw) / 2, y: (S - gh) / 2 + S * lift, width: gw, height: gh))
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: args[2]))
