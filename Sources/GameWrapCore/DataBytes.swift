import Foundation

/// Little-endian helpers for reading and writing binary formats (PE, ICO).
extension Data {
    func u16(_ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let i = startIndex + offset
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[i + $1]) << (8 * UInt32($1)) }
    }

    mutating func put16(_ offset: Int, _ value: UInt16) {
        let i = startIndex + offset
        self[i] = UInt8(value & 0xFF)
        self[i + 1] = UInt8(value >> 8)
    }

    mutating func put32(_ offset: Int, _ value: UInt32) {
        let i = startIndex + offset
        for b in 0..<4 { self[i + b] = UInt8((value >> (8 * UInt32(b))) & 0xFF) }
    }
}
