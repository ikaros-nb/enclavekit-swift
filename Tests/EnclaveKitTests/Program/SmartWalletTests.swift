//
//  SmartWalletTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import Testing
@testable import EnclaveKit

struct SmartWalletTests {
    let vector: StateVector

    init() throws {
        vector = try loadVector("state")
    }

    /// The size and the offsets the SDK filters on are the Rust crate's. A
    /// filter puts a tag and the key after it in one run of bytes: each key
    /// sits right after its tag.
    @Test func layoutMatchesTheVector() throws {
        let key = try CompressedP256Key(bytes: vector.state("created").fields.activeKey.bytes)
        #expect(vector.discriminator.bytes == SmartWallet.discriminator)
        #expect(vector.size == SmartWallet.space)
        #expect(SmartWallet.Filter.activeKey(key).offset == vector.offsets.activeKey)
        #expect((0..<maxGuardians).map { SmartWallet.Filter.guardian(key, slot: $0).offset } == vector.offsets.guardians.map(\.kind))
        #expect(vector.offsets.guardians.allSatisfy { $0.key == $0.kind + 1 })
        #expect(SmartWallet.Filter.proposal(to: key).offset == vector.offsets.rotation.pending)
        #expect(vector.offsets.rotation.newKey == vector.offsets.rotation.pending + 1)
    }

    @Test(arguments: try (loadVector("state") as StateVector).states)
    func decodesTheVector(_ vector: NamedStateVector) throws {
        let state = try SmartWallet(data: vector.data.bytes)
        let fields = vector.fields
        #expect(state.walletId == fields.walletId.bytes)
        #expect(state.activeKey.bytes == fields.activeKey.bytes)
        #expect(state.nonce == fields.nonce)
        #expect(state.attested == fields.attested)
        #expect(state.guardians == (try fields.guardians.map { try $0.guardian }))
        let rotation = fields.rotation
        let pending = SmartWallet.PendingRotation(
            newKey: try CompressedP256Key(bytes: rotation.newKey.bytes),
            proposedAt: rotation.proposedAt,
            proposedBy: rotation.proposedBy
        )
        #expect(state.rotation == (rotation.pending ? pending : nil))
        #expect(state.stateBump == fields.stateBump)
        #expect(state.vaultBump == fields.vaultBump)
    }

    /// Each filter finds the wallet by the key where it looks, and only
    /// there. The passkey in slot 2 is no P256 guardian, and the zeros of an
    /// empty slot or of no rotation match no key.
    @Test func filtersFindTheKeysOfTheVector() throws {
        let recovering = try vector.state("recovering")
        let data = recovering.data.bytes
        let activeKey = try CompressedP256Key(bytes: recovering.fields.activeKey.bytes)
        let guardian = try CompressedP256Key(bytes: recovering.fields.guardians[1].key.bytes)
        let passkey = try CompressedP256Key(bytes: recovering.fields.guardians[2].key.bytes)
        let newKey = try CompressedP256Key(bytes: recovering.fields.rotation.newKey.bytes)

        #expect(SmartWallet.Filter.activeKey(activeKey).matches(data))
        #expect(SmartWallet.Filter.guardian(guardian, slot: 1).matches(data))
        #expect(!SmartWallet.Filter.guardian(guardian, slot: 0).matches(data))
        #expect(!SmartWallet.Filter.guardian(passkey, slot: 2).matches(data))
        #expect(SmartWallet.Filter.proposal(to: newKey).matches(data))
        #expect(!SmartWallet.Filter.activeKey(newKey).matches(data))
        #expect(!SmartWallet.Filter.proposal(to: newKey).matches(try vector.state("created").data.bytes))
    }

    /// The states the other tests read are the program's bytes: the
    /// vector's new wallet is `SoftwareKey.test`'s.
    @Test func testStatesAreWrittenLikeTheProgram() throws {
        #expect(stateData() == (try vector.state("created").data.bytes))
    }

    @Test func rejectsOtherBytes() throws {
        let created = try vector.state("created").data.bytes
        var other = created
        other[0] ^= 1
        #expect(throws: AccountError.wrongDiscriminator) { try SmartWallet(data: other) }
        #expect(throws: AccountError.truncated) { try SmartWallet(data: Array(created.dropLast())) }

        // `attested`, a guardian's kind, the rotation's `pending`.
        for offset in [vector.offsets.attested, vector.offsets.guardians[2].kind, vector.offsets.rotation.pending] {
            var badTag = created
            badTag[offset] = 3
            #expect(throws: AccountError.invalidTag(3)) { try SmartWallet(data: badTag) }
        }
    }
}
