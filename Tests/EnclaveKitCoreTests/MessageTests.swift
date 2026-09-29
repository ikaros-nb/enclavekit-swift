//
//  MessageTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Foundation
import Testing
@testable import EnclaveKitCore

struct MessageTests {
    /// Cases of `short_vec` in the Solana SDK.
    @Test(arguments: [
        (0x0, [0x00]),
        (0x7f, [0x7f]),
        (0x80, [0x80, 0x01]),
        (0xff, [0xff, 0x01]),
        (0x100, [0x80, 0x02]),
        (0x7fff, [0xff, 0xff, 0x01]),
        (0xffff, [0xff, 0xff, 0x03]),
    ] as [(Int, [UInt8])])
    func compactU16(value: Int, encoded: [UInt8]) {
        var out: [UInt8] = []
        out.appendCompactU16(value)
        #expect(out == encoded)
    }

    @Test func transferSolMatchesTheVector() throws {
        let key: KeyVector = try loadVector("key")
        let vector: TransactionVector = try loadVector("transaction")
        let actions: ActionsVector = try loadVector("actions")
        let transferSol = try #require(actions.actions.first { $0.name == "transfer_sol" })
        let preimage = Preimage(
            programId: try PublicKey(base58: key.programId),
            walletId: key.walletId.bytes,
            nonce: actions.nonce,
            expiresAt: actions.expiresAt,
            maxRelayerFee: actions.maxRelayerFee,
            action: transferSol.action
        )
        let relayer = try PublicKey(base58: vector.relayer)

        let message = Message(
            instructions: [
                Secp256r1Program.instruction(
                    publicKey: try CompressedP256Key(bytes: key.compressedPubkey.bytes),
                    signature: transferSol.signature.bytes,
                    message: preimage.bytes
                ),
                try EnclaveKitProgram.instruction(executing: preimage, relayer: relayer, relayerFee: vector.relayerFee),
            ],
            payer: relayer,
            recentBlockhash: try Blockhash(base58: vector.blockhash)
        )
        #expect(message.bytes == vector.message.bytes)
        #expect(Data(message.unsignedTransaction).base64EncodedString() == vector.transaction)
    }
}
