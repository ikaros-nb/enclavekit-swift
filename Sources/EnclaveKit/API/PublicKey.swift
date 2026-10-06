//
//  PublicKey.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Foundation

/// Text that is not what the app expected: a pasted address, a scanned
/// QR code.
public enum KeyError: Error, Equatable {
    case invalidLength(expected: Int, actual: Int)
    case invalidBase58
    /// Not 66 hex digits for a point of P-256: see `DeviceKey`.
    case notADeviceKey
    /// Not `enclavekit:wallet:` and 32 bytes in base58: see `Wallet.ID`.
    case notAWalletID
}

extension KeyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidLength(expected, actual): "Expected \(expected) bytes, found \(actual)."
        case .invalidBase58: "This is not a Solana address."
        case .notADeviceKey: "This is not an EnclaveKit device key."
        case .notAWalletID: "This is not an EnclaveKit wallet."
        }
    }
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
