// Draws Magpie's app icon: stacked clipboard cards on a magpie-feather gradient, with a sparkle
// for the shiny thing it collected. Run: swift docs/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // Body: the standard macOS icon shape, 824pt with a 100pt margin.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: hex(0x000000, 0.35).cgColor)
    hex(0x1A1446).setFill()
    body.fill()
    ctx.restoreGState()

    // Iridescent blue-violet to teal, like a magpie's tail feathers.
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [hex(0x2B1A78), hex(0x1E4FB0), hex(0x0E9C9A)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: body, angle: -55)
    // Soft light from the top.
    NSGradient(colors: [hex(0xFFFFFF, 0.18), hex(0xFFFFFF, 0)])!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Cards, back to front.
    func card(angle: CGFloat, dx: CGFloat, dy: CGFloat, alpha: CGFloat, front: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: 512 + dx, y: 470 + dy)
        ctx.rotate(by: angle * .pi / 180)
        let rect = NSRect(x: -190, y: -235, width: 380, height: 470)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 44, yRadius: 44)
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: hex(0x0A0730, 0.45).cgColor)
        hex(0xFFFFFF, alpha).setFill()
        shape.fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        if front {
            // An image thumbnail and three lines of text.
            let thumb = NSBezierPath(roundedRect: NSRect(x: -140, y: 55, width: 280, height: 130), xRadius: 22, yRadius: 22)
            NSGradient(colors: [hex(0x7FD4C8), hex(0x3D7BE0)])!.draw(in: thumb, angle: -30)
            for (i, width) in [280.0, 230, 160].enumerated() {
                hex(0x2B2F6B, 0.22).setFill()
                NSBezierPath(roundedRect: NSRect(x: -140, y: -15 - CGFloat(i) * 62, width: width, height: 30),
                             xRadius: 15, yRadius: 15).fill()
            }
        }
        ctx.restoreGState()
    }
    card(angle: 14, dx: 70, dy: 30, alpha: 0.35, front: false)
    card(angle: 6, dx: 34, dy: 14, alpha: 0.6, front: false)
    card(angle: -4, dx: -10, dy: -8, alpha: 1, front: true)

    // The sparkle: a four-point star with a glow.
    func star(center: CGPoint, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<8 {
            let r = i.isMultiple(of: 2) ? radius : radius * 0.22
            let a = CGFloat(i) * .pi / 4 + .pi / 2
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        return path
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: hex(0xFFD86B, 0.9).cgColor)
    let big = star(center: CGPoint(x: 700, y: 735), radius: 120)
    NSGraphicsContext.saveGraphicsState()
    big.addClip()
    NSGradient(colors: [hex(0xFFF6D6), hex(0xFFC53D)])!.draw(in: big.bounds, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    hex(0xFFF3C4).setFill()
    star(center: CGPoint(x: 812, y: 625), radius: 46).fill()
    ctx.restoreGState()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
