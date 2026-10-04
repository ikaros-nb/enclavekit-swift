//
//  LowSTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import CryptoKit
import Testing
@testable import EnclaveKit

struct LowSTests {
    let key: KeyVector
    let vector: HighSVector

    init() throws {
        key = try loadVector("key")
        vector = try loadVector("high_s")
    }

    @Test func highSIsNormalised() {
        #expect(LowS.normalize(vector.highS.bytes) == vector.lowS.bytes)
        #expect(LowS.normalize(vector.lowS.bytes) == vector.lowS.bytes)
    }

    /// CryptoKit accepts both forms: only the precompile enforces low-S.
    @Test func cryptoKitAcceptsBoth() throws {
        let publicKey = try P256.Signing.PublicKey(compressedRepresentation: key.compressedPubkey.bytes)
        for raw in [vector.highS, vector.lowS] {
            let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw.bytes)
            #expect(publicKey.isValidSignature(signature, for: vector.message.bytes))
        }
    }

    /// CryptoKit, like the Secure Enclave, signs with a random nonce: about
    /// half its signatures are high-S. 64 draws make missing one ~2^-64.
    @Test func normalisedCryptoKitSignaturesStillVerify() throws {
        let privateKey = P256.Signing.PrivateKey()
        let message = Array("enclavekit".utf8)
        var sawHighS = false
        for _ in 0..<64 {
            let raw = Array(try privateKey.signature(for: message).rawRepresentation)
            let low = LowS.normalize(raw)
            if low != raw { sawHighS = true }
            let signature = try P256.Signing.ECDSASignature(rawRepresentation: low)
            #expect(privateKey.publicKey.isValidSignature(signature, for: message))
        }
        #expect(sawHighS)
    }

    @Test(arguments: try actionVectors())
    func vectorSignaturesAreValidLowS(_ action: ActionVector) throws {
        let publicKey = try P256.Signing.PublicKey(compressedRepresentation: key.compressedPubkey.bytes)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: action.signature.bytes)
        #expect(publicKey.isValidSignature(signature, for: action.preimage.bytes))
        #expect(LowS.normalize(action.signature.bytes) == action.signature.bytes)
    }
}
