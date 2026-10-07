//
//  LiveRecoveryTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

/// A whole recovery on devnet, three software keys standing for three
/// devices. A new wallet every run, funded by `SoftwareKey.funder`; about
/// two minutes, most of it the devnet timelock. Off unless `LIVE_SEND` is
/// set as well as `KORA_URL`:
///
///     KORA_URL=http://127.0.0.1:8080 LIVE_SEND=1 swift test --filter LiveRecoveryTests
@Suite(.enabled(if: ["KORA_URL", "LIVE_SEND"].allSatisfy { ProcessInfo.processInfo.environment[$0] != nil }))
struct LiveRecoveryTests {
    /// Sets the guardian, pays three fees, keeps the vault's rent.
    static let funding: Lamports = 3_000_000

    let kora: Kora

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(environment["KORA_URL"].flatMap(URL.init))
        kora = Kora(url: url, apiKey: environment["KORA_API_KEY"])
    }

    /// The owner adds a guardian; the guardian proposes the new device's key;
    /// the owner cancels; the guardian proposes again; once the delay has
    /// passed, the new device confirms and spends from the same wallet.
    /// `recoverWallet` and `deleteDeviceKey` need the Secure Enclave:
    /// `EnclaveKitClientTests` has them.
    @Test func guardianMovesTheWalletToANewDevice() async throws {
        let funder = Wallet(signer: SoftwareKey.funder, kora: kora)
        // The funding, then the funder's own fee and rent.
        try #require(
            try await funder.balance() >= Lamports(Self.funding.value + 1_000_000),
            "fund the funder: solana transfer \(funder.address) 0.05 --allow-unfunded-recipient -u devnet"
        )
        let guardianKey = SoftwareKey()
        let owner = Wallet(signer: SoftwareKey(), kora: kora)
        // What each device scans on another's screen: the guardian's key,
        // then the wallet to guard and recover.
        let scannedGuardian = try DeviceKey(Wallet(signer: guardianKey, kora: kora).deviceKey.description)
        let scannedWallet = try Wallet.ID(owner.id.description)
        let guardian = GuardedWallet(wallet: Wallet(signer: guardianKey, walletId: scannedWallet.bytes, kora: kora))
        let newDevice = Wallet(signer: SoftwareKey(), walletId: scannedWallet.bytes, kora: kora)
        print(owner.explorerURL)

        try await authorize(funder.prepareTransfer(Self.funding, to: owner.address))

        // First action of the wallet: it also creates the state.
        try await authorize(owner.prepareSetGuardians([scannedGuardian]))
        #expect(try await owner.guardians() == [scannedGuardian])
        #expect(try await guardian.status() == .guarding(recovery: nil))

        try await authorize(guardian.prepareRecovery(to: newDevice.deviceKey))
        let first = try #require(try await recovery(seenBy: owner))
        #expect(first.newKey == newDevice.deviceKey)
        // Dated by the cluster's clock, a few seconds off the Mac's.
        #expect(abs(first.opensAt.timeIntervalSinceNow - Cluster.devnet.recoveryDelay) < 30)

        try await authorize(owner.prepareCancelRecovery())
        #expect(try await recovery(seenBy: owner) == nil)
        #expect(try await newDevice.status() == .keyReplaced)

        try await authorize(guardian.prepareRecovery(to: newDevice.deviceKey))
        let second = try #require(try await recovery(seenBy: owner))
        #expect(try await guardian.status() == .guarding(recovery: second))
        #expect(try await newDevice.status() == .recovering(second))

        // The SDK waits for the delay's end; the program does too, without
        // it: Kora's simulation stops it, nothing is sent, nothing is paid.
        await #expect(throws: EnclaveKitError.recoveryNotOpen(opensAt: second.opensAt)) {
            try await newDevice.confirmRecovery()
        }
        let tooEarly = await #expect(throws: EnclaveKitError.self) {
            try await newDevice.confirmRotation()
        }
        #expect(tooEarly?.localizedDescription.contains(EnclaveKitProgram.rotationTooEarly) == true)

        try await Task.sleep(for: .seconds(max(0, second.opensAt.timeIntervalSinceNow)))
        print(try await newDevice.confirmRecovery().explorerURL)
        #expect(try await newDevice.status() == .active(recovery: nil))
        #expect(try await owner.status() == .keyReplaced)
        // The guardian still guards the wallet on its new key.
        #expect(try await guardian.status() == .guarding(recovery: nil))

        // Same wallet, new key: it spends, and pays the funder back a little.
        try await authorize(newDevice.prepareTransfer(400_000, to: funder.address))
    }

    private func authorize(_ request: ActionRequest) async throws {
        print(request.summary, try await request.authorize().explorerURL)
    }

    /// The recovery the owner sees pending, if any.
    private func recovery(seenBy owner: Wallet) async throws -> Recovery? {
        guard case let .active(recovery) = try await owner.status() else { return nil }
        return recovery
    }
}
