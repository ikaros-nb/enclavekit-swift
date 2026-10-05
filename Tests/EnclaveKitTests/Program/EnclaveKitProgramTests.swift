//
//  EnclaveKitProgramTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Testing
@testable import EnclaveKit

struct EnclaveKitProgramTests {
    let key: KeyVector
    let vectors: InstructionsVector
    /// The shared header of actions.json, around its `transfer_sol` case.
    let preimage: Preimage

    init() throws {
        key = try loadVector("key")
        vectors = try loadVector("instructions")
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

    /// Each case of actions.json, executed by the instruction of the same
    /// name in instructions.json.
    @Test(arguments: try actionVectors())
    func actionMatchesTheVector(_ action: ActionVector) throws {
        let expected = try vectors.instruction(action.name)
        var preimage = preimage
        preimage.action = action.action

        let instruction = try EnclaveKitProgram.instruction(
            executing: preimage,
            relayer: try PublicKey(base58: vectors.relayer),
            relayerFee: vectors.relayerFee
        )
        #expect(EnclaveKitProgram.discriminator(of: action.name) == expected.discriminator.bytes)
        #expect(instruction.programId.base58 == expected.programId)
        #expect(instruction.accounts == (try expected.accounts.map { try $0.accountMeta }))
        #expect(instruction.data == expected.data.bytes)
    }

    @Test func confirmRotationMatchesTheVector() throws {
        let expected = try vectors.instruction("confirm_rotation")
        let instruction = EnclaveKitProgram.confirmRotation(walletId: key.walletId.bytes)
        #expect(instruction.programId.base58 == expected.programId)
        #expect(instruction.accounts == (try expected.accounts.map { try $0.accountMeta }))
        #expect(instruction.data == expected.data.bytes)
    }

    @Test func actionsWithoutHandlerThrow() throws {
        var sweep = preimage
        sweep.action = .sweepVault(to: .systemProgram)
        #expect(throws: EnclaveKitProgram.InstructionError.unsupported(sweep.action)) {
            try EnclaveKitProgram.instruction(executing: sweep, relayer: .systemProgram, relayerFee: 0)
        }
    }
}
