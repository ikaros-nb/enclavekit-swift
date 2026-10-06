//
//  WalletIDTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

struct WalletIDTests {
    let wallet = Wallet(signer: SoftwareKey.test, kora: Kora(url: URL(string: "http://kora.invalid")!))

    /// The `wallet_id` of key.json, after the prefix.
    @Test func textNamesTheWallet() throws {
        #expect(wallet.id.description == "enclavekit:wallet:FAnBvyFqTsuE8HTbq9yCDS4fuWyHnvH8CH5Vi5EqKcNQ")
        #expect(try Wallet.ID(wallet.id.description) == wallet.id)
    }

    /// The vault's address is 32 bytes in base58 too: without the prefix, a
    /// guardian would keep a wallet nobody can find.
    @Test(arguments: [
        "hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK",
        "enclavekit:wallet:",
        "enclavekit:wallet:0OIl",
        // 31 bytes
        "enclavekit:wallet:" + String(repeating: "1", count: 31),
    ])
    func rejectsWhatIsNotAWallet(_ text: String) {
        #expect(throws: KeyError.notAWalletID) { try Wallet.ID(text) }
    }

    @Test func scanErrorReadsWell() {
        let error: Error = KeyError.notAWalletID
        #expect(error.localizedDescription == "This is not an EnclaveKit wallet.")
    }
}
