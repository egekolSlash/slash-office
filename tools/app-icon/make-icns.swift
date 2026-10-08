// Kare kaynak resimden macOS uygulama ikonu: Apple ikon ızgarası (1024'te 824'lük, köşe yarıçapı ~185 yuvarlatılmış kare)
// ve hafif gölge. Kullanım: swift tools/app-icon/make-icns.swift <kaynak.png> <çıktı.iconset>
import AppKit

let args = CommandLine.arguments
let source = NSImage(contentsOfFile: args[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 100 / 1024, side = s * 824 / 1024
    let rect = CGRect(x: inset, y: inset + s * 6 / 1024, width: side, height: side)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 8 / 1024), blur: s * 18 / 1024,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.05, alpha: 1)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0)
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(source, in: rect)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
