//
//  Bytes.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

extension Array where Element == UInt8 {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
