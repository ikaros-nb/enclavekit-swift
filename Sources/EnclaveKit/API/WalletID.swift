//
//  WalletID.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

extension Wallet {
    /// Names a wallet: the hash of its first key, which no recovery
    /// changes. Its text starts with
    /// `enclavekit:wallet:` so that nobody takes it for the vault's address,
    /// which receives SOL.
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        static let prefix = "enclavekit:wallet:"
        let bytes: [UInt8]

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        /// What the QR code held. Anything else throws, a Solana address
        /// included.
        public init(_ text: String) throws(KeyError) {
            guard text.hasPrefix(Self.prefix),
                  let bytes = Base58.decode(String(text.dropFirst(Self.prefix.count))),
                  bytes.count == 32
            else { throw .notAWalletID }
            self.bytes = bytes
        }

        public var description: String { Self.prefix + Base58.encode(bytes) }
    }
}
