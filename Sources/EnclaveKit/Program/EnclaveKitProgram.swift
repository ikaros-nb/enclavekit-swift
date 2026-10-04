//
//  EnclaveKitProgram.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import CryptoKit

/// Instructions of the EnclaveKit program, encoded the way Anchor decodes them.
enum EnclaveKitProgram {
    /// Devnet deployment.
    static let id = try! PublicKey(base58: "dG4h3aizVEW1bKjzkGsfk6zqcfa2MVn2DjavPniesSY")

    enum InstructionError: Error, Equatable {
        /// The program has no handler for this action yet.
        case unsupported(Action)
    }

    /// State account of the wallet.
    static func walletAddress(walletId: [UInt8], programId: PublicKey = id) -> PublicKey {
        address(seed: Seeds.wallet, walletId: walletId, programId: programId)
    }

    /// System account holding the wallet's lamports.
    static func vaultAddress(walletId: [UInt8], programId: PublicKey = id) -> PublicKey {
        address(seed: Seeds.vault, walletId: walletId, programId: programId)
    }

    /// The instruction that executes `preimage.action`. It goes right after the
    /// secp256r1 instruction that carries the signature of `preimage.bytes`.
    /// Its arguments repeat the signed header, from which the program rebuilds
    /// the preimage.
    static func instruction(
        executing preimage: Preimage,
        relayer: PublicKey,
        relayerFee: UInt64
    ) throws(InstructionError) -> Instruction {
        let wallet = walletAddress(walletId: preimage.walletId, programId: preimage.programId)
        let vault = vaultAddress(walletId: preimage.walletId, programId: preimage.programId)

        switch preimage.action {
        case let .transferSol(to, lamports):
            var data = header(of: "transfer_sol", preimage)
            data.appendLittleEndian(lamports)
            data.appendLittleEndian(relayerFee)
            return Instruction(
                programId: preimage.programId,
                accounts: [
                    .writable(wallet),
                    .writable(vault),
                    .writable(to),
                    .writableSigner(relayer),
                    .readonly(.instructionsSysvar),
                    .readonly(.systemProgram),
                ],
                data: data
            )
        case .transferToken, .proposeRotation, .cancelRotation, .setGuardians, .sweepVault, .closeWallet:
            throw .unsupported(preimage.action)
        }
    }

    /// `sha256("global:<name>")[..8]`, what Anchor dispatches on.
    static func discriminator(of name: String) -> [UInt8] {
        Array(SHA256.hash(data: Array("global:\(name)".utf8)).prefix(8))
    }

    /// Discriminator, then the arguments every signed instruction starts with:
    /// `wallet_id`, `nonce`, `expires_at`, `max_relayer_fee`.
    private static func header(of name: String, _ preimage: Preimage) -> [UInt8] {
        var data = discriminator(of: name)
        data += preimage.walletId
        data.appendLittleEndian(preimage.nonce)
        data.appendLittleEndian(preimage.expiresAt)
        data.appendLittleEndian(preimage.maxRelayerFee)
        return data
    }

    private static func address(seed: [UInt8], walletId: [UInt8], programId: PublicKey) -> PublicKey {
        // No bump in 255...1 gives an off-curve address with probability 2^-255.
        PublicKey.findProgramAddress(seeds: [seed, walletId], programId: programId)!.address
    }
}

extension PublicKey {
    static let systemProgram = try! PublicKey(bytes: [UInt8](repeating: 0, count: 32))
    static let instructionsSysvar = try! PublicKey(base58: "Sysvar1nstructions1111111111111111111111111")
}
