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
    /// `ROTATION_DELAY` of the devnet build, in seconds.
    static let rotationDelay = 60
    /// `RotationTooEarly`, the 17th error of the program: 6000 + 16.
    static let rotationTooEarly = "custom program error: 0x1780"
    /// Sets the guardian, pays three fees, keeps the vault's rent.
    static let funding: Lamports = 3_000_000

    let kora: Kora

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(environment["KORA_URL"].flatMap(URL.init))
        kora = Kora(url: url, apiKey: environment["KORA_API_KEY"])
    }

    /// The owner adds a guardian; the guardian proposes the new device's key;
    /// the owner cancels; the guardian proposes again; once the timelock has
    /// passed, the new device confirms and spends from the same wallet.
    @Test func guardianMovesTheWalletToANewDevice() async throws {
        let funder = Wallet(signer: SoftwareKey.funder, kora: kora)
        // The funding, then the funder's own fee and rent.
        try #require(
            try await funder.balance() >= Lamports(Self.funding.value + 1_000_000),
            "fund the funder: solana transfer \(funder.address) 0.05 --allow-unfunded-recipient -u devnet"
        )
        let ownerKey = SoftwareKey(), guardianKey = SoftwareKey(), newKey = SoftwareKey()
        let owner = Wallet(signer: ownerKey, kora: kora)
        let guardian = Wallet(signer: guardianKey, walletId: owner.walletId, kora: kora)
        let newDevice = Wallet(signer: newKey, walletId: owner.walletId, kora: kora)
        print(owner.explorerURL)

        try await authorize(funder.prepareTransfer(Self.funding, to: owner.address))

        // First action of the wallet: it also creates the state.
        try await authorize(owner.prepare(.setGuardians([.p256(guardianKey.publicKey), .none, .none])))
        #expect(try await owner.state()?.guardians.first == .p256(guardianKey.publicKey))

        try await authorize(guardian.prepare(.proposeRotation(newKey: newKey.publicKey)))
        #expect(try await owner.state()?.rotation?.newKey == newKey.publicKey)

        try await authorize(owner.prepare(.cancelRotation))
        #expect(try await owner.state()?.rotation == nil)

        try await authorize(guardian.prepare(.proposeRotation(newKey: newKey.publicKey)))
        #expect(try await owner.state()?.rotation?.newKey == newKey.publicKey)

        // Kora's simulation stops it: nothing is sent, nothing is paid.
        let tooEarly = await #expect(throws: EnclaveKitError.self) {
            try await newDevice.confirmRotation()
        }
        #expect(tooEarly?.localizedDescription.contains(Self.rotationTooEarly) == true)

        print(try await confirmOnceOpen(newDevice).explorerURL)
        #expect(try await newDevice.status() == .active(attested: false))
        #expect(try await owner.status() == .keyReplaced)

        // Same wallet, new key: it spends, and pays the funder back a little.
        try await authorize(newDevice.prepareTransfer(400_000, to: funder.address))
    }

    private func authorize(_ request: ActionRequest) async throws {
        print(request.summary, try await request.authorize().explorerURL)
    }

    /// The program reads the cluster's clock, a few seconds off the Mac's:
    /// waits the delay, then tries again while it is still too early.
    private func confirmOnceOpen(_ wallet: Wallet) async throws -> Receipt {
        try await Task.sleep(for: .seconds(Self.rotationDelay))
        for _ in 0..<12 {
            do {
                return try await wallet.confirmRotation()
            } catch let EnclaveKitError.rejected(reason) where reason.contains(Self.rotationTooEarly) {
                try await Task.sleep(for: .seconds(5))
            }
        }
        throw EnclaveKitError.rejected(reason: "still too early a minute past the delay: is the devnet build deployed?")
    }
}
