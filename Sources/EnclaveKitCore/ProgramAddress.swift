//
//  ProgramAddress.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import CryptoKit

extension PublicKey {
    /// Same search as `Pubkey::find_program_address`: bumps 255 down to 1.
    public static func findProgramAddress(seeds: [[UInt8]], programId: PublicKey) -> (address: PublicKey, bump: UInt8)? {
        for bump in stride(from: UInt8.max, through: 1, by: -1) {
            if let address = createProgramAddress(seeds: seeds + [[bump]], programId: programId) {
                return (address, bump)
            }
        }
        return nil
    }

    static func createProgramAddress(seeds: [[UInt8]], programId: PublicKey) -> PublicKey? {
        var hasher = SHA256()
        for seed in seeds {
            precondition(seed.count <= 32, "a seed is at most 32 bytes")
            hasher.update(data: seed)
        }
        hasher.update(data: programId.bytes)
        hasher.update(data: Array("ProgramDerivedAddress".utf8))
        let hash = Array(hasher.finalize())
        guard !Ed25519.isOnCurve(hash) else { return nil }
        return try? PublicKey(bytes: hash)
    }
}
