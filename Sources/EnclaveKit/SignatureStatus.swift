//
//  SignatureStatus.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

public struct SignatureStatus: Equatable, Sendable, Decodable {
    public enum Commitment: String, Sendable, Decodable {
        case processed, confirmed, finalized
    }

    public let confirmationStatus: Commitment?
    /// Set when the transaction landed but failed: fee paid, no effect.
    public let error: TransactionError?

    private enum CodingKeys: String, CodingKey {
        case confirmationStatus
        case error = "err"
    }
}

/// Why a landed transaction failed: the `err` field of the RPC.
public enum TransactionError: Error, Equatable, Sendable {
    /// Instruction `instruction` returned a program error. For EnclaveKit,
    /// Anchor numbers its errors from 6000.
    case custom(instruction: UInt8, code: UInt32)
    /// Instruction `instruction` failed in the runtime, e.g. `InvalidArgument`.
    case instruction(UInt8, String)
    /// The transaction failed as a whole, e.g. `InsufficientFundsForRent`.
    case transaction(String)
}

extension TransactionError: Decodable {
    public init(from decoder: Decoder) throws {
        let error = try RustEnum(from: decoder)
        guard error.variant == "InstructionError", let payload = error.payload else {
            self = .transaction(error.variant)
            return
        }
        // `[index, error]`, the error itself a Rust enum.
        var pair = try payload.unkeyedContainer()
        let index = try pair.decode(UInt8.self)
        let failure = try pair.decode(RustEnum.self)
        if failure.variant == "Custom", let code = failure.payload {
            self = .custom(instruction: index, code: try code.singleValueContainer().decode(UInt32.self))
        } else {
            self = .instruction(index, failure.variant)
        }
    }
}

/// A Rust enum as serde writes it: `"Variant"` without data,
/// `{ "Variant": <payload> }` with data.
private struct RustEnum: Decodable {
    let variant: String
    let payload: (any Decoder)?

    init(from decoder: Decoder) throws {
        if let variant = try? decoder.singleValueContainer().decode(String.self) {
            self.variant = variant
            payload = nil
            return
        }
        let object = try decoder.container(keyedBy: VariantKey.self)
        guard object.allKeys.count == 1, let key = object.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "expected one variant"))
        }
        variant = key.stringValue
        payload = try object.superDecoder(forKey: key)
    }

    private struct VariantKey: CodingKey {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}
