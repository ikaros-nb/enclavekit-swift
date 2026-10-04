//
//  Receipt.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation

/// A transaction sent through Kora: its signature and its explorer page.
public struct Receipt: Hashable, Sendable {
    public let signature: String
    public let explorerURL: URL
}
