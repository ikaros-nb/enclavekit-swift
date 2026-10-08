//
//  Wallet.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import Foundation

/// A smart wallet seen from one device: the device's key, which signs as
/// the wallet's owner or as one of its guardians, the relayer that pays,
/// the RPC that reads it. The app sees its owner's side, or a new device's
/// while it recovers the wallet; `GuardedWallet` shows a guardian's.
public struct Wallet: Sendable {
    public enum Status: Equatable, Sendable {
        /// No action yet. The address already receives; the first send
        /// creates the account, its rent part of that send's fee. Only
        /// for the wallet this device's key made: no other key may create
        /// it.
        case notOnChainYet
        /// This device signs for the wallet. `recovery`: a guardian proposed
        /// to move the wallet to another key. Not this user's doing? Cancel
        /// it before it opens.
        case active(recovery: Recovery?)
        /// A guardian proposed this device's key: from `recovery.opensAt`,
        /// `confirmRecovery()` moves the wallet here, and
        /// `confirmRecoveryWhenOpen()` waits for it. Until then, the owner
        /// can still cancel.
        case recovering(Recovery)
        /// Another key signs for the wallet: it moved away from this device,
        /// or the recovery toward it was cancelled, or lapsed. Also a
        /// wallet this device took on, closed since: only the key that
        /// made it could create it again, and SOL sent to its address
        /// stays there.
        case keyReplaced
    }

    /// The most guardians a wallet names.
    public static let maxGuardians = EnclaveKit.maxGuardians

    /// 5 000 lamports per signature: the relayer's Ed25519 one and the
    /// secp256r1 one the precompile checks.
    static let transactionFee: UInt64 = 10_000
    /// Seconds the enclave's authorisation stays valid on-chain.
    static let authorizationTTL: Int64 = 120
    /// A blockhash lives 150 slots, about a minute: past this the
    /// transaction can no longer land.
    static let confirmationTimeout: Duration = .seconds(90)

    let signer: any Signer
    /// SHA-256 of the key that made the wallet: the seed of both addresses.
    /// A rotation never changes it.
    let walletId: [UInt8]
    let cluster: Cluster
    /// What a confirmed close runs: the client's `deleteDeviceKey()`.
    /// Nothing for a key the Keychain does not hold.
    let deleteKey: @Sendable () throws -> Void
    private let rpc: SolanaRPC
    private let kora: Kora

    /// `walletId` defaults to the wallet `signer` made. Another one when the
    /// device recovered a wallet, or guards it.
    init(
        signer: any Signer,
        walletId: [UInt8]? = nil,
        kora: Kora,
        rpc: SolanaRPC = SolanaRPC(),
        cluster: Cluster = .devnet,
        deleteKey: @escaping @Sendable () throws -> Void = {}
    ) {
        self.signer = signer
        self.walletId = walletId ?? EnclaveKit.walletId(of: signer.publicKey)
        self.cluster = cluster
        self.deleteKey = deleteKey
        self.rpc = rpc
        self.kora = kora
    }

    var programId: PublicKey { cluster.programId }

    /// The wallet this device's key made: the only key the program lets
    /// create its state, on the first action.
    var madeByThisKey: Bool { walletId == EnclaveKit.walletId(of: signer.publicKey) }

    /// The same through every rotation: what `recoverWallet(_:)` takes on
    /// and `forgetWallet(_:)` hides. No device needs to show it: each finds
    /// the wallets that name its key.
    public var id: ID { ID(bytes: walletId) }

    /// This device's key, for another wallet to name as guardian: show it as
    /// a QR code.
    public var deviceKey: DeviceKey { DeviceKey(signer.publicKey) }

    /// Where to send SOL to this wallet: the vault. Receives before the
    /// first action.
    public var address: PublicKey {
        EnclaveKitProgram.vaultAddress(walletId: walletId, programId: programId)
    }

    /// The vault's page: balance, every transaction in and out.
    public var explorerURL: URL {
        cluster.explorerURL("address/\(address)")
    }

    public func balance() async throws -> Lamports {
        Lamports(try await rpc.balance(address))
    }

    public func status() async throws -> Status {
        status(in: try await state())
    }

    /// What `state`, already read, says of this device's key.
    func status(in state: SmartWallet?) -> Status {
        guard let state else { return madeByThisKey ? .notOnChainYet : .keyReplaced }
        let recovery = recovery(in: state)
        if state.activeKey == signer.publicKey { return .active(recovery: recovery) }
        if let recovery, recovery.newKey == deviceKey { return .recovering(recovery) }
        return .keyReplaced
    }

