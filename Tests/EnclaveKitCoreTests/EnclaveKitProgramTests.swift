//
//  EnclaveKitProgramTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Testing
@testable import EnclaveKitCore

struct EnclaveKitProgramTests {
    let key: KeyVector
    let vector: TransactionVector
    /// The `transfer_sol` case of actions.json, which transaction.json wraps.
    let preimage: Preimage

    init() throws {
        key = try loadVector("key")
        vector = try loadVector("transaction")
        let actions: ActionsVector = try loadVector("actions")
        let transferSol = try #require(actions.actions.first { $0.name == "transfer_sol" })
        preimage = Preimage(
            programId: try PublicKey(base58: key.programId),
            walletId: key.walletId.bytes,
            nonce: actions.nonce,
            expiresAt: actions.expiresAt,
            maxRelayerFee: actions.maxRelayerFee,
            action: transferSol.action
        )
    }

    @Test func programIdIsTheDeployedOne() {
        #expect(EnclaveKitProgram.id.base58 == key.programId)
    }

    @Test func discriminatorIsAnchors() {
        #expect(EnclaveKitProgram.discriminator(of: "transfer_sol") == vector.programInstruction.discriminator.bytes)
    }

    @Test func transferSolMatchesTheVector() throws {
        let instruction = try EnclaveKitProgram.instruction(
            executing: preimage,
            relayer: try PublicKey(base58: vector.relayer),
            relayerFee: vector.relayerFee
        )
        #expect(instruction.programId.base58 == vector.programInstruction.programId)
        #expect(instruction.accounts == (try vector.programInstruction.accounts.map { try $0.accountMeta }))
        #expect(instruction.data == vector.programInstruction.data.bytes)
    }

    @Test func actionsWithoutHandlerThrow() throws {
        var sweep = preimage
        sweep.action = .sweepVault(to: .systemProgram)
        #expect(throws: EnclaveKitProgram.InstructionError.unsupported(sweep.action)) {
            try EnclaveKitProgram.instruction(executing: sweep, relayer: .systemProgram, relayerFee: 0)
        }
    }
}
