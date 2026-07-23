// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { VaultReceipt } from "./VaultReceipt.sol";
import { IGhostVaultAgent } from "./interfaces/IGhostVault.sol";

contract GhostVaultCore is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum VaultState { None, Armed, Grace, Released, Cancelled }

    struct Vault {
        address owner;
        address beneficiary;
        address guardian;
        uint96 amount;
        uint48 lastHeartbeat;
        uint48 heartbeatInterval;
        uint48 gracePeriod;
        uint48 releaseAt;
        VaultState state;
        bytes32 payloadHash;
        bytes32 evidenceHash;
        bytes32 resultHash;
        uint256 scheduleId;
        string name;
        string payloadURI;
        string statusURL;
        string policy;
    }

    uint48 public constant MIN_HEARTBEAT_INTERVAL = 5 minutes;
    uint48 public constant MIN_GRACE_PERIOD = 5 minutes;

    IERC20 public immutable assetToken;
    VaultReceipt public immutable receipt;
    IGhostVaultAgent public agent;
    uint256 public nextVaultId = 1;
    mapping(uint256 vaultId => Vault vault) private _vaults;

    event AgentConfigured(address indexed agent);
    event VaultCreated(uint256 indexed vaultId, address indexed owner, address indexed beneficiary, uint256 amount);
    event Heartbeat(uint256 indexed vaultId, address indexed caller, uint256 nextDeadline);
    event MonitoringScheduled(uint256 indexed vaultId, uint256 indexed scheduleId);
    event GraceStarted(uint256 indexed vaultId, uint256 releaseAt, bytes32 evidenceHash, bytes32 resultHash);
    event VaultReleased(uint256 indexed vaultId, address indexed beneficiary, uint256 amount);
    event VaultCancelled(uint256 indexed vaultId, uint256 amountReturned);

    modifier onlyAgent() {
        require(msg.sender == address(agent), "only agent");
        _;
    }

    constructor(address initialOwner, IERC20 token, VaultReceipt vaultReceipt) Ownable(initialOwner) {
        require(address(token) != address(0) && address(vaultReceipt) != address(0), "zero address");
        assetToken = token;
        receipt = vaultReceipt;
    }

    function setAgent(IGhostVaultAgent newAgent) external onlyOwner {
        require(address(newAgent) != address(0), "zero agent");
        require(address(agent) == address(0), "agent already set");
        agent = newAgent;
        emit AgentConfigured(address(newAgent));
    }

    function createVault(
        string calldata name,
        address beneficiary,
        address guardian,
        uint96 amount,
        uint48 heartbeatInterval,
        uint48 gracePeriod,
        uint32 monitorFrequencyBlocks,
        bytes32 payloadHash,
        string calldata payloadURI,
        string calldata statusURL,
        string calldata policy
    ) external nonReentrant returns (uint256 vaultId) {
        require(address(agent) != address(0), "agent not configured");
        require(bytes(name).length != 0 && bytes(name).length <= 72, "invalid name");
        require(beneficiary != address(0) && beneficiary != msg.sender, "invalid beneficiary");
        require(guardian != msg.sender, "owner cannot guard");
        require(amount != 0, "zero amount");
        require(heartbeatInterval >= MIN_HEARTBEAT_INTERVAL, "heartbeat too short");
        require(gracePeriod >= MIN_GRACE_PERIOD, "grace too short");
        require(monitorFrequencyBlocks >= 10 && monitorFrequencyBlocks <= 100_000, "invalid frequency");
        require(payloadHash != bytes32(0), "zero payload hash");
        require(bytes(payloadURI).length <= 512 && bytes(statusURL).length <= 512, "URI too long");
        require(bytes(policy).length != 0 && bytes(policy).length <= 1_500, "invalid policy");

        vaultId = nextVaultId++;
        Vault storage vault = _vaults[vaultId];
        vault.owner = msg.sender;
        vault.beneficiary = beneficiary;
        vault.guardian = guardian;
        vault.amount = amount;
        vault.lastHeartbeat = uint48(block.timestamp);
        vault.heartbeatInterval = heartbeatInterval;
        vault.gracePeriod = gracePeriod;
        vault.state = VaultState.Armed;
        vault.payloadHash = payloadHash;
        vault.name = name;
        vault.payloadURI = payloadURI;
        vault.statusURL = statusURL;
        vault.policy = policy;

        assetToken.safeTransferFrom(msg.sender, address(this), amount);
        emit VaultCreated(vaultId, msg.sender, beneficiary, amount);

        vault.scheduleId = agent.scheduleMonitoring(vaultId, monitorFrequencyBlocks);
        emit MonitoringScheduled(vaultId, vault.scheduleId);
    }

    function heartbeat(uint256 vaultId) external {
        Vault storage vault = _getVault(vaultId);
        require(msg.sender == vault.owner || msg.sender == vault.guardian, "not owner or guardian");
        require(vault.state == VaultState.Armed || vault.state == VaultState.Grace, "vault inactive");
        require(vault.state != VaultState.Grace || block.timestamp < vault.releaseAt, "grace ended");
        vault.lastHeartbeat = uint48(block.timestamp);
        vault.releaseAt = 0;
        vault.state = VaultState.Armed;
        emit Heartbeat(vaultId, msg.sender, block.timestamp + vault.heartbeatInterval);
    }

    function pokeVault(uint256 vaultId) external returns (uint256 scheduleId) {
        Vault storage vault = _getVault(vaultId);
        require(vault.state == VaultState.Armed, "vault not armed");
        scheduleId = agent.requestCheck(vaultId);
    }

    function onMonitoringResult(uint256 vaultId, bytes32 evidenceHash, bytes32 resultHash)
        external
        onlyAgent
    {
        Vault storage vault = _getVault(vaultId);
        require(vault.state == VaultState.Armed, "vault not armed");
        require(block.timestamp > uint256(vault.lastHeartbeat) + vault.heartbeatInterval, "heartbeat active");
        vault.evidenceHash = evidenceHash;
        vault.resultHash = resultHash;
        vault.releaseAt = uint48(block.timestamp + vault.gracePeriod);
        vault.state = VaultState.Grace;
        emit GraceStarted(vaultId, vault.releaseAt, evidenceHash, resultHash);
    }

    function finalizeRelease(uint256 vaultId) external nonReentrant {
        Vault storage vault = _getVault(vaultId);
        require(vault.state == VaultState.Grace, "vault not in grace");
        require(block.timestamp >= vault.releaseAt, "grace active");
        uint256 amount = vault.amount;
        vault.amount = 0;
        vault.state = VaultState.Released;
        assetToken.safeTransfer(vault.beneficiary, amount);
        receipt.mint(vault.beneficiary, vaultId, _receiptURI(vaultId, vault));
        _tryCancel(vault.scheduleId);
        emit VaultReleased(vaultId, vault.beneficiary, amount);
    }

    function cancelVault(uint256 vaultId) external nonReentrant {
        Vault storage vault = _getVault(vaultId);
        require(msg.sender == vault.owner, "only owner");
        require(vault.state == VaultState.Armed || vault.state == VaultState.Grace, "vault inactive");
        uint256 amount = vault.amount;
        vault.amount = 0;
        vault.state = VaultState.Cancelled;
        assetToken.safeTransfer(vault.owner, amount);
        _tryCancel(vault.scheduleId);
        emit VaultCancelled(vaultId, amount);
    }

    function getVault(uint256 vaultId) external view returns (Vault memory) {
        return _getVault(vaultId);
    }

    function monitoringContext(uint256 vaultId)
        external
        view
        returns (uint8 state, uint256 heartbeatDeadline, string memory statusUrl, string memory policy)
    {
        Vault storage vault = _getVault(vaultId);
        return (
            uint8(vault.state),
            uint256(vault.lastHeartbeat) + vault.heartbeatInterval,
            vault.statusURL,
            vault.policy
        );
    }

    function _tryCancel(uint256 scheduleId) internal {
        if (scheduleId != 0) {
            try agent.cancelMonitoring(scheduleId) { } catch { }
        }
    }

    function _getVault(uint256 vaultId) internal view returns (Vault storage vault) {
        vault = _vaults[vaultId];
        require(vault.state != VaultState.None, "vault not found");
    }

    function _receiptURI(uint256 vaultId, Vault storage vault) internal view returns (string memory) {
        return string.concat(
            "data:application/json,{\"name\":\"GhostVault Release #",
            _toString(vaultId),
            "\",\"description\":\"Autonomous Ritual TEE vault release\",\"attributes\":[{\"trait_type\":\"Payload Hash\",\"value\":\"",
            _toHex(vault.payloadHash),
            "\"},{\"trait_type\":\"Result Hash\",\"value\":\"",
            _toHex(vault.resultHash),
            "\"}]}"
        );
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) { digits--; buffer[digits] = bytes1(uint8(48 + value % 10)); value /= 10; }
        return string(buffer);
    }

    function _toHex(bytes32 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(66);
        out[0] = "0"; out[1] = "x";
        for (uint256 i; i < 32; ++i) {
            out[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
            out[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return string(out);
    }
}
