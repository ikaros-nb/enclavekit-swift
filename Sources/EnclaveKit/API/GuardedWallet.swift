//
//  GuardedWallet.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation

/// Someone else's wallet, seen from a device it names as guardian. All the
/// guardian can do is start a recovery, the day the owner loses their
/// device; the wallet's vault pays the fee.
public struct GuardedWallet: Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The wallet names this device among its guardians. `recovery`: the
        /// proposal pending, from this guardian or another.
        case guarding(recovery: Recovery?)
        /// The wallet does not name this device: not yet, or no longer.
        case notGuarding
    }

    /// Signs with this device's key, for the guarded wallet's id.
    let wallet: Wallet

    public var id: Wallet.ID { wallet.id }

    /// The guarded wallet's vault.
    public var address: PublicKey { wallet.address }

    public var explorerURL: URL { wallet.explorerURL }

    public func status() async throws -> Status {
        guard let state = try await wallet.state(), state.guardians.contains(.p256(wallet.signer.publicKey)) else {
            return .notGuarding
        }
        return .guarding(recovery: wallet.recovery(in: state))
    }

    /// Moves the wallet to `newKey`, the key the new device shows, once the
    /// timelock has passed and the new device confirms. Throws `notAGuardian`
    /// if the wallet does not name this device.
    public func prepareRecovery(to newKey: DeviceKey) async throws -> ActionRequest {
        try await wallet.prepare(.proposeRotation(newKey: newKey.key))
    }
}
