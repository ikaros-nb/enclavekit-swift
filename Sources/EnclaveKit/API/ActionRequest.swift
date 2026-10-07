//
//  ActionRequest.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation

/// An action waiting for the user: the app shows `summary` and `maxFee`,
/// then calls `authorize()`. Nothing is signed before that.
public struct ActionRequest: Identifiable, Sendable {
    /// One Face ID at a time in the whole app.
    private static let queue = AuthorizationQueue()

    public let id = UUID()
    /// The most the vault pays the relayer back: the network fee, plus the
    /// rent of the wallet's account on its first action. The enclave signs
    /// this very ceiling.
    public let maxFee: Lamports
    let action: Action
    let wallet: Wallet
    /// Runs once the cluster confirmed: closing the wallet deletes the key.
    var afterConfirmation: @Sendable () throws -> Void = {}

    /// What the user approves, addresses in full.
    public var summary: String { action.consentPhrase }

    /// Face ID, then Kora sends, then the cluster confirms. Waits while
    /// another authorization is in flight, then reads the nonce it left.
    public func authorize() async throws -> Receipt {
        try await Self.queue.run {
            let receipt = try await wallet.execute(action, maxRelayerFee: maxFee.value)
            try afterConfirmation()
            return receipt
        }
    }
}
