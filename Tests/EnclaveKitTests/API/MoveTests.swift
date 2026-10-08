//
//  MoveTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 07/10/2026.
//

import Foundation
import os
import Testing
@testable import EnclaveKit

/// `SoftwareKey.test`'s wallet, moved by its own key to another device's.
struct MoveTests {
    let newDeviceKey = SoftwareKey()

    /// No delay, nothing to confirm: once the move lands, the old device can
    /// no longer sign and the new one signs.
    @Test func walletMovesAtOnce() async throws {
        let moved = OSAllocatedUnfairLock(initialState: false)
        let newKey = newDeviceKey.publicKey
        let kora = ActionRequestTests.relayer { params in
            let transaction = ActionRequestTests.transaction(params)
            #expect(transaction.firstRange(of: EnclaveKitProgram.discriminator(of: "propose_rotation")) != nil)
            #expect(transaction.firstRange(of: newKey.bytes) != nil)
            moved.withLock { $0 = true }
        }
        let rpc = devnet { moved.withLock { $0 } ? stateData(activeKey: newKey) : stateData() }
        let oldDevice = Wallet(signer: SoftwareKey.test, kora: kora, rpc: rpc)
        let newDevice = Wallet(signer: newDeviceKey, walletId: oldDevice.id.bytes, kora: kora, rpc: rpc)
        #expect(try await newDevice.status() == .keyReplaced)

        let request = try await oldDevice.prepareMove(to: newDevice.deviceKey)
        #expect(request.summary == "Move this wallet to the key \(newDevice.deviceKey) now: this device stops signing for it")
        #expect(request.maxFee == 10_000)
        #expect(try await request.authorize() == ActionRequestTests.sent)

        #expect(try await oldDevice.status() == .keyReplaced)
        #expect(try await newDevice.status() == .active(recovery: nil))
    }

    /// The program has no key to move before the first action.
    @Test func unusedWalletCannotMove() async {
        await #expect(throws: EnclaveKitError.notOnChainYet) {
            try await ActionRequestTests().wallet(balance: 20_000_000).prepareMove(to: DeviceKey(newDeviceKey.publicKey))
        }
    }

    /// Taken on by this device, then closed: no key on-chain, and none this
    /// device could put there.
    @Test func closedWalletOfAnotherKeyCannotMove() async {
        await #expect(throws: EnclaveKitError.keyReplaced) {
            try await ActionRequestTests().wallet(balance: 20_000_000, signer: SoftwareKey()).prepareMove(to: DeviceKey(newDeviceKey.publicKey))
        }
    }

    /// A guardian's key would end up guarding itself; this device's own
    /// would move nothing.
    @Test func keyTheWalletNamesIsRefused() async throws {
        let guardian = SoftwareKey().publicKey
        let wallet = ActionRequestTests().wallet(state: accountJSON(data: stateData(guardian: guardian)), balance: 20_000_000)
        for key in [guardian, SoftwareKey.test.publicKey] {
            await #expect(throws: EnclaveKitError.keyInUse) { try await wallet.prepareMove(to: DeviceKey(key)) }
        }
    }

    /// Signed by a guardian, the same action only proposes, with the delay:
    /// never a move.
    @Test func guardianCannotMove() async {
        let guardian = SoftwareKey()
        let state = accountJSON(data: stateData(guardian: guardian.publicKey))
        let wallet = ActionRequestTests().wallet(state: state, balance: 20_000_000, signer: guardian)
        await #expect(throws: EnclaveKitError.keyReplaced) { try await wallet.prepareMove(to: DeviceKey(newDeviceKey.publicKey)) }
    }

    /// Devnet with the wallet's state as `state` gives it at each read, and
    /// 0.02 SOL in the vault.
    func devnet(state: @escaping @Sendable () -> [UInt8]) -> SolanaRPC {
        SolanaRPC(transport: stub { method, _ in
            switch method {
            case "getAccountInfo": #"{"context":{"slot":1},"value":\#(accountJSON(data: state()))}"#
            case "getBalance": #"{"context":{"slot":1},"value":20000000}"#
            case "getMinimumBalanceForRentExemption": "650240"
            case "getSignatureStatuses": #"{"context":{"slot":1},"value":[{"confirmationStatus":"confirmed","err":null}]}"#
            default: nil
            }
        })
    }
}
