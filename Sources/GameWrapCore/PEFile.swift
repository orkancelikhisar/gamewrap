import Foundation

public enum PEMachine: Equatable, Sendable {
    case x64, x86, arm64
    case other(UInt16)

    init(raw: UInt16) {
        switch raw {
        case 0x8664: self = .x64
        case 0x014C: self = .x86
        case 0xAA64: self = .arm64
        default: self = .other(raw)
        }
    }
}

public enum PEError: Error {
    case notPE
}

/// Reads the parts of a Windows PE executable that GameWrap needs: the machine type and resources.
public struct PEFile {
    public static let rtIcon: UInt32 = 3
    public static let rtGroupIcon: UInt32 = 14

    public let machine: PEMachine
    private let data: Data
    private let sections: [Section]
    private let resourceRVA: UInt32

    private struct Section {
        let virtualAddress: UInt32
        let virtualSize: UInt32
        let rawPointer: UInt32
        let rawSize: UInt32
    }

    private struct DirectoryEntry {
        let id: UInt32
        let isDirectory: Bool
        let offset: Int
    }

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        guard data.u16(0) == 0x5A4D,
              let peOffset = data.u32(0x3C).map(Int.init),
              data.u32(peOffset) == 0x0000_4550,
              let machineRaw = data.u16(peOffset + 4),
              let sectionCount = data.u16(peOffset + 6),
              let optionalSize = data.u16(peOffset + 20),
              let magic = data.u16(peOffset + 24)
        else { throw PEError.notPE }

        let optional = peOffset + 24
        let (numRvaOffset, dirsOffset) = magic == 0x20B ? (108, 112) : (92, 96)
        var rsrc: UInt32 = 0
        if let n = data.u32(optional + numRvaOffset), n > 2 {
            rsrc = data.u32(optional + dirsOffset + 16) ?? 0
        }

        var sections: [Section] = []
        let table = optional + Int(optionalSize)
        for i in 0..<Int(sectionCount) {
            let s = table + 40 * i
            guard let vs = data.u32(s + 8), let va = data.u32(s + 12),
                  let rs = data.u32(s + 16), let rp = data.u32(s + 20) else { throw PEError.notPE }
            sections.append(Section(virtualAddress: va, virtualSize: vs, rawPointer: rp, rawSize: rs))
        }

        self.machine = PEMachine(raw: machineRaw)
        self.data = data
        self.sections = sections
        self.resourceRVA = rsrc
    }

    public static func machine(of url: URL) -> PEMachine? {
        (try? PEFile(url: url))?.machine
    }

    /// Each resource of `type` that has a numeric id, using its first language. Named entries are skipped.
    public func resources(ofType type: UInt32) -> [(id: UInt32, data: Data)] {
        guard resourceRVA != 0, let base = fileOffset(ofRVA: resourceRVA),
              let typeDir = entries(base: base, directory: 0).first(where: { $0.id == type && $0.isDirectory })
        else { return [] }

        var result: [(id: UInt32, data: Data)] = []
        for idEntry in entries(base: base, directory: typeDir.offset) where idEntry.isDirectory {
            guard let lang = entries(base: base, directory: idEntry.offset).first, !lang.isDirectory,
                  let rva = data.u32(base + lang.offset), let size = data.u32(base + lang.offset + 4),
                  let start = fileOffset(ofRVA: rva), start + Int(size) <= data.count
            else { continue }
            result.append((idEntry.id, data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + Int(size)))))
        }
        return result
    }

    private func fileOffset(ofRVA rva: UInt32) -> Int? {
        for s in sections where rva >= s.virtualAddress && UInt64(rva) < UInt64(s.virtualAddress) + UInt64(max(s.virtualSize, s.rawSize)) {
            return Int(s.rawPointer) + Int(rva - s.virtualAddress)
        }
        return nil
    }

    private func entries(base: Int, directory: Int) -> [DirectoryEntry] {
        let d = base + directory
        guard let named = data.u16(d + 12), let ids = data.u16(d + 14) else { return [] }
        let total = Int(named) + Int(ids)
        guard total <= 4096 else { return [] }
        return (0..<total).compactMap { i in
            let e = d + 16 + 8 * i
            guard let name = data.u32(e), let target = data.u32(e + 4), name & 0x8000_0000 == 0 else { return nil }
            return DirectoryEntry(id: name, isDirectory: target & 0x8000_0000 != 0, offset: Int(target & 0x7FFF_FFFF))
        }
    }
}
