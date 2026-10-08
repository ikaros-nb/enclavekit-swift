//
//  Vectors.swift.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

/// Reads `Vectors/<name>.json`, copied from enclavekit-anchor by scripts/sync-vectors.sh.
func loadVector<T: Decodable>(_ name: String) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Vectors"))
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(contentsOf: url))
}

/// Bytes written as a lowercase hex string.
struct Hex: Decodable, Equatable {
    let bytes: [UInt8]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let chars = Array(string.utf8)
        guard chars.count.isMultiple(of: 2) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "odd hex length")
        }
        bytes = try stride(from: 0, to: chars.count, by: 2).map { i in
            guard let byte = UInt8(String(decoding: chars[i...i + 1], as: UTF8.self), radix: 16) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not hex: \(string)")
            }
            return byte
        }
    }
}

struct PDAVector: Decodable {
    let address: String
    let bump: UInt8
}

struct KeyVector: Decodable {
    let privateKey: Hex
    let compressedPubkey: Hex
    let walletId: Hex
    let programId: String
    let wallet: PDAVector
    let vault: PDAVector
    let eventAuthority: PDAVector
}

struct ActionsVector: Decodable {
    let nonce: UInt64
    let expiresAt: Int64
    let maxRelayerFee: UInt64
    let actions: [ActionVector]
}

func actionVectors() throws -> [ActionVector] {
    try (loadVector("actions") as ActionsVector).actions
}

struct InstructionVector: Decodable {
    let programId: String
    let data: Hex
}

struct ActionVector: Decodable, CustomTestStringConvertible {
    let name: String
    let action: Action
    let borsh: Hex
    let preimage: Hex
    let signature: Hex
    let secp256r1Instruction: InstructionVector

    var testDescription: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, fields, borsh, preimage, signature, secp256r1Instruction
    }

    private enum FieldKeys: String, CodingKey {
        case to, lamports, newKey, guardians
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        borsh = try c.decode(Hex.self, forKey: .borsh)
        preimage = try c.decode(Hex.self, forKey: .preimage)
        signature = try c.decode(Hex.self, forKey: .signature)
        secp256r1Instruction = try c.decode(InstructionVector.self, forKey: .secp256r1Instruction)

        let f = try c.nestedContainer(keyedBy: FieldKeys.self, forKey: .fields)
        switch name {
        case "transfer_sol":
            action = .transferSol(
                to: try PublicKey(bytes: f.decode(Hex.self, forKey: .to).bytes),
                lamports: try f.decode(UInt64.self, forKey: .lamports)
            )
        case "propose_rotation":
            action = .proposeRotation(newKey: try CompressedP256Key(bytes: f.decode(Hex.self, forKey: .newKey).bytes))
        case "cancel_rotation":
            action = .cancelRotation
        case "set_guardians":
            action = .setGuardians(try f.decode([GuardianVector].self, forKey: .guardians).map(\.guardian))
        case "sweep_vault":
            action = .sweepVault(to: try PublicKey(bytes: f.decode(Hex.self, forKey: .to).bytes))
        case "close_wallet":
            action = .closeWallet(to: try PublicKey(bytes: f.decode(Hex.self, forKey: .to).bytes))
        default:
            // A new action in the vectors fails here until the SDK encodes it.
            throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "unknown action \(name)")
        }
    }
}

/// `"None"`, `{ "P256": "<hex>" }` or `{ "WebAuthn": "<hex>" }`.
struct GuardianVector: Decodable {
    let guardian: Guardian

    private enum Keys: String, CodingKey {
        case p256 = "P256"
        case webAuthn = "WebAuthn"
    }

    init(from decoder: Decoder) throws {
        if let unit = try? decoder.singleValueContainer().decode(String.self), unit == "None" {
            guardian = .none
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        if let key = try c.decodeIfPresent(Hex.self, forKey: .p256) {
            guardian = .p256(try CompressedP256Key(bytes: key.bytes))
        } else if let key = try c.decodeIfPresent(Hex.self, forKey: .webAuthn) {
            guardian = .webAuthn(try CompressedP256Key(bytes: key.bytes))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "unknown guardian"))
        }
    }
}

/// The state account as Anchor encodes it, with the offset of every field.
struct StateVector: Decodable {
    let discriminator: Hex
    let size: Int
    let offsets: StateOffsets
    /// What `rp_id_hash` hashes in the passkey's slot.
    let rpId: String
    let states: [NamedStateVector]

    func state(_ name: String) throws -> NamedStateVector {
        try #require(states.first { $0.name == name })
    }
}

struct StateOffsets: Decodable {
    let walletId: Int
    let activeKey: Int
    let nonce: Int
    let attested: Int
    let guardians: [GuardianSlotOffsets]
    let rotation: RotationOffsets
    let stateBump: Int
    let vaultBump: Int
}

struct GuardianSlotOffsets: Decodable {
    let kind: Int
    let key: Int
    let rpIdHash: Int
}

struct RotationOffsets: Decodable {
    let pending: Int
    let newKey: Int
    let proposedAt: Int
    let proposedBy: Int
}

struct NamedStateVector: Decodable, CustomTestStringConvertible {
    let name: String
    let fields: StateFields
    let data: Hex

    var testDescription: String { name }
}

struct StateFields: Decodable {
    let walletId: Hex
    let activeKey: Hex
    let nonce: UInt64
    let attested: Bool
    let guardians: [GuardianSlotVector]
    let rotation: RotationVector
    let stateBump: UInt8
    let vaultBump: UInt8
}

/// `kind` is `"None"`, `"P256"` or `"WebAuthn"`; `key` and `rpIdHash` are
/// zeros when unused.
struct GuardianSlotVector: Decodable {
    let kind: String
    let key: Hex
    let rpIdHash: Hex

    var guardian: Guardian {
        get throws {
            switch kind {
            case "None": .none
            case "P256": .p256(try CompressedP256Key(bytes: key.bytes))
            case "WebAuthn": .webAuthn(try CompressedP256Key(bytes: key.bytes))
            default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown kind \(kind)"))
            }
        }
    }
}

/// All zeros but `pending` when no rotation is pending.
struct RotationVector: Decodable {
    let pending: Bool
    let newKey: Hex
    let proposedAt: Int64
    let proposedBy: UInt8
}

struct HighSVector: Decodable {
    let message: Hex
    let highS: Hex
    let lowS: Hex
}

struct TransactionVector: Decodable {
    let relayer: String
    let relayerFee: UInt64
    let blockhash: String
    let programInstruction: ProgramInstructionVector
    let message: Hex
    let transaction: String
}

struct InstructionsVector: Decodable {
    let relayer: String
    let relayerFee: UInt64
    let instructions: [NamedInstructionVector]

    func instruction(_ name: String) throws -> ProgramInstructionVector {
        try #require(instructions.first { $0.name == name }).programInstruction
    }
}

struct NamedInstructionVector: Decodable {
    let name: String
    let programInstruction: ProgramInstructionVector
}

struct ProgramInstructionVector: Decodable {
    let programId: String
    let accounts: [AccountMetaVector]
    let discriminator: Hex
    let data: Hex
}

struct AccountMetaVector: Decodable {
    let pubkey: String
    let isSigner: Bool
    let isWritable: Bool

    var accountMeta: AccountMeta {
        get throws { AccountMeta(publicKey: try PublicKey(base58: pubkey), isSigner: isSigner, isWritable: isWritable) }
    }
}
