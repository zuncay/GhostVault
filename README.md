# GhostVault

GhostVault is an autonomous dead-man vault running on Ritual Testnet. Owners lock GHOST tokens and commit an encrypted payload hash, then maintain an on-chain heartbeat. Ritual Scheduler coordinates TEE HTTP and LLM checks; the contract starts a recoverable grace period after a missed heartbeat and only code can release funds after that period expires.

## Ritual Testnet deployment

| Contract | Address |
| --- | --- |
| GhostToken | `0x561b92482FA47DbB94361C7D91060d7B51A3E8Cd` |
| VaultReceipt | `0xAEE203f72E4d038FF895948cFEC7b72e05cca6b4` |
| GhostVaultCore | `0x790732793fc7ac36a55FfE5311cc79576602118b` |
| GhostVaultAgent | `0xA3aF41dDb387E60C32c2D777B3a606632EbFdd08` |

- Chain ID: `1979`
- RPC: `https://rpc.ritualfoundation.org`
- Agent mode: real Ritual precompiles (`bypassPrecompiles = false`)
- Agent RitualWallet deposit: `0.06 RITUAL`

## Safety model

- LLM output never transfers funds.
- Only an `inactive` outcome with confidence of at least 75 can start grace.
- `alive`, low-confidence, unknown, HTTP errors, and LLM errors fail closed.
- A missed on-chain heartbeat is required before grace can start.
- The owner or guardian can restore the vault during grace.
- Finalization is permissionless only after the configured grace deadline.
- The encrypted payload remains off-chain; only its hash and URI are committed.
- Bypass mode is an owner-controlled resilience switch and is disabled on deployment.

## Local development

```bash
npm install
npm run dev
```

Open `http://localhost:4174`. The dashboard reads public chain data before a wallet is connected.

## Verification

```bash
D:/Ritual/.tools/foundry/forge.exe test -vv
npm run build
```

The suite covers real Scheduler-shaped HTTP → LLM callbacks, bypass recovery, guardian heartbeat reactivation, escrow cancellation, finalization timing, and RitualWallet funding.
