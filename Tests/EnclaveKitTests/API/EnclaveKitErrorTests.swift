//
//  EnclaveKitErrorTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

/// What the app shows: `localizedDescription`, never "error 1".
struct EnclaveKitErrorTests {
    @Test func insufficientFundsSaysHowMuch() {
        let error: Error = EnclaveKitError.insufficientFunds(available: 17_526_200)
        #expect(error.localizedDescription == "This wallet can send at most 0.0175262 SOL: it keeps enough for the fee and its own rent.")
    }

    /// Internal, yet readable once it reaches the app.
    @Test func networkErrorsReadWell() {
        let error: Error = JSONRPCError.httpStatus(401)
        #expect(error.localizedDescription == "The server answered with HTTP status 401.")
    }

    @Test func receiptOnlyOnceSent() {
        let receipt = ActionRequestTests.sent
        #expect(EnclaveKitError.notConfirmed(receipt).receipt == receipt)
        #expect(EnclaveKitError.rejected(reason: "simulation failed").receipt == nil)
    }
}
