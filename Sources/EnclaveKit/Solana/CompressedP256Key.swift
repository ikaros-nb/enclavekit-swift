//
//  CompressedP256Key.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

/// Compressed SEC1 P-256 public key: 0x02 or 0x03, then x.
struct CompressedP256Key: Hashable, Sendable {
    static let length = 33
    let bytes: [UInt8]

    init(bytes: [UInt8]) throws(KeyError) {
        guard bytes.count == Self.length else {
            throw .invalidLength(expected: Self.length, actual: bytes.count)
        }
        self.bytes = bytes
    }

    /// How the consent sentence and the QR code write it: the user can
    /// compare one with the other.
    var hex: String { bytes.hex }
}
