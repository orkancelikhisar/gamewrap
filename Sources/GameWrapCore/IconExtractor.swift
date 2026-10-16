import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct IconExtractor: Sendable {
    let runner: ProcessRunner

    public init(runner: ProcessRunner) {
        self.runner = runner
    }

    /// The largest icon embedded in the exe, re-encoded as PNG, or nil if it has none.
    public static func largestIconPNG(exe: URL) -> Data? {
        guard let pe = try? PEFile(url: exe),
              let group = pe.resources(ofType: PEFile.rtGroupIcon).first?.data,
              let count = group.u16(4) else { return nil }
        let images = Dictionary(pe.resources(ofType: PEFile.rtIcon).map { ($0.id, $0.data) }, uniquingKeysWith: { first, _ in first })

        var best: (width: Int, id: UInt32)?
        for i in 0..<Int(count) {
            let entry = 6 + 14 * i
            guard let id = group.u16(entry + 12) else { break }
            let raw = Int(group[group.startIndex + entry])
            let width = raw == 0 ? 256 : raw
            if images[UInt32(id)] != nil, width > (best?.width ?? 0) { best = (width, UInt32(id)) }
        }
        guard let best, let raw = images[best.id], let image = decodeIcon(raw, width: best.width) else { return nil }
        return pngData(image)
    }

    public func makeICNS(fromImageData data: Data, to output: URL) async throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw GameWrapError.invalidIcon }
        try await writeICNS(Self.padded(image), to: output)
    }

    public func makeGenericICNS(name: String, to output: URL) async throws {
        try await writeICNS(Self.genericCanvas(name: name), to: output)
    }

    private func writeICNS(_ canvas: CGImage, to output: URL) async throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("gamewrap-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        for size in [16, 32, 128, 256, 512] {
            try Self.writePNG(Self.resized(canvas, to: size), to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
            try Self.writePNG(Self.resized(canvas, to: size * 2), to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
        try await runner.run(Tool.iconutil, ["-c", "icns", iconset.path, "-o", output.path])
    }

    static func decodeIcon(_ raw: Data, width: Int) -> CGImage? {
        var file = raw
        if !raw.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            // A BMP-style icon image: wrap it in a one-entry .ico so ImageIO can decode it.
            var header = Data(count: 22)
            header.put16(2, 1)
            header.put16(4, 1)
            header[6] = UInt8(width >= 256 ? 0 : width)
            header[7] = header[6]
            header.put16(10, 1)
            header.put16(12, 32)
            header.put32(14, UInt32(raw.count))
            header.put32(18, 22)
            file = header + raw
        }
        guard let source = CGImageSourceCreateWithData(file as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let data = pngData(image) else { throw GameWrapError.invalidIcon }
        try data.write(to: url)
    }

    private static func context(_ size: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Places the image inside the macOS icon grid: 824 px artwork on a 1024 px canvas.
    static func padded(_ image: CGImage) -> CGImage {
        let ctx = context(1024)
        ctx.draw(image, in: CGRect(x: 100, y: 100, width: 824, height: 824))
        return ctx.makeImage()!
    }

    private static func resized(_ image: CGImage, to size: Int) -> CGImage {
        let ctx = context(size)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    /// A rounded square with the game's initial, in a colour chosen from the name.
    static func genericCanvas(name: String) -> CGImage {
        let palette: [(CGFloat, CGFloat, CGFloat)] = [(0.20, 0.47, 0.96), (0.56, 0.27, 0.86), (0.93, 0.36, 0.25),
                                                      (0.12, 0.64, 0.47), (0.95, 0.62, 0.13), (0.85, 0.22, 0.48)]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        let (r, g, b) = palette[hash % palette.count]
        let ctx = context(1024)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fillPath()

        let letter = String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 480, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: letter, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: 512 - bounds.midX, y: 512 - bounds.midY)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }
}
