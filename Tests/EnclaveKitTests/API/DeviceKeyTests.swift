//
//  DeviceKeyTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Testing
@testable import EnclaveKit

struct DeviceKeyTests {
    let key = DeviceKey(SoftwareKey.test.publicKey)

    /// The compressed key of key.json, in the QR code as in the consent
    /// sentence the guardian approves.
    @Test func textIsWhatTheConsentShows() throws {
        #expect(key.description == "02515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f")
        #expect(try DeviceKey(key.description) == key)
        #expect(Action.proposeRotation(newKey: key.key).consentPhrase == "Move this wallet to the key \(key)")
    }

    @Test func uppercaseIsTheSameKey() throws {
        #expect(try DeviceKey(key.description.uppercased()) == key)
    }

    @Test(arguments: [
        "",
        "02abc",
        "zz" + String(repeating: "00", count: 32),
        // 32 bytes
        "02" + String(repeating: "00", count: 31),
        // x = 1 is not on the curve
        "02" + String(repeating: "00", count: 31) + "01",
        // the vault of key.json
        "hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK",
    ])
    func rejectsWhatIsNotAKey(_ text: String) {
        #expect(throws: KeyError.notADeviceKey) { try DeviceKey(text) }
    }
}
