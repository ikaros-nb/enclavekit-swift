//
//  Secp256r1Tests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Testing
@testable import EnclaveKitCore

struct Secp256r1Tests {
    let key: KeyVector
    init() throws { key = try loadVector("key") }

    @Test(arguments: try actionVectors())
    func instructionMatchesTheVector(_ action: ActionVector) throws {
        let instruction = Secp256r1Program.instruction(
            publicKey: try CompressedP256Key(bytes: key.compressedPubkey.bytes),
            signature: action.signature.bytes,
            message: action.preimage.bytes
        )
        #expect(instruction.programId.base58 == action.secp256r1Instruction.programId)
        #expect(instruction.accounts.isEmpty)
        #expect(instruction.data == action.secp256r1Instruction.data.bytes)
    }

    @Test func highSSignatureIsNormalised() throws {
        let vector: HighSVector = try loadVector("high_s")
        let publicKey = try CompressedP256Key(bytes: key.compressedPubkey.bytes)
        let fromHigh = Secp256r1Program.instruction(publicKey: publicKey, signature: vector.highS.bytes, message: vector.message.bytes)
        let fromLow = Secp256r1Program.instruction(publicKey: publicKey, signature: vector.lowS.bytes, message: vector.message.bytes)
        #expect(fromHigh == fromLow)
        #expect(Array(fromHigh.data[49..<113]) == vector.lowS.bytes)
    }
}
