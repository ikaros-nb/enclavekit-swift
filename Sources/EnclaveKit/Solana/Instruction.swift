//
//  Instruction.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

struct AccountMeta: Hashable, Sendable {
    var publicKey: PublicKey
    var isSigner: Bool
    var isWritable: Bool
}

extension AccountMeta {
    static func writableSigner(_ key: PublicKey) -> Self { .init(publicKey: key, isSigner: true, isWritable: true) }
    static func writable(_ key: PublicKey) -> Self { .init(publicKey: key, isSigner: false, isWritable: true) }
    static func readonly(_ key: PublicKey) -> Self { .init(publicKey: key, isSigner: false, isWritable: false) }
}

struct Instruction: Hashable, Sendable {
    var programId: PublicKey
    var accounts: [AccountMeta]
    var data: [UInt8]
}
