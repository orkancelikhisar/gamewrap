import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import GameWrapCore

extension XCTestCase {
    /// A fresh directory under the temporary folder, deleted after the test.
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gwtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

/// Records every call. By default it does just enough work (copies, output files)
/// for later build steps to find what they expect.
final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let tool: String
        let args: [String]
    }

    typealias Handler = @Sendable (String, [String]) async throws -> ProcessResult

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let handler: Handler

    var calls: [Call] {
        lock.withLock { recorded }
    }

    init(handler: @escaping Handler = FakeProcessRunner.realisticHandler) {
        self.handler = handler
    }

    func run(_ tool: String, _ args: [String], cwd: URL?, env: [String: String]?) async throws -> ProcessResult {
        lock.withLock { recorded.append(Call(tool: tool, args: args)) }
        return try await handler(tool, args)
    }

    static let realisticHandler: Handler = { tool, args in
        let fm = FileManager.default
        switch tool {
        case Tool.ditto:
            try fm.copyItem(at: URL(fileURLWithPath: args[0]), to: URL(fileURLWithPath: args[1]))
        case Tool.hdiutil where args.first == "create":
            fm.createFile(atPath: args[args.count - 1], contents: Data("dmg".utf8))
        case Tool.iconutil:
            if let i = args.firstIndex(of: "-o") { fm.createFile(atPath: args[i + 1], contents: Data("icns".utf8)) }
        default:
            break
        }
        return ProcessResult(status: 0, output: "")
    }
}

/// Builds minimal but valid PE files: headers plus an optional .rsrc section.
/// `resources` maps resource type → (resource id → bytes). Every entry gets language 0x409.
enum PEBuilder {
    static let sectionRVA: UInt32 = 0x1000
    static let rawPointer = 0x200

    static func make(machine: UInt16 = 0x8664, pe32: Bool = false, resources: [UInt32: [UInt32: Data]] = [:]) -> Data {
        let rsrc = resources.isEmpty ? Data() : resourceSection(resources)
        var d = Data(count: rawPointer)
        d.put16(0, 0x5A4D)                    // "MZ"
        d.put32(0x3C, 64)                     // e_lfanew
        d.put32(64, 0x0000_4550)              // "PE\0\0"
        let coff = 68
        let optSize = pe32 ? 224 : 240
        d.put16(coff, machine)
        d.put16(coff + 2, rsrc.isEmpty ? 0 : 1)
        d.put16(coff + 16, UInt16(optSize))
        let opt = coff + 20
        d.put16(opt, pe32 ? 0x10B : 0x20B)
        let (numRvaOffset, dirsOffset) = pe32 ? (92, 96) : (108, 112)
        d.put32(opt + numRvaOffset, 16)
        if !rsrc.isEmpty {
            d.put32(opt + dirsOffset + 16, sectionRVA)
            d.put32(opt + dirsOffset + 20, UInt32(rsrc.count))
            let sec = opt + optSize
            d.replaceSubrange(sec..<sec + 5, with: Array(".rsrc".utf8))
            d.put32(sec + 8, UInt32(rsrc.count))
            d.put32(sec + 12, sectionRVA)
            d.put32(sec + 16, UInt32(rsrc.count))
            d.put32(sec + 20, UInt32(rawPointer))
            d.append(rsrc)
        }
        return d
    }

