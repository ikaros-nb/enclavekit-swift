//
//  KeyTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import CryptoKit
import Testing
@testable import EnclaveKit

struct KeyTests {
    let vector: KeyVector
    init() throws { vector = try loadVector("key") }

    @Test func cryptoKitGivesTheCompressedKey() throws {
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: vector.privateKey.bytes)
        #expect(Array(privateKey.publicKey.compressedRepresentation) == vector.compressedPubkey.bytes)
    }
    
    @Test func programIdRoundTripsThroughBase58() throws {
        let programId = try PublicKey(base58: vector.programId)
        #expect(programId.base58 == vector.programId)
    }

    @Test func leadingZerosBecomeOnes() throws {
        let systemProgram = try PublicKey(bytes: [UInt8](repeating: 0, count: 32))
        #expect(systemProgram.base58 == "11111111111111111111111111111111")
    }

    @Test func invalidInputThrows() {
        #expect(throws: KeyError.invalidLength(expected: 32, actual: 31)) {
            try PublicKey(bytes: [UInt8](repeating: 1, count: 31))
        }
        #expect(throws: KeyError.invalidBase58) { try PublicKey(base58: "0OIl") }
    }
    
    @Test func walletIdIsSHA256OfTheCompressedKey() throws {
        let key = try CompressedP256Key(bytes: vector.compressedPubkey.bytes)
        #expect(walletId(of: key) == vector.walletId.bytes)
    }
}
