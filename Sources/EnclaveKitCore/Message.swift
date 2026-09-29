//
//  Message.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

/// A recent blockhash: 32 bytes shown in base58, like an address.
public struct Blockhash: Hashable, Sendable {
    public let bytes: [UInt8]

    public init(base58: String) throws(KeyError) {
        bytes = try PublicKey(base58: base58).bytes
    }
}

/// Legacy transaction message, compiled like `Message::new_with_blockhash`
/// so the bytes match the Rust side exactly.
public struct Message: Sendable {
    public struct Header: Hashable, Sendable {
        public var numRequiredSignatures: UInt8
        public var numReadonlySignedAccounts: UInt8
        public var numReadonlyUnsignedAccounts: UInt8
    }

    struct CompiledInstruction: Hashable, Sendable {
        var programIdIndex: UInt8
        var accounts: [UInt8]
        var data: [UInt8]
    }

    /// Order of the groups in `accountKeys`. Synthesised `Comparable` follows
    /// the declaration order.
    private enum Group: Comparable {
        case payer, writableSigner, readonlySigner, writable, readonly
    }

    public let header: Header
    public let accountKeys: [PublicKey]
    public let recentBlockhash: Blockhash
    let instructions: [CompiledInstruction]

    public init(instructions: [Instruction], payer: PublicKey, recentBlockhash: Blockhash) {
        // Every key once, with its flags merged over all instructions.
        var flags: [PublicKey: (isSigner: Bool, isWritable: Bool)] = [:]
        func add(_ key: PublicKey, isSigner: Bool, isWritable: Bool) {
            let old = flags[key] ?? (false, false)
            flags[key] = (old.isSigner || isSigner, old.isWritable || isWritable)
        }
        for instruction in instructions {
            add(instruction.programId, isSigner: false, isWritable: false)
            for meta in instruction.accounts {
                add(meta.publicKey, isSigner: meta.isSigner, isWritable: meta.isWritable)
            }
        }
        add(payer, isSigner: true, isWritable: true)

        func group(_ key: PublicKey) -> Group {
            if key == payer { return .payer }
            switch flags[key]! {
            case (true, true): return .writableSigner
            case (true, false): return .readonlySigner
            case (false, true): return .writable
            case (false, false): return .readonly
            }
        }
        // Within a group, byte order: Rust keeps the keys in a BTreeMap.
        let keys = flags.keys.sorted { a, b in
            let (ga, gb) = (group(a), group(b))
            return ga != gb ? ga < gb : a.bytes.lexicographicallyPrecedes(b.bytes)
        }
        precondition(keys.count <= 256, "account indexes are one byte")
        let groups = keys.map(group)
        let index = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, UInt8($0)) })

        header = Header(
            numRequiredSignatures: UInt8(groups.filter { $0 <= .readonlySigner }.count),
            numReadonlySignedAccounts: UInt8(groups.filter { $0 == .readonlySigner }.count),
            numReadonlyUnsignedAccounts: UInt8(groups.filter { $0 == .readonly }.count)
        )
        accountKeys = keys
        self.recentBlockhash = recentBlockhash
        self.instructions = instructions.map { instruction in
            CompiledInstruction(
                programIdIndex: index[instruction.programId]!,
                accounts: instruction.accounts.map { index[$0.publicKey]! },
                data: instruction.data
            )
        }
    }

    /// What the fee payer signs.
    public var bytes: [UInt8] {
        var out = [header.numRequiredSignatures, header.numReadonlySignedAccounts, header.numReadonlyUnsignedAccounts]
        out.appendCompactU16(accountKeys.count)
        for key in accountKeys {
            out += key.bytes
        }
        out += recentBlockhash.bytes
        out.appendCompactU16(instructions.count)
        for instruction in instructions {
            out.append(instruction.programIdIndex)
            out.appendShortVec(instruction.accounts)
            out.appendShortVec(instruction.data)
        }
        return out
    }

    /// The transaction handed to Kora: one empty signature slot per required
    /// signer, then the message. Kora fills the fee payer's slot.
    public var unsignedTransaction: [UInt8] {
        let signatures = Int(header.numRequiredSignatures)
        var out: [UInt8] = []
        out.appendCompactU16(signatures)
        out += [UInt8](repeating: 0, count: 64 * signatures)
        return out + bytes
    }
}
