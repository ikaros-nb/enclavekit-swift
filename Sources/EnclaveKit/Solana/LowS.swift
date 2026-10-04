//
//  LowS.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

enum LowS {
    /// Order of P-256, big-endian.
    private static let n: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51,
    ]
    /// floor(n / 2): the precompile refuses any s above it.
    private static let halfN: [UInt8] = [
        0x7f, 0xff, 0xff, 0xff, 0x80, 0x00, 0x00, 0x00, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xde, 0x73, 0x7d, 0x56, 0xd3, 0x8b, 0xcf, 0x42, 0x79, 0xdc, 0xe5, 0x61, 0x7e, 0x31, 0x92, 0xa8,
    ]

    /// r ‖ s with s replaced by n - s when s > n/2.
    static func normalize(_ signature: [UInt8]) -> [UInt8] {
        precondition(signature.count == 64)
        let r = Array(signature[0..<32])
        let s = Array(signature[32..<64])
        // Same length, big-endian: byte order is numeric order.
        guard halfN.lexicographicallyPrecedes(s) else { return signature }

        var lowS = [UInt8](repeating: 0, count: 32)
        var borrow = 0
        for i in (0..<32).reversed() {
            let diff = Int(n[i]) - Int(s[i]) - borrow
            lowS[i] = UInt8((diff + 256) & 0xff)
            borrow = diff < 0 ? 1 : 0
        }
        return r + lowS
    }
}
