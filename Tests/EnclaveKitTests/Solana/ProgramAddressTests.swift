//
//  ProgramAddressTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import CryptoKit
import Testing
@testable import EnclaveKit

struct ProgramAddressTests {
    let vector: KeyVector
    init() throws { vector = try loadVector("key") }

    @Test func walletAndVaultPDAs() throws {
        let programId = try PublicKey(base58: vector.programId)
        let wallet = try #require(PublicKey.findProgramAddress(seeds: [Seeds.wallet, vector.walletId.bytes], programId: programId))
        let vault = try #require(PublicKey.findProgramAddress(seeds: [Seeds.vault, vector.walletId.bytes], programId: programId))
        #expect(wallet.address.base58 == vector.wallet.address)
        #expect(wallet.bump == vector.wallet.bump)
        #expect(vault.address.base58 == vector.vault.address)
        #expect(vault.bump == vector.vault.bump)
    }

    /// Bump 252: 255 to 253 land on the curve, so the search goes on past them.
    @Test func eventAuthorityPDA() throws {
        let programId = try PublicKey(base58: vector.programId)
        let eventAuthority = try #require(PublicKey.findProgramAddress(seeds: [Seeds.eventAuthority], programId: programId))
        #expect(eventAuthority.address.base58 == vector.eventAuthority.address)
        #expect(eventAuthority.bump == vector.eventAuthority.bump)
        #expect(EnclaveKitProgram.eventAuthorityAddress() == eventAuthority.address)
    }

    /// Wallet and vault have bump 255: this is what exercises the on-curve branch.
    @Test func ed25519PublicKeysAreOnTheCurve() {
        for _ in 0..<64 {
            let key = Curve25519.Signing.PrivateKey().publicKey
            #expect(Ed25519.isOnCurve(Array(key.rawRepresentation)))
        }
    }

    @Test func pdasAreOffTheCurve() throws {
        for address in [vector.wallet.address, vector.vault.address, vector.eventAuthority.address] {
            #expect(!Ed25519.isOnCurve(try PublicKey(base58: address).bytes))
        }
    }
}
