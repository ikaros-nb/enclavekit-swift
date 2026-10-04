//
//  Consent.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

extension Action {
    /// The sentence the user approves before Face ID. Addresses and keys in
    /// full: a look-alike address only has to match the shortened form.
    var consentPhrase: String {
        switch self {
        case let .transferSol(to, lamports):
            "Send \(Lamports(lamports)) to \(to)"
        case let .transferToken(mint, to, amount):
            "Send \(amount) base units of the token \(mint) to \(to)"
        case let .proposeRotation(newKey):
            "Move this wallet to the key \(newKey.hex)"
        case .cancelRotation:
            "Cancel the pending key rotation"
        case let .setGuardians(guardians):
            guardians.allSatisfy { $0 == .none }
                ? "Remove every guardian"
                : "Set the guardians to " + guardians.compactMap(\.consentName).joined(separator: ", ")
        case let .sweepVault(to):
            "Send the whole balance to \(to)"
        case let .closeWallet(to):
            "Close this wallet and send everything to \(to)"
        }
    }
}

extension Guardian {
    fileprivate var consentName: String? {
        switch self {
        case .none: nil
        case .p256(let key): key.hex
        case .webAuthn(let key): "passkey \(key.hex)"
        }
    }
}

extension CompressedP256Key {
    var hex: String {
        bytes.map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined()
    }
}
