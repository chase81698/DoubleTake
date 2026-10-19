// Draws Resources/dmg-background.tiff, the picture behind the icons in DoubleTake.dmg.
// Run: swift scripts/make-dmg-background.swift
// The icon positions in scripts/make-dmg.sh line up with the arrow drawn here.
import AppKit

let width: CGFloat = 640, height: CGFloat = 420

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(starting: NSColor(red: 0.97, green: 0.97, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.90, green: 0.90, blue: 0.97, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
        ]
        NSAttributedString(string: string, attributes: attributes)
            .draw(in: NSRect(x: 30, y: height - y - size * 1.3, width: width - 60, height: size * 2.8))
    }
    let ink = NSColor(red: 0.13, green: 0.13, blue: 0.2, alpha: 1)
    let muted = NSColor(red: 0.36, green: 0.36, blue: 0.45, alpha: 1)
    text("Drag DoubleTake into Applications", size: 22, weight: .semibold, color: ink, y: 34)

    // Arrow from the app (x 170) to Applications (x 470); icons sit centred at y 185 from the top.
    let accent = NSColor(red: 0.45, green: 0.36, blue: 0.97, alpha: 1)
    accent.setStroke()
    accent.setFill()
    let y = height - 185
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: y))
    shaft.line(to: NSPoint(x: 362, y: y))
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 382, y: y))
    head.line(to: NSPoint(x: 356, y: y + 17))
    head.line(to: NSPoint(x: 356, y: y - 17))
    head.close()
    head.fill()

    text("Then open DoubleTake from Applications. If macOS says it can’t check the app for malicious software,",
         size: 12, weight: .regular, color: muted, y: 318)
    text("open System Settings › Privacy & Security, scroll down and click Open Anyway.",
         size: 12, weight: .regular, color: muted, y: 336)
    text("DoubleTake asks once for Input Monitoring, which only lets it see your shortcut keys.",
         size: 12, weight: .regular, color: muted, y: 366)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("Resources/dmg-background.tiff")
// One TIFF holding the 1x and 2x pictures, so Finder stays sharp on Retina screens.
let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try tiff.write(to: out)
print("Wrote \(out.path)")
