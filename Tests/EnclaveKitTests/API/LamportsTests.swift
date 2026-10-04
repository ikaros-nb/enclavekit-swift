//
//  LamportsTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 04/10/2026.
//

import EnclaveKit
import Testing

struct LamportsTests {
    @Test(arguments: [
        (0, "0 SOL"),
        (1, "0.000000001 SOL"),
        (10_000_000, "0.01 SOL"),
        (1_813_560, "0.00181356 SOL"),
        (5_000_000_000, "5 SOL"),
        (UInt64.max, "18446744073.709551615 SOL"),
    ] as [(UInt64, String)])
    func formatted(_ lamports: UInt64, _ text: String) {
        #expect(Lamports(lamports).formatted == text)
    }

    @Test(arguments: [
        ("0.01", 10_000_000),
        ("0,01", 10_000_000),
        (".5", 500_000_000),
        ("5.", 5_000_000_000),
        ("0", 0),
        ("0.000000001", 1),
        ("18446744073.709551615", UInt64.max),
    ] as [(String, UInt64)])
    func parsed(_ text: String, _ lamports: UInt64) {
        #expect(Lamports(sol: text) == Lamports(lamports))
    }

    @Test(arguments: ["", ".", "1.2.3", "1,000.5", "0.0000000001", "-1", "+1", " 1", "1e3", "18446744073.709551616", "99999999999"])
    func rejected(_ text: String) {
        #expect(Lamports(sol: text) == nil)
    }
}
