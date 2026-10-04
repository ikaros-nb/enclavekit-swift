//
//  Ed25519.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

/// Just enough arithmetic mod p = 2^255 - 19 to tell whether 32 bytes
/// decode to a point of Ed25519. Port of TweetNaCl: 16 limbs of 16 bits,
/// least significant first, in Int64 so sums and products never overflow.
enum Ed25519 {
    typealias Field = [Int64]

    /// d = -121665 / 121666, the curve constant.
    private static let d: Field = [
        0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
        0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203,
    ]
    private static let one: Field = [1] + Field(repeating: 0, count: 15)

    /// Same rule as curve25519-dalek's `CompressedEdwardsY::decompress`:
    /// on the curve iff x² = (y² - 1) / (d·y² + 1) has a square root.
    static func isOnCurve(_ bytes: [UInt8]) -> Bool {
        precondition(bytes.count == 32)
        let y = unpack(bytes)
        let y2 = square(y)
        let num = sub(y2, one)            // y² - 1
        let den = add(mul(d, y2), one)    // d·y² + 1

        // Candidate root: x = num · den³ · (num · den⁷)^((p-5)/8)
        let den2 = square(den)
        let den4 = square(den2)
        let den6 = mul(den4, den2)
        var t = mul(mul(den6, num), den)  // num · den⁷
        t = pow2523(t)
        let x = mul(mul(mul(mul(t, num), den), den), den)

        // x is a root of num/den, or of -num/den (then x·√-1 is the root).
        let check = mul(square(x), den)
        return pack(check) == pack(num) || pack(add(check, num)) == pack(Field(repeating: 0, count: 16))
    }

    private static func unpack(_ bytes: [UInt8]) -> Field {
        var out = Field(repeating: 0, count: 16)
        for i in 0..<16 {
            out[i] = Int64(bytes[2 * i]) + (Int64(bytes[2 * i + 1]) << 8)
        }
        out[15] &= 0x7fff // the top bit is the sign of x, not part of y
        return out
    }

    /// Canonical 32-byte encoding, fully reduced mod p.
    private static func pack(_ n: Field) -> [UInt8] {
        var t = n
        carry(&t); carry(&t); carry(&t)
        for _ in 0..<2 {
            var m = Field(repeating: 0, count: 16)
            m[0] = t[0] - 0xffed
            for i in 1..<15 {
                m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1)
                m[i - 1] &= 0xffff
            }
            m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1)
            let borrow = (m[15] >> 16) & 1
            m[14] &= 0xffff
            if borrow == 0 { t = m } // t >= p: keep t - p
        }
        var out = [UInt8](repeating: 0, count: 32)
        for i in 0..<16 {
            out[2 * i] = UInt8(t[i] & 0xff)
            out[2 * i + 1] = UInt8(t[i] >> 8)
        }
        return out
    }

    private static func carry(_ o: inout Field) {
        for i in 0..<16 {
            o[i] += 1 << 16
            let c = o[i] >> 16
            if i < 15 { o[i + 1] += c - 1 } else { o[0] += 38 * (c - 1) } // 2^256 ≡ 38
            o[i] -= c << 16
        }
    }

    private static func add(_ a: Field, _ b: Field) -> Field { (0..<16).map { a[$0] + b[$0] } }
    private static func sub(_ a: Field, _ b: Field) -> Field { (0..<16).map { a[$0] - b[$0] } }
    private static func square(_ a: Field) -> Field { mul(a, a) }

    private static func mul(_ a: Field, _ b: Field) -> Field {
        var t = [Int64](repeating: 0, count: 31)
        for i in 0..<16 {
            for j in 0..<16 { t[i + j] += a[i] * b[j] }
        }
        for i in 0..<15 { t[i] += 38 * t[i + 16] }
        var o = Array(t[0..<16])
        carry(&o); carry(&o)
        return o
    }

    /// a^(2^252 - 3), that is a^((p-5)/8).
    private static func pow2523(_ a: Field) -> Field {
        var c = a
        for i in stride(from: 250, through: 0, by: -1) {
            c = square(c)
            if i != 1 { c = mul(c, a) }
        }
        return c
    }
}
