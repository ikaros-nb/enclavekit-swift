//
//  KeychainTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import Foundation
import Security
import Testing
@testable import EnclaveKit

/// On the Mac the items land in the login keychain, each test under its own
/// account, deleted at the end.
final class KeychainTests {
    let account = "test-\(UUID().uuidString)"

    deinit {
        try? Keychain.delete(account)
    }

    @Test func missingItemIsNil() throws {
        #expect(try Keychain.read(account) == nil)
    }

    @Test func addNeverOverwrites() throws {
        try Keychain.add(Data([1]), account: account)
        #expect(throws: Keychain.Failure(status: errSecDuplicateItem)) {
            try Keychain.add(Data([2]), account: account)
        }
        #expect(try Keychain.read(account) == Data([1]))
    }

    @Test func deleteRemoves() throws {
        try Keychain.add(Data([1]), account: account)
        try Keychain.delete(account)
        #expect(try Keychain.read(account) == nil)
    }
}
