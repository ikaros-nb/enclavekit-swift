//
//  Encoding.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import CryptoKit

enum Seeds {
    static let wallet = Array("wallet".utf8)
    static let vault = Array("vault".utf8)
}

let maxGuardians = 3

enum Guardian: Hashable, Sendable {
    case none
    case p256(CompressedP256Key)
    case webAuthn(CompressedP256Key)

    var borsh: [UInt8] {
        switch self {
        case .none: [0]
        case .p256(let key): [1] + key.bytes
        case .webAuthn(let key): [2] + key.bytes
        }
    }
}

/// Mirror of `enclavekit_encoding::Action`: same variant order, same field order.
enum Action: Hashable, Sendable {
    case transferSol(to: PublicKey, lamports: UInt64)
    case transferToken(mint: PublicKey, to: PublicKey, amount: UInt64)
    case proposeRotation(newKey: CompressedP256Key)
    case cancelRotation
    case setGuardians([Guardian])
    case sweepVault(to: PublicKey)
    case closeWallet(to: PublicKey)

    /// Variant index as one byte, then the fields in declaration order.
    /// Fixed-size arrays have no length prefix.
    var borsh: [UInt8] {
        var out: [UInt8] = []
        switch self {
        case let .transferSol(to, lamports):
            out.append(0)
            out += to.bytes
            out.appendLittleEndian(lamports)
        case let .transferToken(mint, to, amount):
            out.append(1)
            out += mint.bytes
            out += to.bytes
            out.appendLittleEndian(amount)
        case let .proposeRotation(newKey):
            out.append(2)
            out += newKey.bytes
        case .cancelRotation:
            out.append(3)
        case let .setGuardians(guardians):
            precondition(guardians.count == maxGuardians, "borsh writes a fixed array of \(maxGuardians) guardians")
            out.append(4)
            for guardian in guardians {
                out += guardian.borsh
            }
        case let .sweepVault(to):
            out.append(5)
            out += to.bytes
        case let .closeWallet(to):
            out.append(6)
            out += to.bytes
        }
        return out
    }
}

/// The bytes the Secure Enclave signs. Layout of `preimage.rs`.
struct Preimage: Sendable {
    static let domainTag: [UInt8] = Array("enclavekit:v1".utf8) + [0, 0, 0]

    var programId: PublicKey
    var walletId: [UInt8]
    var nonce: UInt64
    var expiresAt: Int64
    var maxRelayerFee: UInt64
    var action: Action

    init(programId: PublicKey, walletId: [UInt8], nonce: UInt64, expiresAt: Int64, maxRelayerFee: UInt64, action: Action) {
        self.programId = programId
        self.walletId = walletId
        self.nonce = nonce
        self.expiresAt = expiresAt
        self.maxRelayerFee = maxRelayerFee
        self.action = action
    }

    /// `tag ‖ program_id ‖ wallet_id ‖ nonce ‖ expires_at ‖ max_relayer_fee ‖ borsh(action)`,
    /// integers little-endian, 104 bytes before the action.
    var bytes: [UInt8] {
        var out = Self.domainTag
        out += programId.bytes
        out += walletId
        out.appendLittleEndian(nonce)
        out.appendLittleEndian(expiresAt)
        out.appendLittleEndian(maxRelayerFee)
        out += action.borsh
        return out
    }
}

/// SHA-256 of the compressed key: the seed of both PDAs.
func walletId(of key: CompressedP256Key) -> [UInt8] {
    Array(SHA256.hash(data: key.bytes))
}
