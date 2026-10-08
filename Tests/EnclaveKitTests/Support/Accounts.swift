//
//  Accounts.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation
@testable import EnclaveKit

/// An account as `getAccountInfo` returns it, owned by the program unless
/// told otherwise.
func accountJSON(owner: String = "dG4h3aizVEW1bKjzkGsfk6zqcfa2MVn2DjavPniesSY", data: [UInt8]) -> String {
    """
    {"data":["\(Data(data).base64EncodedString())","base64"],"executable":false,"lamports":2301240,
     "owner":"\(owner)","rentEpoch":18446744073709551615,"space":\(data.count)}
    """
}

/// A token account of `owner` holding `amount`, as `getTokenAccountsByOwner`
/// lists it: mint, owner, amount, then the rest of SPL Token's 165 bytes.
func tokenAccountJSON(owner: PublicKey, amount: UInt64, program: PublicKey) -> String {
    var data = [UInt8](repeating: 0xee, count: 32) + owner.bytes
    data.appendLittleEndian(amount)
    data += [UInt8](repeating: 0, count: 165 - data.count)
    let address = try! PublicKey(bytes: [UInt8](repeating: 0xdd, count: 32))
    return #"{"pubkey":"\#(address)","account":\#(accountJSON(owner: program.base58, data: data))}"#
}

/// The state of the wallet `owner`'s key made, nonce 1, not attested, as
/// the program writes it field after field: `activeKey`, `owner` unless
/// given; `guardian` in each slot of `slots`; `rotation` pending. Built
/// without the SDK's offsets, which the tests check against it.
func stateData(
    of owner: CompressedP256Key = SoftwareKey.test.publicKey,
    activeKey: CompressedP256Key? = nil,
    guardian: CompressedP256Key? = nil,
    inSlots slots: [Int] = [0],
    rotation: SmartWallet.PendingRotation? = nil
) -> [UInt8] {
    var data = SmartWallet.discriminator + walletId(of: owner) + (activeKey ?? owner).bytes
    data.appendLittleEndian(UInt64(1))
    data.append(0)
    for slot in 0..<maxGuardians {
        // Kind and key, zeros when empty, then a passkey's rpId hash: zeros.
        let borsh = (slots.contains(slot) ? guardian.map(Guardian.p256) : nil)?.borsh ?? Guardian.none.borsh
        data += borsh + [UInt8](repeating: 0, count: 66 - borsh.count)
    }
    data.append(rotation == nil ? 0 : 1)
    data += rotation?.newKey.bytes ?? [UInt8](repeating: 0, count: 33)
    data.appendLittleEndian(rotation?.proposedAt ?? 0)
    data.append(rotation?.proposedBy ?? 0)
    // The bumps, which nothing reads, as in the vector.
    data += [255, 255]
    return data
}

extension SmartWallet.Filter {
    /// What the RPC checks for a `memcmp` filter.
    func matches(_ data: [UInt8]) -> Bool {
        data.count >= offset + bytes.count && Array(data[offset..<offset + bytes.count]) == bytes
    }
}

/// `getProgramAccounts`' answer on a devnet that holds `states`: those that
/// pass every filter of `params`, as the RPC applies them. `nil` for a call
/// without filters, which the SDK never makes.
func programAccountsJSON(_ states: [[UInt8]], params: Any?) -> String? {
    guard let config = (params as? [Any])?.last as? [String: Any],
          let filters = config["filters"] as? [[String: Any]]
    else { return nil }
    let found = states.filter { data in
        filters.allSatisfy { filter in
            if let size = filter["dataSize"] as? Int { return data.count == size }
            guard let memcmp = filter["memcmp"] as? [String: Any],
                  let offset = memcmp["offset"] as? Int,
                  let bytes = (memcmp["bytes"] as? String).flatMap(Base58.decode)
            else { return false }
            return SmartWallet.Filter(offset: offset, bytes: bytes).matches(data)
        }
    }
    let accounts = found.map { data in
        #"{"pubkey":"\#(EnclaveKitProgram.walletAddress(walletId: Array(data[8..<40])))","account":\#(accountJSON(data: data))}"#
    }
    return "[\(accounts.joined(separator: ","))]"
}

/// What the wallet holds `seconds` after a guardian, in the first slot,
/// proposed `newKey`.
func rotation(to newKey: CompressedP256Key, secondsAgo seconds: Int64) -> SmartWallet.PendingRotation {
    SmartWallet.PendingRotation(newKey: newKey, proposedAt: Int64(Date.now.timeIntervalSince1970) - seconds, proposedBy: 0)
}
