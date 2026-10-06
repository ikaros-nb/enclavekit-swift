//
//  Recovery.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation

/// A guardian's proposal to move a wallet to a new device's key. Until
/// `opensAt` only the owner can act on it, to cancel it. From then until
/// `closesAt`, anyone can confirm it, and the wallet moves.
public struct Recovery: Hashable, Sendable {
    /// The key the wallet moves to: the new device's.
    public let newKey: DeviceKey
    /// The end of the timelock: 72 hours after the proposal, one minute on
    /// devnet.
    public let opensAt: Date
    /// Past this the proposal lapses, and a guardian may make another.
    public let closesAt: Date

    init(_ rotation: SmartWallet.PendingRotation, cluster: Cluster) {
        newKey = DeviceKey(rotation.newKey)
        opensAt = Date(timeIntervalSince1970: TimeInterval(rotation.proposedAt) + cluster.recoveryDelay)
        closesAt = opensAt + Cluster.recoveryWindow
    }
}
