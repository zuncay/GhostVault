# GhostVault

GhostVault is an autonomous dead-man vault running on Ritual Testnet. Owners lock GHOST tokens and commit an encrypted payload hash, then maintain an on-chain heartbeat. Ritual Scheduler coordinates TEE HTTP and LLM checks; the contract starts a recoverable grace period after a missed heartbeat and only code can release funds after that period expires.

## Ritual Testnet deployment

| Contract | Address |
| --- | --- |
| GhostToken | `0x0A0bfC9c4B040eAdf1Eb259fAc4c067865789eae` |
| VaultReceipt | `0x9403F7A235EaDa786958D900ccC047aB4Ea5b4bE` |
| GhostVaultCore | `0x006BdFeE1C2BA7E985Af12C62Cc9d08d94126eCf` |
| GhostVaultAgent | `0x1E7C5eA5182A750CF35a283dCF51f506e593bFC1` |

- Chain ID: `1979`
- RPC: `https://rpc.ritualfoundation.org`
- Agent mode: real Ritual precompiles (`bypassPrecompiles = false`)
- Agent RitualWallet deposit: `0.1 RITUAL`

## Safety model

- LLM output never transfers funds.
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
