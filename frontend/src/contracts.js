export const addresses = {
  core: import.meta.env.VITE_CORE_ADDRESS || "0x006BdFeE1C2BA7E985Af12C62Cc9d08d94126eCf",
  agent: import.meta.env.VITE_AGENT_ADDRESS || "0x1E7C5eA5182A750CF35a283dCF51f506e593bFC1",
  token: import.meta.env.VITE_TOKEN_ADDRESS || "0x0A0bfC9c4B040eAdf1Eb259fAc4c067865789eae",
  receipt: import.meta.env.VITE_RECEIPT_ADDRESS || "0x9403F7A235EaDa786958D900ccC047aB4Ea5b4bE"
};

const vaultComponents = [
  { name: "owner", type: "address" }, { name: "beneficiary", type: "address" },
  { name: "guardian", type: "address" }, { name: "amount", type: "uint96" },
  { name: "lastHeartbeat", type: "uint48" }, { name: "heartbeatInterval", type: "uint48" },
  { name: "gracePeriod", type: "uint48" }, { name: "releaseAt", type: "uint48" },
  { name: "state", type: "uint8" }, { name: "payloadHash", type: "bytes32" },
  { name: "evidenceHash", type: "bytes32" }, { name: "resultHash", type: "bytes32" },
  { name: "scheduleId", type: "uint256" }, { name: "name", type: "string" },
  { name: "payloadURI", type: "string" }, { name: "statusURL", type: "string" },
  { name: "policy", type: "string" }
];

export const coreAbi = [
  { type: "function", name: "nextVaultId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "getVault", stateMutability: "view", inputs: [{ name: "vaultId", type: "uint256" }], outputs: [{ name: "vault", type: "tuple", components: vaultComponents }] },
  { type: "function", name: "createVault", stateMutability: "nonpayable", inputs: [
    { name: "name", type: "string" }, { name: "beneficiary", type: "address" }, { name: "guardian", type: "address" },
    { name: "amount", type: "uint96" }, { name: "heartbeatInterval", type: "uint48" }, { name: "gracePeriod", type: "uint48" },
    { name: "monitorFrequencyBlocks", type: "uint32" }, { name: "payloadHash", type: "bytes32" },
    { name: "payloadURI", type: "string" }, { name: "statusURL", type: "string" }, { name: "policy", type: "string" }
  ], outputs: [{ name: "vaultId", type: "uint256" }] },
  { type: "function", name: "heartbeat", stateMutability: "nonpayable", inputs: [{ name: "vaultId", type: "uint256" }], outputs: [] },
  { type: "function", name: "pokeVault", stateMutability: "nonpayable", inputs: [{ name: "vaultId", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "finalizeRelease", stateMutability: "nonpayable", inputs: [{ name: "vaultId", type: "uint256" }], outputs: [] },
  { type: "function", name: "cancelVault", stateMutability: "nonpayable", inputs: [{ name: "vaultId", type: "uint256" }], outputs: [] }
];

export const tokenAbi = [
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claimFaucet", stateMutability: "nonpayable", inputs: [], outputs: [] }
];

export const agentAbi = [
  { type: "function", name: "feeBalance", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "bypassPrecompiles", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] }
];
