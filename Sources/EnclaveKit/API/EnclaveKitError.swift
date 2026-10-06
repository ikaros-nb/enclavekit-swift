//
//  EnclaveKitError.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation

/// The failures an app can act on. The others come as they are: a
/// `URLError` when Kora or the RPC is out of reach, for instance. All of
/// them read well through `localizedDescription`.
public enum EnclaveKitError: Error, Equatable, Sendable {
    /// `createWallet()` found a key on this device: the wallet is that key,
    /// it is never replaced.
    case walletExists
    /// No key on this device yet: `createWallet()` makes it, the key that
    /// signs as guardian too.
    case noWallet
    /// No Secure Enclave key behind Face ID here: the iOS Simulator has one,
    /// but refuses its access control.
    case secureEnclaveUnavailable
    /// The wallet rotated to another key: this device can no longer sign.
    case keyReplaced
    /// The guarded wallet does not name this device: its owner adds it with
    /// `prepareSetGuardians`.
    case notAGuardian
    /// The vault cannot pay the amount, the fee and keep its own rent:
    /// `available` is the most it can send.
    case insufficientFunds(available: Lamports)
    /// The user dismissed Face ID, or the system did as the app left the
    /// screen: nothing was signed. The request can be authorized again.
    case cancelled
    /// The relayer refused the transaction, its simulation failed for
    /// instance: nothing was sent, no fee was paid.
    case rejected(reason: String)
    /// Landed and failed: the relayer paid the fee, nothing else happened.
    case failed(Receipt, reason: String)
    /// Still unknown after its blockhash expired: it can no longer land.
    case notConfirmed(Receipt)

    /// The transaction's receipt once it reached the network: its explorer
    /// page tells what happened.
    public var receipt: Receipt? {
        switch self {
        case let .failed(receipt, _), let .notConfirmed(receipt): receipt
        case .walletExists, .noWallet, .secureEnclaveUnavailable, .keyReplaced, .notAGuardian, .insufficientFunds, .cancelled, .rejected: nil
        }
    }
}

extension EnclaveKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .walletExists:
            "This device already has a wallet."
        case .noWallet:
            "This device has no wallet yet: create it first, its key is the one that signs."
        case .secureEnclaveUnavailable:
            "This device cannot keep a key behind Face ID. The iOS Simulator cannot: run on an iPhone."
        case .keyReplaced:
            "This wallet moved to another key: this device can no longer sign for it."
        case .notAGuardian:
            "This wallet does not name this device as guardian: its owner has to add it first."
        case let .insufficientFunds(available):
            "This wallet can send at most \(available): it keeps enough for the fee and its own rent."
        case .cancelled:
            "Face ID was cancelled: nothing was signed."
        case let .rejected(reason):
            "The relayer refused the transaction, nothing was sent: \(reason)"
        case let .failed(_, reason):
            "The transaction failed on-chain, nothing moved: \(reason)"
        case .notConfirmed:
            "The network did not confirm the transaction in time: it can no longer go through."
        }
    }
}
