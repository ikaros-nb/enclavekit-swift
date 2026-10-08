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
    /// A `bool` or a guardian kind that the program never writes.
    case invalidTag(UInt8)
}

/// The wallet's state account, mirror of `state.rs`. Every field has a fixed
/// size: an empty guardian slot, or no pending rotation, is zeros, never a
/// shorter encoding. Each key sits at a fixed offset, where
/// `getProgramAccounts` finds it.
struct SmartWallet: Hashable, Sendable {
    struct PendingRotation: Hashable, Sendable {
        var newKey: CompressedP256Key
        var proposedAt: Int64
        var proposedBy: UInt8
    }

    /// Bytes `bytes` at `offset`: a `memcmp` filter of `getProgramAccounts`.
    /// Offsets of `enclavekit_encoding::state`.
    struct Filter: Hashable, Sendable {
        let offset: Int
        let bytes: [UInt8]

        /// The key that signs for the wallet.
        static func activeKey(_ key: CompressedP256Key) -> Filter {
            Filter(offset: 40, bytes: key.bytes)
        }

        /// `key` as P256 guardian in slot `index`: the slot's kind byte, then
        /// its key, as `Guardian` writes them.
        static func guardian(_ key: CompressedP256Key, slot index: Int) -> Filter {
            Filter(offset: 82 + guardianSlotLength * index, bytes: Guardian.p256(key).borsh)
        }

        /// A guardian's proposal toward `key`: the `pending` byte, then
        /// `new_key`. It matches a lapsed one too.
        static func proposal(to key: CompressedP256Key) -> Filter {
            Filter(offset: 280, bytes: [1] + key.bytes)
        }
    }

    /// Kind, key, then the passkey's rpId hash, zeros for any other kind.
    static let guardianSlotLength = 1 + CompressedP256Key.length + 32

    /// Bytes Anchor allocates, discriminator included: the `dataSize` filter
    /// that leaves out accounts of another layout.
    static let space = 8 + 32 + 33 + 8 + 1 + maxGuardians * guardianSlotLength + (1 + 33 + 8 + 1) + 1 + 1

    /// `sha256("account:SmartWallet")[..8]`, written by Anchor before the fields.
    static let discriminator = Array(SHA256.hash(data: Array("account:SmartWallet".utf8)).prefix(8))

    var walletId: [UInt8]
    var activeKey: CompressedP256Key
    var nonce: UInt64
    var attested: Bool
    var guardians: [Guardian]
    var rotation: PendingRotation?
    var stateBump: UInt8
    var vaultBump: UInt8

    /// Decodes `getAccountInfo` data, field after field.
    init(data: [UInt8]) throws(AccountError) {
        var reader = BorshReader(data)
        guard try reader.bytes(8) == Self.discriminator else { throw .wrongDiscriminator }
        walletId = try reader.bytes(32)
        activeKey = try reader.key()
        nonce = try reader.integer()
        attested = try reader.bool()
        guardians = []
        for _ in 0..<maxGuardians {
            let kind = try reader.integer(UInt8.self)
            let key = try reader.key()
            // The passkey's rpId hash: nothing reads it yet.
            _ = try reader.bytes(32)
            switch kind {
            case 0: guardians.append(.none)
            case 1: guardians.append(.p256(key))
            case 2: guardians.append(.webAuthn(key))
            case let tag: throw .invalidTag(tag)
            }
        }
        let pending = try reader.bool()
        let proposal = PendingRotation(newKey: try reader.key(), proposedAt: try reader.integer(), proposedBy: try reader.integer())
        rotation = pending ? proposal : nil
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

    /// Zeros in an empty slot: a key no device has.
    mutating func key() throws(AccountError) -> CompressedP256Key {
        let raw = try bytes(CompressedP256Key.length)
        // 33 bytes read, the length cannot be wrong.
        return try! CompressedP256Key(bytes: raw)
    }
}
