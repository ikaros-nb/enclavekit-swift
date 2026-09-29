//
//  Instruction.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

public struct AccountMeta: Hashable, Sendable {
    public var publicKey: PublicKey
    public var isSigner: Bool
    public var isWritable: Bool
}

public struct Instruction: Hashable, Sendable {
    public var programId: PublicKey
    public var accounts: [AccountMeta]
    public var data: [UInt8]
}
