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
        // Accounts in the order of `#[derive(Accounts)]`: wallet, vault, the
        // action's own, then relayer, Instructions sysvar, System.
        var accounts: [AccountMeta] = [
            .writable(walletAddress(walletId: preimage.walletId, programId: preimage.programId)),
            .writable(vaultAddress(walletId: preimage.walletId, programId: preimage.programId)),
        ]
        var data: [UInt8]

        switch preimage.action {
        case let .transferSol(to, lamports):
            data = header(of: "transfer_sol", preimage)
            data.appendLittleEndian(lamports)
            accounts.append(.writable(to))
        case let .proposeRotation(newKey):
            data = header(of: "propose_rotation", preimage)
            data += newKey.bytes
        case .cancelRotation:
            data = header(of: "cancel_rotation", preimage)
        case let .setGuardians(guardians):
            data = header(of: "set_guardians", preimage)
            data += guardians.flatMap(\.borsh)
        case .transferToken, .sweepVault, .closeWallet:
            throw .unsupported(preimage.action)
        }

        // Last argument of every handler, outside the signed bytes: the
        // program pays back at most the signed ceiling.
        data.appendLittleEndian(relayerFee)
        accounts += [.writableSigner(relayer), .readonly(.instructionsSysvar), .readonly(.systemProgram)]
        return Instruction(programId: preimage.programId, accounts: accounts, data: data)
    }

    /// Swaps in the key a guardian proposed, once the timelock has passed.
    /// Nobody signs it: the program checks the clock, the relayer pays the
    /// fee and gets nothing back.
    static func confirmRotation(walletId: [UInt8], programId: PublicKey = id) -> Instruction {
        Instruction(
            programId: programId,
            accounts: [.writable(walletAddress(walletId: walletId, programId: programId))],
            data: discriminator(of: "confirm_rotation") + walletId
        )
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
