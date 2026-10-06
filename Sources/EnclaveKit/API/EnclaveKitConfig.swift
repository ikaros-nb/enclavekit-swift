//
//  EnclaveKitConfig.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 04/10/2026.
//

import Foundation

/// What the app chooses: the relayer that pays the fees, the cluster the
/// wallet lives on. Everything else is the SDK's business.
public struct EnclaveKitConfig: Sendable {
    /// The Kora server, fee payer of every transaction.
    public var relayerURL: URL
    /// Sent as `x-api-key` when Kora requires one.
    public var relayerAPIKey: String?
    public var cluster: Cluster

    public init(relayerURL: URL, relayerAPIKey: String? = nil, cluster: Cluster = .devnet) {
        self.relayerURL = relayerURL
        self.relayerAPIKey = relayerAPIKey
        self.cluster = cluster
    }
}

/// A Solana cluster where the EnclaveKit program is deployed.
public enum Cluster: Sendable {
    case devnet

    /// The public RPC: free, rate limited.
    var rpcURL: URL {
        switch self {
        case .devnet: SolanaRPC.devnet
        }
    }

    var programId: PublicKey {
        switch self {
        case .devnet: EnclaveKitProgram.id
        }
    }

    /// `ROTATION_DELAY` of the program there: the time the owner has to
    /// cancel a recovery. The devnet build waits a minute, not 72 hours.
    var recoveryDelay: TimeInterval {
        switch self {
        case .devnet: 60
        }
    }

    /// `ROTATION_WINDOW`: how long a recovery stays open to confirm.
    static let recoveryWindow: TimeInterval = 7 * 24 * 60 * 60

    /// `path` on explorer.solana.com, e.g. `tx/<signature>`.
    func explorerURL(_ path: String) -> URL {
        switch self {
        case .devnet: URL(string: "https://explorer.solana.com/\(path)?cluster=devnet")!
        }
    }
}
