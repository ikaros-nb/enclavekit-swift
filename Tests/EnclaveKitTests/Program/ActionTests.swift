//
//  ActionTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Testing
@testable import EnclaveKit

struct ActionTests {
    let key: KeyVector
    let header: ActionsVector

    init() throws {
        key = try loadVector("key")
        header = try loadVector("actions")
    }

    @Test(arguments: try actionVectors())
    func borsh(_ vector: ActionVector) {
        #expect(vector.action.borsh == vector.borsh.bytes)
    }

    @Test(arguments: try actionVectors())
    func preimage(_ vector: ActionVector) throws {
        let preimage = Preimage(
            programId: try PublicKey(base58: key.programId),
            walletId: key.walletId.bytes,
            nonce: header.nonce,
            expiresAt: header.expiresAt,
            maxRelayerFee: header.maxRelayerFee,
            action: vector.action
        )
        #expect(preimage.bytes == vector.preimage.bytes)
    }
}