    /// The devices that may start a recovery, none before the first action.
    public func guardians() async throws -> [DeviceKey] {
        try await state()?.guardians.compactMap { guardian in
            guard case let .p256(key) = guardian else { return nil }
            return DeviceKey(key)
        } ?? []
    }

    /// `nil` until the first action creates the state. An account the
    /// program does not own is no state either: anyone can send lamports to
    /// the address before it exists.
    func state() async throws -> SmartWallet? {
        let stateAddress = EnclaveKitProgram.walletAddress(walletId: walletId, programId: programId)
        guard let account = try await rpc.accountInfo(stateAddress), account.owner == programId else { return nil }
        return try SmartWallet(data: account.data)
    }

    /// The proposal pending in `state`. `nil` once it lapsed: it no longer
    /// blocks anything.
    func recovery(in state: SmartWallet) -> Recovery? {
        state.rotation.map { Recovery($0, cluster: cluster) }.flatMap { $0.closesAt > .now ? $0 : nil }
    }

    /// A transfer for the user to approve. Reads the state and the balance,
    /// and refuses here, before any Face ID, what the vault cannot pay.
    public func prepareTransfer(_ amount: Lamports, to recipient: PublicKey) async throws -> ActionRequest {
        try await prepare(.transferSol(to: recipient, lamports: amount.value), spending: amount)
    }

    /// Replaces the whole list, and cancels any recovery in progress. At most
    /// `maxGuardians`, or `tooManyGuardians`; an empty list removes them all.
    public func prepareSetGuardians(_ guardians: [DeviceKey]) async throws -> ActionRequest {
        guard guardians.count <= Self.maxGuardians else { throw EnclaveKitError.tooManyGuardians }
        let slots = guardians.map { Guardian.p256($0.key) } + Array(repeating: .none, count: Self.maxGuardians - guardians.count)
        return try await prepare(.setGuardians(slots))
    }

    /// Stops the recovery a guardian started: the wallet stays with this
    /// device. Possible until someone confirms it.
    public func prepareCancelRecovery() async throws -> ActionRequest {
        try await prepare(.cancelRotation)
    }

    /// Moves the wallet to `newKey`, the key another device shows, as soon
    /// as the transaction confirms: this device still holds the wallet's key,
    /// so no delay, no guardian. From then on this device's status is
    /// `keyReplaced`; the other device finds the wallet with
    /// `recoverableWallets()` and takes it on with `recoverWallet(_:)`.
    /// Ends any recovery in progress. Throws
    /// `notOnChainYet` before the first action, `keyInUse` if the wallet
    /// already names `newKey`: this device's own, or a guardian's.
    public func prepareMove(to newKey: DeviceKey) async throws -> ActionRequest {
        guard let state = try await state() else {
            throw madeByThisKey ? EnclaveKitError.notOnChainYet : EnclaveKitError.keyReplaced
        }
        // A guardian signing the same action only proposes: not a move.
        guard state.activeKey == signer.publicKey else { throw EnclaveKitError.keyReplaced }
        guard newKey.key != state.activeKey, !state.guardians.contains(.p256(newKey.key)) else {
            throw EnclaveKitError.keyInUse
        }
        return try await prepare(.proposeRotation(newKey: newKey.key), over: state, summary: Action.movePhrase(to: newKey.key))
    }

    /// Everything the vault holds, the relayer's refund aside, to
    /// `recipient`: the program reads the amount as it executes, so the
    /// summary names none. The wallet stays, guardians included, and its
    /// address receives again.
    public func prepareTransferAll(to recipient: PublicKey) async throws -> ActionRequest {
        let action = Action.sweepVault(to: recipient)
        let state = try await state()
        try requireAuthority(over: state, for: action)
        guard let maxFee = try await sweepFee(state) else { throw EnclaveKitError.insufficientFunds(available: 0) }
        return ActionRequest(maxFee: maxFee, action: action, wallet: self)
    }

