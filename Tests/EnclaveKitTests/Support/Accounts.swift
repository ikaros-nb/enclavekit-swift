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
    {"data":["\(Data(data).base64EncodedString())","base64"],"executable":false,"lamports":1813560,
     "owner":"\(owner)","rentEpoch":18446744073709551615,"space":\(data.count)}
    """
}

/// The devnet account of `SmartWalletTests` (nonce 1), moved to the wallet
/// of `SoftwareKey.test`, with `activeKey`, `attested` and `rotation` as
/// given, and `guardian` in the first slot.
func stateData(
    activeKey: CompressedP256Key = SoftwareKey.test.publicKey,
    attested: Bool = false,
    guardian: CompressedP256Key? = nil,
    rotation: SmartWallet.PendingRotation? = nil
) -> [UInt8] {
    let devnet = SmartWalletTests.devnetAccount
    var data = Array(devnet.prefix(82)) // up to `attested`
    data.replaceSubrange(8..<73, with: walletId(of: SoftwareKey.test.publicKey) + activeKey.bytes)
    data[81] = attested ? 1 : 0
    if let rotation {
        data += [1] + rotation.newKey.bytes
        data.appendLittleEndian(rotation.proposedAt)
        data.append(rotation.proposedBy)
    } else {
        data.append(0)
    }
    data += [guardian.map(Guardian.p256) ?? .none, .none, .none].flatMap(\.borsh)
    data += devnet[86..<88] // the bumps, after a `None` rotation and three `None` guardians
    data += [UInt8](repeating: 0, count: SmartWallet.space - data.count)
    return data
}

/// What the wallet holds `seconds` after a guardian, in the first slot,
/// proposed `newKey`.
func rotation(to newKey: CompressedP256Key, secondsAgo seconds: Int64) -> SmartWallet.PendingRotation {
    SmartWallet.PendingRotation(newKey: newKey, proposedAt: Int64(Date.now.timeIntervalSince1970) - seconds, proposedBy: 0)
}
