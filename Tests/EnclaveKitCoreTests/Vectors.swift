//
//  Vectors.swift.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Foundation
import Testing
@testable import EnclaveKitCore

/// Reads `Vectors/<name>.json`, copied from enclavekit-anchor by scripts/sync-vectors.sh.
func loadVector<T: Decodable>(_ name: String) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Vectors"))
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(contentsOf: url))
}

/// Bytes written as a lowercase hex string.
struct Hex: Decodable, Equatable {
    let bytes: [UInt8]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let chars = Array(string.utf8)
        guard chars.count.isMultiple(of: 2) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "odd hex length")
        }
        bytes = try stride(from: 0, to: chars.count, by: 2).map { i in
            guard let byte = UInt8(String(decoding: chars[i...i + 1], as: UTF8.self), radix: 16) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not hex: \(string)")
            }
            return byte
        }
    }
}

struct PDAVector: Decodable {
    let address: String
    let bump: UInt8
}

struct KeyVector: Decodable {
    let privateKey: Hex
    let compressedPubkey: Hex
    let walletId: Hex
    let programId: String
    let wallet: PDAVector
    let vault: PDAVector
}