    /// Sends everything the vault holds to `destination` and closes the
    /// wallet's account, then deletes this device's key once confirmed:
    /// nothing signs for this address again. As with `deleteDeviceKey()`,
    /// the wallets this device guards lose it as guardian. Throws
    /// `tokensLeft` while a token account of the vault holds a balance.
    /// A wallet that never acted has no account to close: its vault is
    /// emptied, then the key goes all the same; `nothingToClose` when it
    /// holds no more than the fee.
    public func prepareClose(to destination: PublicKey) async throws -> ActionRequest {
        let state = try await state()
        let action: Action = state == nil ? .sweepVault(to: destination) : .closeWallet(to: destination)
        try requireAuthority(over: state, for: action)
        try await requireNoTokens()
        let maxFee: Lamports
        if state == nil {
            guard let sweepFee = try await sweepFee(state) else { throw EnclaveKitError.nothingToClose }
            maxFee = sweepFee
        } else {
            // The program caps the refund at the balance: an emptied vault
            // closes too.
            maxFee = Lamports(try await relayerFee(state))
        }
        return ActionRequest(maxFee: maxFee, action: action, wallet: self, afterConfirmation: deleteKey)
    }

    /// The vault pays `amount`, the relayer's refund, and keeps its own rent:
    /// the program refuses less. Only `sweep_vault` and `close_wallet` empty
    /// it.
    func prepare(_ action: Action, spending amount: Lamports = 0) async throws -> ActionRequest {
        try await prepare(action, over: try await state(), spending: amount)
    }

    /// Same, with the state already read. `summary`: another sentence than
    /// the action's own.
    private func prepare(
        _ action: Action,
        over state: SmartWallet?,
        spending amount: Lamports = 0,
        summary: String? = nil
    ) async throws -> ActionRequest {
        try requireAuthority(over: state, for: action)
        let maxFee = try await relayerFee(state)
        let reserved = maxFee + (try await rpc.minimumBalanceForRentExemption(space: 0))
        let balance = try await rpc.balance(address)
        guard balance >= reserved, amount.value <= balance - reserved else {
            throw EnclaveKitError.insufficientFunds(available: Lamports(balance > reserved ? balance - reserved : 0))
        }
        return ActionRequest(maxFee: Lamports(maxFee), action: action, wallet: self, summary: summary)
    }

    /// Signs `action` with the enclave, has Kora send it, returns once
    /// confirmed. One Face ID. `maxRelayerFee` is the ceiling the user
    /// approved; the nonce and the expiry are read now, right before.
    func execute(_ action: Action, maxRelayerFee: UInt64) async throws -> Receipt {
        let state = try await state()
        try requireAuthority(over: state, for: action)
        // Lower than approved if another send created the state meanwhile.
        let relayerFee = min(try await relayerFee(state), maxRelayerFee)
        let relayer = try await kora.payerSigner()
        let preimage = Preimage(
            programId: programId,
            walletId: walletId,
            nonce: state?.nonce ?? 0,
            expiresAt: Int64(Date.now.timeIntervalSince1970) + Self.authorizationTTL,
            maxRelayerFee: maxRelayerFee,
            action: action
        )
        // Before Face ID: an action without handler throws here.
        let instruction = try EnclaveKitProgram.instruction(executing: preimage, relayer: relayer, relayerFee: relayerFee)

        let signature = try await signer.sign(preimage.bytes)
        return try await send(
            [
                Secp256r1Program.instruction(publicKey: signer.publicKey, signature: signature, message: preimage.bytes),
                instruction,
            ],
            payer: relayer
        )
    }

    /// Ends the recovery toward this device once it opened: the wallet's key
    /// becomes this device's. Nothing to sign, no Face ID: the relayer pays
    /// the fee. Throws `recoveryNotOpen` before `opensAt`, `noRecovery` if
    /// none is pending toward this device.
    public func confirmRecovery() async throws -> Receipt {
        try await confirmRecovery(retryingEvery: .seconds(1))
    }

    /// Waits for the recovery toward this device to open, then confirms
    /// it: started as soon as `status()` says `recovering`, it leaves the
    /// user nothing to tap. Reads the state again once the delay is over: a
    /// guardian who proposed again pushed `opensAt` back, and the wait goes
    /// on. Throws `noRecovery` if none is pending toward this device by
    /// then, the owner cancelled for instance, and `CancellationError` if
    /// the task is cancelled while it waits: the app starts it again when
    /// the screen comes back.
    public func confirmRecoveryWhenOpen() async throws -> Receipt {
        while true {
            guard case let .recovering(recovery) = try await status() else { throw EnclaveKitError.noRecovery }
            let wait = recovery.opensAt.timeIntervalSinceNow
            if wait <= 0 { return try await confirmRecovery() }
            try await Task.sleep(for: .seconds(wait))
        }
    }