    private static func resourceSection(_ res: [UInt32: [UInt32: Data]]) -> Data {
        let types = res.keys.sorted()
        var cursor = 16 + 8 * types.count
        var typeDirs: [UInt32: Int] = [:]
        for t in types { typeDirs[t] = cursor; cursor += 16 + 8 * res[t]!.count }
        var leaves: [(type: UInt32, id: UInt32, langDir: Int)] = []
        for t in types { for id in res[t]!.keys.sorted() { leaves.append((t, id, cursor)); cursor += 16 + 8 } }
        var dataEntries: [Int] = []
        for _ in leaves { dataEntries.append(cursor); cursor += 16 }
        var raws: [Int] = []
        for leaf in leaves { raws.append(cursor); cursor += res[leaf.type]![leaf.id]!.count; cursor = (cursor + 7) & ~7 }

        var out = Data(count: cursor)
        out.put16(14, UInt16(types.count))
        for (i, t) in types.enumerated() {
            out.put32(16 + 8 * i, t)
            out.put32(16 + 8 * i + 4, UInt32(typeDirs[t]!) | 0x8000_0000)
        }
        var leafIndex = 0
        for t in types {
            let base = typeDirs[t]!
            let ids = res[t]!.keys.sorted()
            out.put16(base + 14, UInt16(ids.count))
            for (j, id) in ids.enumerated() {
                out.put32(base + 16 + 8 * j, id)
                out.put32(base + 16 + 8 * j + 4, UInt32(leaves[leafIndex + j].langDir) | 0x8000_0000)
            }
            leafIndex += ids.count
        }
        for (i, leaf) in leaves.enumerated() {
            let raw = res[leaf.type]![leaf.id]!
            out.put16(leaf.langDir + 14, 1)
            out.put32(leaf.langDir + 16, 0x409)
            out.put32(leaf.langDir + 20, UInt32(dataEntries[i]))
            out.put32(dataEntries[i], sectionRVA + UInt32(raws[i]))
            out.put32(dataEntries[i] + 4, UInt32(raw.count))
            out.replaceSubrange(raws[i]..<raws[i] + raw.count, with: raw)
        }
        return out
    }
}

enum Fixtures {
    @discardableResult
    static func writeExe(_ root: URL, _ rel: String, padTo size: Int = 0, machine: UInt16 = 0x8664,
                         resources: [UInt32: [UInt32: Data]] = [:]) throws -> URL {
        var data = PEBuilder.make(machine: machine, pe32: machine == 0x014C, resources: resources)
        if data.count < size { data.append(Data(count: size - data.count)) }
        return try write(root, rel, data)
    }

    @discardableResult
    static func writeFile(_ root: URL, _ rel: String, _ text: String = "x") throws -> URL {
        try write(root, rel, Data(text.utf8))
    }

    private static func write(_ root: URL, _ rel: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
}

enum ImageFixtures {
    /// A solid red square encoded as PNG.
    static func png(width: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: width))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// A 32-bit BMP-style icon image as stored in RT_ICON (BITMAPINFOHEADER + pixels + AND mask).
    static func dib(width w: Int) -> Data {
        var header = Data(count: 40)
        header.put32(0, 40)
        header.put32(4, UInt32(w))
        header.put32(8, UInt32(w * 2))
        header.put16(12, 1)
        header.put16(14, 32)
        var pixels = Data(count: w * w * 4)
        for i in 0..<(w * w) { pixels[i * 4 + 2] = 255; pixels[i * 4 + 3] = 255 }   // BGRA red
        let maskRow = ((w + 31) / 32) * 4
        return header + pixels + Data(count: maskRow * w)
    }

    /// RT_GROUP_ICON data listing (width, resource id, byte size) entries.
    static func groupIcon(_ entries: [(width: Int, id: UInt16, size: Int)]) -> Data {
        var d = Data(count: 6 + 14 * entries.count)
        d.put16(2, 1)
        d.put16(4, UInt16(entries.count))
        for (i, e) in entries.enumerated() {
            let o = 6 + 14 * i
            d[o] = UInt8(e.width >= 256 ? 0 : e.width)
            d[o + 1] = d[o]
            d.put16(o + 4, 1)
            d.put16(o + 6, 32)
            d.put32(o + 8, UInt32(e.size))
            d.put16(o + 12, e.id)
        }
        return d
    }

    static func size(ofPNG data: Data) -> Int? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return image.width
    }
}

struct FakeRuntime: RuntimeProviding {
    let wine: URL
    var spec: RuntimeSpec { RuntimeSpec(id: "fake-rt", url: URL(fileURLWithPath: "/dev/null"), sha256: "", downloadSize: 0) }
    func isInstalled() -> Bool { true }
    func ensureInstalled(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        return wine
    }

    static func make(in dir: URL) throws -> FakeRuntime {
        let wine = dir.appendingPathComponent("wine")
        try Fixtures.writeFile(wine, "bin/wine64", "#!/bin/sh\n")
        try Fixtures.writeFile(wine, "lib/external/D3DMetal.framework/D3DMetal")
        return FakeRuntime(wine: wine)
    }
}
