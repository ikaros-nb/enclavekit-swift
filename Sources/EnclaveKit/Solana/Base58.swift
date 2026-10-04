//
//  Base58.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    static func encode(_ bytes: [UInt8]) -> String {
        var digits: [UInt8] = [] // base 58, least significant first
        for byte in bytes {
            var carry = Int(byte)
            for i in digits.indices {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        let zeros = bytes.prefix { $0 == 0 }.count
        let chars = [UInt8](repeating: alphabet[0], count: zeros) + digits.reversed().map { alphabet[Int($0)] }
        return String(decoding: chars, as: UTF8.self)
    }

    static func decode(_ string: String) -> [UInt8]? {
        var bytes: [UInt8] = [] // base 256, least significant first
        for char in string.utf8 {
            guard let value = alphabet.firstIndex(of: char) else { return nil }
            var carry = value
            for i in bytes.indices {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }
        let zeros = string.utf8.prefix { $0 == alphabet[0] }.count
        return [UInt8](repeating: 0, count: zeros) + bytes.reversed()
    }
}
