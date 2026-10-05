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
/// of `SoftwareKey.test`, with `activeKey` and `attested` as given, and
/// `guardian` in the first slot.
func stateData(activeKey: CompressedP256Key = SoftwareKey.test.publicKey, attested: Bool = false, guardian: CompressedP256Key? = nil) -> [UInt8] {
    var data = SmartWalletTests.devnetAccount
    data.replaceSubrange(8..<73, with: walletId(of: SoftwareKey.test.publicKey) + activeKey.bytes)
    data[81] = attested ? 1 : 0
    if let guardian {
        // No rotation (82): the first slot's `None` is at 83. The account
        // keeps its size, the zeros at its end make room.
        data.replaceSubrange(83...83, with: [1] + guardian.bytes)
        data.removeLast(guardian.bytes.count)
    }
    return data
}
