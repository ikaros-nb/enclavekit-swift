//
//  SmartWallet.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import CryptoKit

enum AccountError: Error, Equatable {
    /// The first 8 bytes are not those of a `SmartWallet`.
    case wrongDiscriminator
    /// The data ends before the last field.
    case truncated
    /// An `Option`, `bool` or enum tag that borsh does not accept.
    case invalidTag(UInt8)
}

/// The wallet's state account, mirror of `state.rs`.
struct SmartWallet: Hashable, Sendable {
    struct PendingRotation: Hashable, Sendable {
        var newKey: CompressedP256Key
        var proposedAt: Int64
        var proposedBy: UInt8
    }

    /// Bytes Anchor allocates: discriminator, then every field at its largest
    /// (`Some` rotation, guardians holding a key).
    static let space = 8 + 32 + 33 + 8 + 1 + (1 + 33 + 8 + 1) + maxGuardians * (1 + 33) + 1 + 1

    /// `sha256("account:SmartWallet")[..8]`, written by Anchor before the fields.
    static let discriminator = Array(SHA256.hash(data: Array("account:SmartWallet".utf8)).prefix(8))

    var walletId: [UInt8]
    var activeKey: CompressedP256Key
    var nonce: UInt64
    var attested: Bool
    var rotation: PendingRotation?
    var guardians: [Guardian]
    var stateBump: UInt8
    var vaultBump: UInt8

    /// Decodes `getAccountInfo` data. Borsh writes only the bytes of the
    /// variant it holds: every field after `rotation` moves with it, so no
    /// fixed offset past `attested`. Zeros pad the end up to `space`.
    init(data: [UInt8]) throws(AccountError) {
        var reader = BorshReader(data)
        guard try reader.bytes(8) == Self.discriminator else { throw .wrongDiscriminator }
        walletId = try reader.bytes(32)
        activeKey = try reader.key()
        nonce = try reader.integer()
        attested = try reader.bool()
        switch try reader.integer(UInt8.self) {
        case 0:
            rotation = nil
        case 1:
            rotation = PendingRotation(newKey: try reader.key(), proposedAt: try reader.integer(), proposedBy: try reader.integer())
        case let tag:
            throw .invalidTag(tag)
        }
        guardians = []
        for _ in 0..<maxGuardians {
            switch try reader.integer(UInt8.self) {
            case 0: guardians.append(.none)
            case 1: guardians.append(.p256(try reader.key()))
            case 2: guardians.append(.webAuthn(try reader.key()))
            case let tag: throw .invalidTag(tag)
            }
        }
        stateBump = try reader.integer()
        vaultBump = try reader.integer()
    }
}

/// Reads borsh fields one after the other.
private struct BorshReader {
    private let data: [UInt8]
    private var offset = 0

    init(_ data: [UInt8]) {
        self.data = data
    }

    mutating func bytes(_ count: Int) throws(AccountError) -> [UInt8] {
        guard data.count - offset >= count else { throw .truncated }
        defer { offset += count }
        return Array(data[offset..<offset + count])
    }

    mutating func integer<T: FixedWidthInteger>(_: T.Type = T.self) throws(AccountError) -> T {
        let raw = try bytes(MemoryLayout<T>.size)
        return T(littleEndian: raw.withUnsafeBytes { $0.loadUnaligned(as: T.self) })
    }

    mutating func bool() throws(AccountError) -> Bool {
        switch try integer(UInt8.self) {
        case 0: return false
        case 1: return true
        case let tag: throw .invalidTag(tag)
        }
    }

    mutating func key() throws(AccountError) -> CompressedP256Key {
        let raw = try bytes(CompressedP256Key.length)
        // 33 bytes read, the length cannot be wrong.
        return try! CompressedP256Key(bytes: raw)
    }
}
