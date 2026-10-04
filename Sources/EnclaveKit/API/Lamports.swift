//
//  Lamports.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 04/10/2026.
//

import Foundation

/// An amount of SOL, counted in lamports like the chain does: 1 SOL is
/// 10^9 lamports. Integers only: through a `Double`, "0.00000003" SOL
/// becomes 29 lamports.
public struct Lamports: Hashable, Comparable, Sendable {
    public static let perSOL: UInt64 = 1_000_000_000
    static let decimals = 9

    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    /// What the user typed: "0.01", "0,01" (the decimal pad follows the
    /// region), ".5". `nil` for anything else, more than 9 decimals, or more
    /// than `UInt64.max` lamports.
    public init?(sol text: String) {
        let separator = text.firstIndex { $0 == "." || $0 == "," }
        let whole = separator.map { text[..<$0] } ?? text[...]
        let fraction = separator.map { text[text.index(after: $0)...] } ?? ""
        // `UInt64("+1")` is 1: check the digits first.
        guard whole.count + fraction.count > 0,
              fraction.count <= Self.decimals,
              (whole + fraction).allSatisfy({ ("0"..."9").contains($0) })
        else { return nil }

        let padded = fraction + String(repeating: "0", count: Self.decimals - fraction.count)
        guard let units = whole.isEmpty ? 0 : UInt64(whole), let lamports = UInt64(padded) else { return nil }
        let (scaled, overflow) = units.multipliedReportingOverflow(by: Self.perSOL)
        let (total, carry) = scaled.addingReportingOverflow(lamports)
        guard !overflow, !carry else { return nil }
        value = total
    }

    /// "0.01 SOL": no trailing zeros, a dot whatever the region.
    public var formatted: String {
        let whole = value / Self.perSOL
        let fraction = value % Self.perSOL
        guard fraction > 0 else { return "\(whole) SOL" }
        var digits = String(fraction)
        digits = String(repeating: "0", count: Self.decimals - digits.count) + digits
        while digits.last == "0" { digits.removeLast() }
        return "\(whole).\(digits) SOL"
    }

    public static func < (lhs: Lamports, rhs: Lamports) -> Bool {
        lhs.value < rhs.value
    }
}

extension Lamports: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(value)
    }
}

extension Lamports: CustomStringConvertible {
    public var description: String { formatted }
}
