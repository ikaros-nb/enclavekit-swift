//
//  EnclaveKitError.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

/// The failures an app can act on. The others come as they are: a
/// `URLError` when Kora or the RPC is out of reach, for instance.
public enum EnclaveKitError: Error, Equatable, Sendable {
    /// `createWallet()` found a key on this device: the wallet is that key,
    /// it is never replaced.
    case walletExists
    /// The wallet rotated to another key: this device can no longer sign.
    case keyReplaced
    /// The vault cannot pay the amount, the fee and keep its own rent:
    /// `available` is the most it can send.
    case insufficientFunds(available: Lamports)
    /// Landed and failed: the relayer paid the fee, nothing else happened.
    case failed(Receipt, reason: String)
    /// Still unknown after its blockhash expired: it can no longer land.
    case notConfirmed(Receipt)
}
