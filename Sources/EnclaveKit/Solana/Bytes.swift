//
//  Bytes.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

extension Array where Element == UInt8 {
    /// Two lowercase hex digits per byte.
    var hex: String {
        map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    /// `nil` unless every character is a hex digit, two per byte.
    init?(hex: String) {
        let digits = hex.compactMap(\.hexDigitValue)
        guard digits.count == hex.count, digits.count.isMultiple(of: 2) else { return nil }
        self = stride(from: 0, to: digits.count, by: 2).map { UInt8(digits[$0] << 4 | digits[$0 + 1]) }
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    
    /// Solana's `short_vec` length: 7 bits per byte, low bits first, high bit
    /// set while more bytes follow. One to three bytes.
    mutating func appendCompactU16(_ value: Int) {
        precondition((0...Int(UInt16.max)).contains(value), "compact-u16 holds 0...65535")
        var rest = value
        repeat {
            var byte = UInt8(rest & 0x7f)
            rest >>= 7
            if rest != 0 { byte |= 0x80 }
            append(byte)
        } while rest != 0
    }
    
    /// Length as compact-u16, then the bytes.
    mutating func appendShortVec(_ bytes: [UInt8]) {
        appendCompactU16(bytes.count)
        append(contentsOf: bytes)
    }
}
