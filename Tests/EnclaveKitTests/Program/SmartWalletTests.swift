//
//  SmartWalletTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

struct SmartWalletTests {
    /// Devnet account zJnfu9j39T4tB2VYGLrDNbdujq89YtvkgJk1FwJ135u, created by
    /// one run of the `kora_transfer_sol` script.
    static let devnetAccount = Array(Data(base64Encoded: """
        QzvcsykKPLHP6LNu6xc3nV+snMt31bx9aURx/E7PZnWsdqiy6c5sCgPiuO5D7rNhJ9bZpKRYsIvT\
        ESvEJ/MsCp4GztW1QTplqwEAAAAAAAAAAAAAAAD9/QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
        AA==
        """)!)

    @Test func spaceIsTheAllocatedSize() {
        #expect(Self.devnetAccount.count == SmartWallet.space)
    }

    /// No vector for accounts: the fields check each other instead. The
    /// address comes from `walletId`, `walletId` from the key, the bump from
    /// the derivation.
    @Test func decodesARealAccount() throws {
        let wallet = try SmartWallet(data: Self.devnetAccount)
        let address = try #require(PublicKey.findProgramAddress(seeds: [Seeds.wallet, wallet.walletId], programId: EnclaveKitProgram.id))
        #expect(address.address.base58 == "zJnfu9j39T4tB2VYGLrDNbdujq89YtvkgJk1FwJ135u")
        #expect(address.bump == wallet.stateBump)
        #expect(walletId(of: wallet.activeKey) == wallet.walletId)
        #expect(wallet.nonce == 1)
        #expect(!wallet.attested)
        #expect(wallet.rotation == nil)
        #expect(wallet.guardians == [.none, .none, .none])
    }

    /// `Some` rotation and guardians with a key shift everything after them.
    @Test func variantsShiftTheFollowingFields() throws {
        let key = try CompressedP256Key(bytes: [0x02] + [UInt8](repeating: 0xaa, count: 32))
        let guardians: [Guardian] = [.p256(key), .none, .webAuthn(key)]

        var data = Array(Self.devnetAccount.prefix(82)) // up to `attested`
        data += [1] + key.bytes
        data.appendLittleEndian(Int64(1_790_000_000))
        data.append(2)
        data += guardians.flatMap(\.borsh)
        data += [254, 253]
        data += [UInt8](repeating: 0, count: SmartWallet.space - data.count)

        let wallet = try SmartWallet(data: data)
        #expect(wallet.rotation == SmartWallet.PendingRotation(newKey: key, proposedAt: 1_790_000_000, proposedBy: 2))
        #expect(wallet.guardians == guardians)
        #expect(wallet.stateBump == 254)
        #expect(wallet.vaultBump == 253)
    }

    @Test func rejectsOtherBytes() {
        var other = Self.devnetAccount
        other[0] ^= 1
        #expect(throws: AccountError.wrongDiscriminator) { try SmartWallet(data: other) }
        #expect(throws: AccountError.truncated) { try SmartWallet(data: Array(Self.devnetAccount.prefix(80))) }

        var badTag = Self.devnetAccount
        badTag[82] = 7 // rotation
        #expect(throws: AccountError.invalidTag(7)) { try SmartWallet(data: badTag) }
    }
}
