import {
  createPublicClient, createWalletClient, custom, defineChain, formatEther, formatUnits,
  http, keccak256, parseUnits, toBytes
} from "viem";
import { addresses, agentAbi, coreAbi, tokenAbi } from "./contracts.js";

const ritual = defineChain({
  id: 1979,
  name: "Ritual Testnet",
  nativeCurrency: { name: "RITUAL", symbol: "RITUAL", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.ritualfoundation.org"] } },
  blockExplorers: { default: { name: "Ritual Explorer", url: "https://explorer.ritualfoundation.org" } }
});
const publicClient = createPublicClient({ chain: ritual, transport: http("https://rpc.ritualfoundation.org", { timeout: 12_000 }) });
const configured = Object.values(addresses).every((value) => /^0x[0-9a-fA-F]{40}$/.test(value || ""));
const stateNames = ["None", "Armed", "Grace", "Released", "Cancelled"];
const zeroAddress = "0x0000000000000000000000000000000000000000";
let walletClient;
let account;
let loading = false;
const $ = (selector) => document.querySelector(selector);
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function reliableRead(request, attempts = 3) {
  let lastError;
  for (let i = 0; i < attempts; i += 1) {
    try { return await publicClient.readContract(request); }
    catch (error) { lastError = error; if (i < attempts - 1) await pause(400 * (i + 1)); }
  }
  throw lastError;
}

async function ensureNetwork() {
  const chainId = `0x${ritual.id.toString(16)}`;
  try { await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId }] }); }
  catch (error) {
    if (error.code !== 4902) throw error;
    await window.ethereum.request({ method: "wallet_addEthereumChain", params: [{ chainId, chainName: ritual.name, nativeCurrency: ritual.nativeCurrency, rpcUrls: ritual.rpcUrls.default.http, blockExplorerUrls: [ritual.blockExplorers.default.url] }] });
  }
}

async function connect() {
  if (!window.ethereum) throw new Error("MetaMask is not installed");
  await ensureNetwork();
  const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
  account = accounts[0];
  walletClient = createWalletClient({ account, chain: ritual, transport: custom(window.ethereum) });
  renderAccount();
  await loadVaults();
}

function renderAccount() {
  $("#account").textContent = account ? `${account.slice(0, 6)}…${account.slice(-4)}` : "Read only";
  $("#connect").textContent = account ? `${account.slice(0, 6)}…${account.slice(-4)}` : "Connect wallet";
  if (!account) $("#balance").textContent = "No signature required";
}

async function loadNetwork() {
  try {
    const block = await publicClient.getBlockNumber();
    $("#block").textContent = Number(block).toLocaleString();
    $("#rpc-status").textContent = "Ritual RPC online";
    $("#rpc-dot").classList.add("online");
  } catch (error) {
    $("#rpc-status").textContent = "RPC unavailable";
  }
}

async function loadVaults() {
  if (loading) return;
  loading = true;
  try {
    if (!configured) {
      $("#warning").classList.remove("hidden");
      $("#warning").textContent = "Contracts are not configured yet. Deploy GhostVault and set the VITE_* addresses.";
      $("#vault-list").innerHTML = '<div class="empty">Waiting for deployed contract addresses.</div>';
      return;
    }
    const [nextId, fees] = await Promise.all([
      reliableRead({ address: addresses.core, abi: coreAbi, functionName: "nextVaultId" }),
      reliableRead({ address: addresses.agent, abi: agentAbi, functionName: "feeBalance" })
    ]);
    const count = Number(nextId - 1n);
    $("#total").textContent = count.toLocaleString();
    $("#fees").textContent = `${Number(formatEther(fees)).toFixed(4)} RITUAL`;
    if (account) {
      const balance = await reliableRead({ address: addresses.token, abi: tokenAbi, functionName: "balanceOf", args: [account] });
      $("#balance").textContent = `${Number(formatUnits(balance, 18)).toLocaleString()} GHOST`;
    }
    if (!count) { $("#vault-list").innerHTML = '<div class="empty">No vaults have been armed yet.</div>'; return; }
    const ids = Array.from({ length: Math.min(count, 30) }, (_, i) => BigInt(count - i));
    const vaults = [];
    for (const id of ids) vaults.push(await reliableRead({ address: addresses.core, abi: coreAbi, functionName: "getVault", args: [id] }));
    $("#vault-list").innerHTML = vaults.map((vault, i) => vaultCard(ids[i], vault)).join("");
  } catch (error) {
    if (!$("#vault-list .vault-card")) $("#vault-list").innerHTML = '<div class="empty">RPC is retrying the vault registry. Use Refresh if this persists.</div>';
  } finally { loading = false; }
}

function vaultCard(id, vault) {
  const state = stateNames[Number(vault.state)];
  const deadline = new Date((Number(vault.lastHeartbeat) + Number(vault.heartbeatInterval)) * 1000).toLocaleString();
  const release = Number(vault.releaseAt) ? new Date(Number(vault.releaseAt) * 1000).toLocaleString() : "Not triggered";
  return `<article class="vault-card"><div><div class="vault-top"><span class="vault-id">VAULT #${id}</span><span class="state ${state.toLowerCase()}">${state.toUpperCase()}</span></div><h3>${escapeHtml(vault.name)}</h3><p>Beneficiary ${short(vault.beneficiary)} · Payload ${short(vault.payloadHash)}</p><div class="vault-meta"><span>Heartbeat deadline ${deadline}</span><span>Release ${release}</span><span>Schedule #${vault.scheduleId}</span></div></div><div class="vault-side"><strong>${formatUnits(vault.amount, 18)}</strong><small>GHOST locked</small><div class="vault-actions">${vaultActions(id, vault)}</div></div></article>`;
}

