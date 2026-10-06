//
//  DeviceKey.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import CryptoKit

/// A device's public key, as another device scans it: what a wallet names
/// as guardian, what a recovery moves a wallet to. Its text, 66 hex digits,
/// goes in the QR code, and the consent sentence writes the key the same
/// way: the user can compare the two.
public struct DeviceKey: Hashable, Sendable, CustomStringConvertible {
    let key: CompressedP256Key

    init(_ key: CompressedP256Key) {
        self.key = key
    }

    /// What the QR code held. Anything but a point of P-256 throws: a
    /// guardian off the curve could never sign.
    public init(_ text: String) throws(KeyError) {
        guard let bytes = [UInt8](hex: text),
              (try? P256.Signing.PublicKey(compressedRepresentation: bytes)) != nil,
              let key = try? CompressedP256Key(bytes: bytes)
        else { throw .notADeviceKey }
        self.key = key
    }

    public var description: String { key.hex }
}
