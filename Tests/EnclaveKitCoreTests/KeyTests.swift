//
//  KeyTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import CryptoKit
import Testing
@testable import EnclaveKitCore

struct KeyTests {
    let vector: KeyVector
    init() throws { vector = try loadVector("key") }

    @Test func cryptoKitGivesTheCompressedKey() throws {
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: vector.privateKey.bytes)
        #expect(Array(privateKey.publicKey.compressedRepresentation) == vector.compressedPubkey.bytes)
    }
}