    /// The program reads the cluster's clock, a second or so behind this
    /// device's: past `opensAt`, a "too early" is tried again.
    func confirmRecovery(retryingEvery delay: Duration, attempts: Int = 10) async throws -> Receipt {
        guard case let .recovering(recovery) = try await status() else { throw EnclaveKitError.noRecovery }
        guard recovery.opensAt <= .now else { throw EnclaveKitError.recoveryNotOpen(opensAt: recovery.opensAt) }
        for _ in 0..<attempts {
            do {
                return try await confirmRotation()
            } catch let EnclaveKitError.rejected(reason) where reason.contains(EnclaveKitProgram.rotationTooEarly) {
                try await Task.sleep(for: delay)
            }
        }
        throw EnclaveKitError.recoveryNotOpen(opensAt: recovery.opensAt)
    }

    /// Swaps in the key a guardian proposed, once the timelock has passed.
    /// Nothing to sign, no Face ID: anyone may send it, the relayer pays the
    /// fee and gets nothing back.
    func confirmRotation() async throws -> Receipt {
        try await send(
            [EnclaveKitProgram.confirmRotation(walletId: walletId, programId: programId)],
            payer: try await kora.payerSigner()
        )
    }

    /// The active key signs every action. A guardian only proposes a new
    /// key. Before the first action there is no state: the key that made
    /// the wallet creates it, and there is no guardian yet.
    private func requireAuthority(over state: SmartWallet?, for action: Action) throws {
        let key = signer.publicKey
        if state.map({ $0.activeKey == key }) ?? madeByThisKey { return }
        guard case .proposeRotation = action else { throw EnclaveKitError.keyReplaced }
        guard state?.guardians.contains(.p256(key)) == true else { throw EnclaveKitError.notAGuardian }
    }

    /// The relayer's refund for emptying the vault, `nil` when it would
    /// leave nothing to send. The program refuses a refund the balance
    /// cannot cover.
    private func sweepFee(_ state: SmartWallet?) async throws -> Lamports? {
        let maxFee = try await relayerFee(state)
        return try await rpc.balance(address) > maxFee ? Lamports(maxFee) : nil
    }

    /// The program cannot list the vault's token accounts: the SDK reads
    /// them before the key goes.
    private func requireNoTokens() async throws {
        guard try await rpc.tokenAmounts(owner: address).allSatisfy({ $0 == 0 }) else {
            throw EnclaveKitError.tokensLeft
        }
    }

    /// Kora signs as fee payer and sends, then the cluster confirms.
    private func send(_ instructions: [Instruction], payer relayer: PublicKey) async throws -> Receipt {
        // Not signed by the enclave: fetched last, after any Face ID, it
        // keeps its whole life.
        let blockhash = try await kora.blockhash()
        let message = Message(instructions: instructions, payer: relayer, recentBlockhash: blockhash)
        let receipt: Receipt
        do {
            receipt = self.receipt(try await kora.signAndSend(message))
        } catch let JSONRPCError.server(_, reason) {
            // Kora simulates first: what fails there is never sent.
            throw EnclaveKitError.rejected(reason: reason)
        }
        try await confirm(receipt)
        return receipt
    }

    private func receipt(_ signature: String) -> Receipt {
        Receipt(signature: signature, explorerURL: cluster.explorerURL("tx/\(signature)"))
    }

    /// What the relayer advances and the vault pays back: the fee, and on
    /// the first action the rent of the state.
    private func relayerFee(_ state: SmartWallet?) async throws -> UInt64 {
        let rent = state == nil ? try await rpc.minimumBalanceForRentExemption(space: SmartWallet.space) : 0
        return rent + Self.transactionFee
    }

    private func confirm(_ receipt: Receipt) async throws {
        let deadline = ContinuousClock.now + Self.confirmationTimeout
        while ContinuousClock.now < deadline {
            if let status = try await rpc.signatureStatus(receipt.signature) {
                if let error = status.error { throw EnclaveKitError.failed(receipt, reason: "\(error)") }
                if status.confirmationStatus == .confirmed || status.confirmationStatus == .finalized { return }
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw EnclaveKitError.notConfirmed(receipt)
    }
}
