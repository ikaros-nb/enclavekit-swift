//
//  Secp256r1Program.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

/// The instruction placed before every EnclaveKit instruction. The runtime checks the signature;
/// the program then reads this instruction back through the Instructions sysvar.
enum Secp256r1Program {
    static let id = try! PublicKey(base58: "Secp256r1SigVerify1111111111111111111111111")

    private static let publicKeyOffset: UInt16 = 16   // 2 + 14
    private static let signatureOffset: UInt16 = 49   // 16 + 33
    private static let messageOffset: UInt16 = 113    // 49 + 64
    /// "In this instruction".
    private static let currentInstruction = UInt16.max

    /// Layout of `new_secp256r1_instruction_with_signature`, which the program
    /// checks strictly. The signature is normalised to low-S here, so callers
    /// can pass the Secure Enclave output as is.
    static func instruction(publicKey: CompressedP256Key, signature: [UInt8], message: [UInt8]) -> Instruction {
        var data: [UInt8] = [1, 0] // one signature, padding
        data.appendLittleEndian(signatureOffset)
        data.appendLittleEndian(currentInstruction)
        data.appendLittleEndian(publicKeyOffset)
        data.appendLittleEndian(currentInstruction)
        data.appendLittleEndian(messageOffset)
        data.appendLittleEndian(UInt16(message.count))
        data.appendLittleEndian(currentInstruction)
        data += publicKey.bytes
        data += LowS.normalize(signature)
        data += message
        return Instruction(programId: id, accounts: [], data: data)
    }
}
