//
//  GuardedWalletTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Testing
@testable import EnclaveKit

struct GuardedWalletTests {
    let guardian = SoftwareKey()
    let newKey = SoftwareKey().publicKey

    @Test func guardianSeesTheRecovery() async throws {
        let pending = rotation(to: newKey, secondsAgo: 10)
        let wallet = guarded(state: accountJSON(data: stateData(guardian: guardian.publicKey, rotation: pending)))
        #expect(try await wallet.status() == .guarding(recovery: Recovery(pending, cluster: .devnet)))
    }

    /// Before the owner names it, or after they drop it.
    @Test func otherDeviceIsNotGuarding() async throws {
        #expect(try await guarded(state: "null").status() == .notGuarding)
        #expect(try await guarded(state: accountJSON(data: stateData())).status() == .notGuarding)
    }

    /// The vault pays the fee, the guardian approves the new device's key in
    /// full.
    @Test func guardianProposesTheNewKey() async throws {
        let wallet = guarded(state: accountJSON(data: stateData(guardian: guardian.publicKey)), balance: 20_000_000)
        let request = try await wallet.prepareRecovery(to: DeviceKey(newKey))
        #expect(request.maxFee == 10_000)
        #expect(request.summary == "Move this wallet to the key \(DeviceKey(newKey))")
    }

    @Test(arguments: ["null", accountJSON(data: stateData())])
    func otherDeviceCannotPropose(state: String) async {
        await #expect(throws: EnclaveKitError.notAGuardian) {
            try await guarded(state: state, balance: 20_000_000).prepareRecovery(to: DeviceKey(newKey))
        }
    }

    /// `SoftwareKey.test`'s wallet, guarded by `guardian`.
    func guarded(state: String, balance: UInt64 = 0) -> GuardedWallet {
        GuardedWallet(wallet: ActionRequestTests().wallet(state: state, balance: balance, signer: guardian))
    }
}
