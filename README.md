# EnclaveKit for Swift

Swift SDK of EnclaveKit, a Solana smart wallet whose key lives in the iPhone's Secure Enclave.

The user approves each action as they unlock their iPhone: Face ID, Touch ID or the passcode. The key signs inside the Secure Enclave, the program checks the signature through the `secp256r1` precompile, and a Kora relayer pays the fee, refunded from the wallet. The iPhone that signs can move the wallet to another one at once. Guardians, the user's other Apple devices, can move it to a new key after a timelock, when that iPhone is lost. Each device finds its wallets on-chain from its own key: one QR code per step, always a device key.

- The program and the relayer config: [enclavekit-anchor](https://github.com/ikaros-nb/enclavekit-anchor).
- The demo app: `enclavekit-demo-ios`, next to this repository.

Devnet only, not audited.

## Recovery in v1: read this first

- **The key never leaves the Secure Enclave.** No export, no iCloud backup. It survives a reinstall of the app, not the loss, reset or replacement of the iPhone. To change iPhones, move the wallet before resetting the old one: see [Moving to another iPhone](#moving-to-another-iphone).
- **A guardian is the only way back.** In v1, a guardian is another Apple device running an EnclaveKit app: the owner scans its device key, and a wallet names up to 3. Without a guardian, a lost iPhone is a lost wallet. Tell your users at enrollment, before they fund it.
- **A guardian is trusted.** A guardian alone can start a recovery, toward any key. The owner's iPhone can cancel it during the delay: 72 hours, one minute on devnet. Past it, anyone can confirm, and the wallet moves for good. An owner away from their iPhone for three days can lose the wallet to a dishonest guardian.
- **A guardian finds its wallets on-chain.** The owner scans the guardian's device key once, and the guardian's device lists the wallet from then on, with nothing to keep. Anyone who saw that key can name it too: `forgetWallet(_:)` hides a wallet for good. A guardian that deletes its key can no longer start a recovery: name more than one.
- **One key per device, for both roles.** The device key signs for the device's own wallet and as guardian of others. Deleting it, or closing its wallet, ends both.
- **One wallet per device at a time.** A device that signs for a wallet cannot take on another: `recoverWallet` throws `walletExists`.

Passkey guardians, and recovery from Android or the web, come in v2.

## Requirements

- iOS 16 or macOS 13, swift-tools-version 6.4.
- A real device. The iOS Simulator has a Secure Enclave but refuses the access control the key needs: `createWallet()` throws `secureEnclaveUnavailable` there.
- `NSFaceIDUsageDescription` in the app's Info.plist.
- A Kora relayer that allows the program: see enclavekit-anchor. During development, Kora runs on the Mac and the iPhone reaches it over Wi-Fi: add `NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking` too.
- An RPC that answers `getProgramAccounts` with `memcmp` filters, for the wallets a device finds on-chain. Devnet's public RPC does.

```swift
.package(url: "https://github.com/ikaros-nb/enclavekit-swift.git", branch: "master")
```

One product, `EnclaveKit`, and no third-party dependency.

## Quick start

```swift
import EnclaveKit

let enclaveKit = EnclaveKitClient(config: EnclaveKitConfig(
    relayerURL: URL(string: "http://my-mac.local:8080")!
))

// The device key, made once: no network, no prompt.
let wallet = try enclaveKit.wallet() ?? enclaveKit.createWallet()

wallet.address                  // the vault: receives SOL right away
try await wallet.balance()      // Lamports, .formatted → "0.05 SOL"
try await wallet.status()       // .notOnChainYet, .active, .recovering, .keyReplaced

// Every action in two steps: the app shows the request in between.
let request = try await wallet.prepareTransfer(Lamports(sol: "0.01")!, to: recipient)
request.summary                 // "Send 0.01 SOL to <the address in full>"
request.maxFee                  // the most the vault pays the relayer back
let receipt = try await request.authorize()   // unlock, Kora, confirmed
receipt.explorerURL
```

- `prepare…` reads the wallet on-chain and refuses what the vault cannot pay, before any prompt.
- `ActionRequest` is `Identifiable`: put it in `.sheet(item:)`, show `summary` and `maxFee`, then call `authorize()`.
- `authorize()` asks the user, signs in the Secure Enclave, has Kora send the transaction and returns once it is confirmed. One authorization at a time in the whole app.
- The first action creates the wallet's account. Its rent is part of that action's fee: no setup transaction.

## Actions

| Call | Instruction | Effect |
|---|---|---|
| `wallet.prepareTransfer(_:to:)` | `transfer_sol` | The vault keeps the fee and its own rent: more is refused. |
| `wallet.prepareTransferAll(to:)` | `sweep_vault` | Everything, the fee aside, read on-chain as it executes. The wallet stays. |
| `wallet.prepareSetGuardians(_:)` | `set_guardians` | The whole list, up to `Wallet.maxGuardians`. Cancels a pending recovery. |
| `wallet.prepareCancelRecovery()` | `cancel_rotation` | From the owner's iPhone, until someone confirms the recovery. |
| `wallet.prepareMove(to:)` | `propose_rotation` | From the iPhone that signs: to another device's key, at once. Ends a recovery in progress. |
| `wallet.prepareClose(to:)` | `close_wallet` | Everything out, the account closed, then the device key deleted. |
| `guarded.prepareRecovery(to:)` | `propose_rotation` | From a guardian: proposes the new device's key, behind the delay. |
| `wallet.confirmRecoveryWhenOpen()` | `confirm_rotation` | From the new device: waits for the delay's end, then confirms. No signature, no prompt. `confirmRecovery()` confirms at once, or throws `recoveryNotOpen`. |

Each transaction carries the program's event for its action: see [Events](https://github.com/ikaros-nb/enclavekit-anchor#events) in enclavekit-anchor.

## Guardians and recovery

One QR code per step, always a device key: the device that scans it acts, and the other one finds the result on-chain from its own key.

```swift
// Guardian's device: show its key to the owner.
myWallet.deviceKey.description              // 66 hex digits

// Owner's iPhone: name the guardian.
_ = try await wallet.prepareSetGuardians([try DeviceKey(scanned)]).authorize()

// Guardian's device: the owner's wallet is listed, read on-chain.
let guarded = try await enclaveKit.guardedWallets()

// The owner lost their iPhone. The new one shows its key.
let newWallet = try enclaveKit.wallet() ?? enclaveKit.createWallet()
newWallet.deviceKey.description

// Guardian: propose that key.
_ = try await guarded[0].prepareRecovery(to: try DeviceKey(scanned)).authorize()

// New iPhone: find the wallet, take it on, confirm once the delay is over.
let found = try await enclaveKit.recoverableWallets()
let recovered = try await enclaveKit.recoverWallet(found[0].id)
try await recovered.status()                // .recovering(recovery), recovery.opensAt
_ = try await recovered.confirmRecoveryWhenOpen()
```

- `guardedWallets()` and `recoverableWallets()` read the chain with `getProgramAccounts`, three queries and two. They return what is there now: poll them while a screen waits for the other device. The demo polls every 3 seconds, well under the rate limit of devnet's public RPC.
- `recoverableWallets()` returns the wallets whose key is this device's, and those a guardian proposes to move to it. A lapsed proposal and the wallet `wallet()` returns are left out. Several can wait at once: show their `address` and let the user pick theirs.
- `recoverWallet` checks on-chain again, so nothing waits in local state. From then on, `wallet()` returns the recovered wallet.
- `confirmRecoveryWhenOpen()` sleeps until `opensAt`, then confirms, with nothing for the user to do. If a guardian proposes again, the delay starts over and the wait goes on. It throws `noRecovery` once the owner cancels, and `CancellationError` when its task is cancelled: start it again while the status is `.recovering`.
- During the delay, the owner's iPhone, if it still has its key, sees `.active(recovery:)` with the recovery, and can cancel.
- Each `GuardedWallet.status()` is `.guarding(recovery:)` or `.notGuarding`. A wallet that no longer names this device, or that was closed, leaves `guardedWallets()`. `forgetWallet(_:)` hides one for good, even if its owner names this device again later. On-chain, the wallet still names the device until its owner changes its guardians.

## Moving to another iPhone

While the old iPhone still has its key, it moves the wallet itself: no guardian, no delay. One QR code: the new iPhone's key.

```swift
// New iPhone: show its key to the old one.
let newWallet = try enclaveKit.wallet() ?? enclaveKit.createWallet()
newWallet.deviceKey.description

// Old iPhone: move the wallet.
_ = try await wallet.prepareMove(to: try DeviceKey(scanned)).authorize()
try await wallet.status()                   // .keyReplaced

// New iPhone: find the wallet and take it on. It signs from now on.
let found = try await enclaveKit.recoverableWallets()
let moved = try await enclaveKit.recoverWallet(found[0].id)
try await moved.status()                    // .active(recovery: nil)
```

- The move takes effect once the transaction confirms. The address, the funds and the guardians stay. A recovery in progress ends.
- `prepareMove(to:)` throws `notOnChainYet` before the wallet's first action: it has no key on-chain to move. It throws `keyInUse` for this device's own key or a guardian's: remove that guardian first.
- The new iPhone must not already sign for a wallet: `recoverWallet` throws `walletExists`. A wallet of its own that never acted is fine.
- A wallet comes back the same way. To the wallet `wallet()` returns, the device that made it for instance, it needs nothing more: `recoverableWallets()` leaves it out, and its status turns back to `.active`.
- `wallet()` returns the last wallet the device took on, even once that wallet moved away again: `.keyReplaced`. The device key still guards, and can take on another wallet.

## Starting over

- `prepareTransferAll(to:)` empties the vault. The wallet, its guardians and its address stay.
- `prepareClose(to:)` sends everything out and closes the wallet's account. The account's rent goes to the relayer, which advanced it. Once confirmed, the device key is deleted and `wallet()` returns `nil`. SOL sent to the old address afterwards is lost.
  - It throws `tokensLeft` while a token account of the vault holds a balance.
  - It throws `nothingToClose` for a wallet that never acted and holds no more than the fee. Call `deleteDeviceKey()` then.
- `deleteDeviceKey()` is local only. The wallet stays on-chain with what it holds, for a guardian to move: this is how the demo loses an iPhone.

## Errors

`EnclaveKitError` covers what an app can act on. Network failures come as they are, a `URLError` for instance. All of them read well through `localizedDescription`.

| Case | Meaning |
|---|---|
| `cancelled` | The user dismissed the prompt: nothing was signed, the request can be authorized again. |
| `insufficientFunds(available:)` | The vault cannot pay the amount, the fee and keep its rent. |
| `rejected(reason:)` | Kora refused the transaction, its simulation failed for instance: nothing was sent. |
| `failed(_:reason:)`, `notConfirmed(_:)` | The transaction reached the network: `receipt` gives its explorer page. |
| `keyReplaced` | The wallet moved to another key: this device no longer signs for it. |
| `notAGuardian` | The guarded wallet does not name this device. |
| `noRecovery` | The wallet neither moved nor is moving to this device's key: the device that signs for it, or a guardian, scans this key first. |
| `recoveryNotOpen(opensAt:)` | The recovery's delay is still running. |
| `notOnChainYet`, `keyInUse` | See [Moving to another iPhone](#moving-to-another-iphone). |
| `tooManyGuardians` | `prepareSetGuardians` got more than `Wallet.maxGuardians` keys. |
| `tokensLeft`, `nothingToClose` | See [Starting over](#starting-over). |
| `walletExists` | `createWallet()` found a device key, or `recoverWallet` found this device signing for another wallet. |
| `noWallet`, `secureEnclaveUnavailable` | No device key yet, or none possible here. |

## Layout

| Folder | Contents |
|---|---|
| `API/` | The only public code. |
| `Program/` | Action encoding, preimage, the program's instructions, the wallet's account. |
| `Solana/` | Base58, PDAs, low-S, the `secp256r1` instruction, the legacy message. |
| `Network/` | JSON-RPC, Solana RPC, Kora. |
| `Device/` | Secure Enclave key, Keychain. |

The tests mirror these folders, plus `Support/` and `Vectors/`.

## Tests

```bash
swift test
```

Runs on a Mac against stubs, the Mac's Secure Enclave and its Keychain.

`Tests/EnclaveKitTests/Vectors/` is a copy of enclavekit-anchor's `vectors/`: the encoding, the PDAs, the `secp256r1` instruction and the transaction are compared byte for byte. After `cargo run -p gen-vectors` over there:

```bash
scripts/sync-vectors.sh       # copies them, prints the commit message
```

Live tests run against a running Kora and devnet, off unless asked for:

```bash
KORA_URL=http://127.0.0.1:8080 swift test --filter LiveTests                      # read-only
KORA_URL=http://127.0.0.1:8080 LIVE_SEND=1 swift test --filter LiveSendTests       # one transfer_sol
KORA_URL=http://127.0.0.1:8080 LIVE_SEND=1 swift test --filter LiveRecoveryTests   # a whole recovery, about 90 s
```

The last two spend devnet SOL from test vaults. When one runs dry, the failure prints the `solana transfer` that funds it. `KORA_API_KEY` is sent when set.

The shared Xcode scheme `EnclaveKit` sets `KORA_URL` and `LIVE_SEND`: ⌘U in Xcode sends real transactions.
