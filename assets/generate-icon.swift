// Original GameWrap icon. Regenerate: swift assets/generate-icon.swift /tmp/GameWrap.iconset
// Then: iconutil -c icns /tmp/GameWrap.iconset -o assets/AppIcon.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let unit = CGFloat(size) / 32
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: NSColor) {
            color.setFill()
            NSRect(x: CGFloat(x)*unit, y: CGFloat(y)*unit, width: CGFloat(w)*unit, height: CGFloat(h)*unit).fill()
        }
        let paper = NSColor(srgbRed: 0.97, green: 0.95, blue: 0.88, alpha: 1)
        let ink = NSColor(srgbRed: 0.18, green: 0.24, blue: 0.17, alpha: 1)
        let orange = NSColor(srgbRed: 0.95, green: 0.48, blue: 0.18, alpha: 1)
        paper.setFill()
        NSBezierPath(roundedRect: NSRect(x: 2*unit, y: 2*unit, width: 28*unit, height: 28*unit), xRadius: 6*unit, yRadius: 6*unit).fill()
        box(20, 21, 5, 5, orange)
        box(19, 22, 7, 3, orange)
        box(8, 10, 16, 9, ink)
        box(6, 8, 5, 9, ink)
        box(21, 8, 5, 9, ink)
        box(9, 14, 6, 2, paper)
        box(11, 12, 2, 6, paper)
        box(19, 15, 2, 2, orange)
        box(22, 12, 2, 2, orange)
        box(15, 5, 2, 3, ink)
        box(17, 7, 3, 1, ink)
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