function vaultActions(id, vault) {
  if (!account) return "";
  const me = account.toLowerCase();
  const participant = [vault.owner.toLowerCase(), vault.guardian.toLowerCase()].includes(me);
  const actions = [];
  if (participant && [1, 2].includes(Number(vault.state))) actions.push(`<button class="vault-action" data-action="heartbeat" data-id="${id}">Heartbeat</button>`);
  if (Number(vault.state) === 1) actions.push(`<button class="vault-action" data-action="poke" data-id="${id}">Check now</button>`);
  if (Number(vault.state) === 2 && Date.now() / 1000 >= Number(vault.releaseAt)) actions.push(`<button class="vault-action" data-action="finalize" data-id="${id}">Finalize</button>`);
  if (vault.owner.toLowerCase() === me && [1, 2].includes(Number(vault.state))) actions.push(`<button class="vault-action" data-action="cancel" data-id="${id}">Cancel</button>`);
  return actions.join("");
}

async function write(address, abi, functionName, args, label) {
  if (!walletClient || !account) await connect();
  const { request } = await publicClient.simulateContract({ account, address, abi, functionName, args });
  const hash = await walletClient.writeContract(request);
  log(label, `<a target="_blank" rel="noreferrer" href="${ritual.blockExplorers.default.url}/tx/${hash}">${hash}</a>`);
  await publicClient.waitForTransactionReceipt({ hash, confirmations: 1, timeout: 180_000 });
  await loadVaults();
  return hash;
}

async function createVault(form) {
  const data = new FormData(form);
  const amount = parseUnits(data.get("amount"), 18);
  const heartbeat = BigInt(Math.max(300, Math.round(Number(data.get("heartbeat")) * 3600)));
  const grace = BigInt(Math.max(300, Math.round(Number(data.get("grace")) * 3600)));
  const guardian = data.get("guardian") || zeroAddress;
  const payloadHash = keccak256(toBytes(data.get("payload")));
  await write(addresses.token, tokenAbi, "approve", [addresses.core, amount], "Approving GHOST escrow");
  await write(addresses.core, coreAbi, "createVault", [data.get("name"), data.get("beneficiary"), guardian, amount, heartbeat, grace, 100, payloadHash, data.get("payloadURI"), data.get("statusURL"), data.get("policy")], "Arming autonomous vault");
}

function log(title, detail) {
  const item = document.createElement("div"); item.className = "activity-item";
  item.innerHTML = `<b>${escapeHtml(title)}</b><span>${detail}</span>`;
  $("#activity").prepend(item);
}
const short = (value) => `${String(value).slice(0, 8)}…${String(value).slice(-6)}`;
const escapeHtml = (value) => String(value).replace(/[&<>\"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const randomAddress = () => { const bytes = crypto.getRandomValues(new Uint8Array(20)); return `0x${[...bytes].map((b) => b.toString(16).padStart(2, "0")).join("")}`; };

$("#connect").addEventListener("click", () => connect().catch((e) => log("Wallet connection failed", escapeHtml(e.shortMessage || e.message))));
$("#refresh").addEventListener("click", loadVaults);
$("#faucet").addEventListener("click", () => write(addresses.token, tokenAbi, "claimFaucet", [], "Claiming testnet GHOST").catch((e) => log("Faucet failed", escapeHtml(e.shortMessage || e.message))));
$("#open-create").addEventListener("click", async () => { try { if (!account) await connect(); $("#create-dialog").showModal(); } catch (e) { log("Wallet connection failed", escapeHtml(e.shortMessage || e.message)); } });
$(".close").addEventListener("click", () => $("#create-dialog").close());
$("#fill-showcase").addEventListener("click", () => {
  const form = $("#create-form");
  form.name.value = `Recovery vault ${crypto.getRandomValues(new Uint32Array(1))[0].toString(16).toUpperCase()}`;
  form.beneficiary.value = randomAddress(); form.guardian.value = randomAddress(); form.amount.value = "25";
  form.heartbeat.value = "0.1"; form.grace.value = "0.1";
  form.payloadURI.value = "https://raw.githubusercontent.com/ritual-foundation/ritual-dapp-skills/main/LICENSE";
  form.payload.value = `encrypted-recovery-package-${crypto.randomUUID()}`; form.statusURL.value = "";
  form.policy.value = "Classify the public liveness evidence. The contract must still enforce the missed heartbeat and grace period.";
});
$("#create-form").addEventListener("submit", async (event) => { event.preventDefault(); try { await createVault(event.currentTarget); $("#create-dialog").close(); event.currentTarget.reset(); } catch (e) { log("Create vault failed", escapeHtml(e.shortMessage || e.message)); } });
$("#vault-list").addEventListener("click", async (event) => {
  const button = event.target.closest("[data-action]"); if (!button) return;
  const map = { heartbeat: ["heartbeat", "Sending heartbeat"], poke: ["pokeVault", "Requesting Ritual check"], finalize: ["finalizeRelease", "Finalizing vault release"], cancel: ["cancelVault", "Cancelling vault"] };
  try { await write(addresses.core, coreAbi, map[button.dataset.action][0], [BigInt(button.dataset.id)], map[button.dataset.action][1]); }
  catch (e) { log("Transaction failed", escapeHtml(e.shortMessage || e.message)); }
});
if (window.ethereum) {
  window.ethereum.on("accountsChanged", (accounts) => { account = accounts[0]; walletClient = account ? createWalletClient({ account, chain: ritual, transport: custom(window.ethereum) }) : undefined; renderAccount(); loadVaults(); });
  window.ethereum.on("chainChanged", () => location.reload());
}
renderAccount(); loadNetwork(); loadVaults(); setInterval(loadNetwork, 10_000); setInterval(loadVaults, 30_000);
