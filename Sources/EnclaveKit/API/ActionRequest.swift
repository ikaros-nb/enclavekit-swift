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
    /// What the user approves, addresses in full.
    public let summary: String
    let action: Action
    let wallet: Wallet
    /// Runs once the cluster confirmed: closing the wallet deletes the key.
    let afterConfirmation: @Sendable () throws -> Void

    /// `summary` defaults to the action's own sentence.
    init(
        maxFee: Lamports,
        action: Action,
        wallet: Wallet,
        summary: String? = nil,
        afterConfirmation: @escaping @Sendable () throws -> Void = {}
    ) {
        self.maxFee = maxFee
        self.summary = summary ?? action.consentPhrase
        self.action = action
        self.wallet = wallet
        self.afterConfirmation = afterConfirmation
    }

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
