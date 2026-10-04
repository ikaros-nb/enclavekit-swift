//
//  ConsentTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Testing
@testable import EnclaveKit

struct ConsentTests {
    static let address = try! PublicKey(bytes: [UInt8](repeating: 0x77, count: 32))
    static let key = try! CompressedP256Key(bytes: [0x02] + [UInt8](repeating: 0x0a, count: 32))
    static let hex = "02" + String(repeating: "0a", count: 32)

    @Test(arguments: [
        (.transferSol(to: address, lamports: 10_000_000),
         "Send 0.01 SOL to 93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"),
        (.transferToken(mint: address, to: address, amount: 5),
         "Send 5 base units of the token 93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8 to 93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"),
        (.proposeRotation(newKey: key), "Move this wallet to the key \(hex)"),
        (.cancelRotation, "Cancel the pending key rotation"),
        (.setGuardians([.none, .none, .none]), "Remove every guardian"),
        (.setGuardians([.p256(key), .none, .webAuthn(key)]), "Set the guardians to \(hex), passkey \(hex)"),
        (.sweepVault(to: address), "Send the whole balance to 93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"),
        (.closeWallet(to: address), "Close this wallet and send everything to 93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"),
    ] as [(Action, String)])
    func phrase(_ action: Action, _ phrase: String) {
        #expect(action.consentPhrase == phrase)
    }
}
