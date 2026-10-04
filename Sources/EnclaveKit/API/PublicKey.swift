//
//  PublicKey.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

public enum KeyError: Error, Equatable {
    case invalidLength(expected: Int, actual: Int)
    case invalidBase58
}

/// A Solana address: 32 bytes, shown in base58.
public struct PublicKey: Hashable, Sendable, CustomStringConvertible {
    static let length = 32
    let bytes: [UInt8]

    init(bytes: [UInt8]) throws(KeyError) {
        guard bytes.count == Self.length else {
            throw .invalidLength(expected: Self.length, actual: bytes.count)
        }
        self.bytes = bytes
    }

    /// What the user pasted or scanned: anything but 32 bytes in base58
    /// throws.
    public init(base58: String) throws(KeyError) {
        guard let bytes = Base58.decode(base58) else { throw .invalidBase58 }
        try self.init(bytes: bytes)
    }

    public var base58: String { Base58.encode(bytes) }
    public var description: String { base58 }
}
