// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IGhostVaultCore } from "./interfaces/IGhostVault.sol";
import { IRitualWallet, IScheduler, ITEEServiceRegistry } from "./interfaces/IRitualSystem.sol";
import { PrecompileConsumer } from "./utils/PrecompileConsumer.sol";

contract GhostVaultAgent is Ownable, PrecompileConsumer {
    enum CheckStage { None, HttpScheduled, LlmScheduled }

    struct StorageRef { string platform; string path; string keyRef; }
    struct Check {
        CheckStage stage;
        uint256 httpScheduleId;
        uint256 llmScheduleId;
        bytes32 evidenceHash;
        bytes evidence;
        string policy;
    }

    address public constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address public constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address public constant TEE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    uint8 private constant CAPABILITY_HTTP = 0;
    uint8 private constant CAPABILITY_LLM = 1;
    uint32 private constant CHECK_GAS = 3_000_000;
    uint32 private constant SCHEDULER_TTL = 2_000_000;
    uint256 private constant PRIORITY_FEE = 1 gwei;

    IGhostVaultCore public immutable core;
    IScheduler public immutable scheduler = IScheduler(SCHEDULER);
    ITEEServiceRegistry public immutable registry = ITEEServiceRegistry(TEE_REGISTRY);
    bool public bypassPrecompiles;
    bytes32 public bypassEvidenceHash = keccak256("ghostvault-bypass-evidence");
    bytes32 public bypassResultHash = keccak256("ghostvault-bypass-result");
    mapping(uint256 vaultId => Check check) private _checks;

    event MonitoringScheduled(uint256 indexed vaultId, uint256 indexed scheduleId, bool recurring);
    event CheckStageChanged(uint256 indexed vaultId, CheckStage stage, uint256 scheduleId);
    event MonitoringCompleted(uint256 indexed vaultId, bytes32 evidenceHash, bytes32 resultHash);
    event BypassModeChanged(bool enabled, bytes32 evidenceHash, bytes32 resultHash);
    event FeesFunded(address indexed funder, uint256 amount, uint256 lockDuration);

    modifier onlyCore() { require(msg.sender == address(core), "only core"); _; }
    modifier onlyScheduler() { require(msg.sender == SCHEDULER, "only scheduler"); _; }

    constructor(address initialOwner, IGhostVaultCore coreAddress) Ownable(initialOwner) {
        require(address(coreAddress) != address(0), "zero core");
        core = coreAddress;
    }

    function setBypassPrecompiles(bool enabled, bytes32 evidenceHash, bytes32 resultHash)
        external
        onlyOwner
    {
        bypassPrecompiles = enabled;
        if (evidenceHash != bytes32(0)) bypassEvidenceHash = evidenceHash;
        if (resultHash != bytes32(0)) bypassResultHash = resultHash;
        emit BypassModeChanged(enabled, bypassEvidenceHash, bypassResultHash);
    }

    function fundFees(uint256 lockDuration) external payable {
        require(msg.value != 0, "zero value");
        require(lockDuration >= 1_000, "lock too short");
        IRitualWallet(RITUAL_WALLET).deposit{ value: msg.value }(lockDuration);
        emit FeesFunded(msg.sender, msg.value, lockDuration);
    }

    function feeBalance() external view returns (uint256) {
        return IRitualWallet(RITUAL_WALLET).balanceOf(address(this));
    }

    function scheduleMonitoring(uint256 vaultId, uint32 frequencyBlocks)
        external
        onlyCore
        returns (uint256 scheduleId)
    {
        scheduleId = _schedule(
            abi.encodeWithSelector(this.executeMonitor.selector, uint256(0), vaultId),
            1_000,
            frequencyBlocks
        );
        emit MonitoringScheduled(vaultId, scheduleId, true);
    }

    function requestCheck(uint256 vaultId) external onlyCore returns (uint256 scheduleId) {
        if (bypassPrecompiles) {
            _complete(vaultId, bypassEvidenceHash, bypassResultHash);
            return 0;
        }
        scheduleId = _schedule(
            abi.encodeWithSelector(this.executeMonitor.selector, uint256(0), vaultId), 1, 1
        );
        emit MonitoringScheduled(vaultId, scheduleId, false);
    }

    function cancelMonitoring(uint256 scheduleId) external onlyCore {
        scheduler.cancel(scheduleId);
    }

    function executeMonitor(uint256 executionIndex, uint256 vaultId) external onlyScheduler {
        (uint8 state, uint256 deadline, string memory statusUrl, string memory policy) =
            core.monitoringContext(vaultId);
        if (state != 1 || block.timestamp <= deadline || _checks[vaultId].stage != CheckStage.None) return;

        if (bypassPrecompiles) {
            _complete(vaultId, bypassEvidenceHash, bypassResultHash);
            return;
        }
        if (bytes(statusUrl).length == 0) {
            bytes32 deterministic = keccak256(abi.encode(vaultId, deadline, "onchain-timeout"));
            _complete(vaultId, bytes32(0), deterministic);
            return;
        }

        Check storage check = _checks[vaultId];
        check.policy = policy;
        check.stage = CheckStage.HttpScheduled;
        check.httpScheduleId = _schedule(
            abi.encodeWithSelector(this.executeHttpStep.selector, uint256(0), vaultId, statusUrl), 1, 1
        );
        emit CheckStageChanged(vaultId, CheckStage.HttpScheduled, check.httpScheduleId);
        executionIndex;
    }

    function executeHttpStep(uint256 executionIndex, uint256 vaultId, string calldata statusUrl)
        external
        onlyScheduler
    {
        Check storage check = _checks[vaultId];
        require(check.stage == CheckStage.HttpScheduled, "wrong stage");
        address executor = _pickExecutor(CAPABILITY_HTTP, vaultId, executionIndex);
        bytes memory input = abi.encode(
            executor,
            new bytes[](0),
            uint256(300),
            new bytes[](0),
            bytes(""),
            statusUrl,
            uint8(1),
            new string[](0),
            new string[](0),
            bytes(""),
            uint256(0),
            uint8(0),
            false
        );
        bytes memory output = _executePrecompile(HTTP_CALL_PRECOMPILE, input);
        (uint16 statusCode,,, bytes memory body, string memory errorMessage) =
            abi.decode(output, (uint16, string[], string[], bytes, string));
        if (bytes(errorMessage).length != 0 || statusCode < 200 || statusCode >= 300 || body.length == 0 || body.length > 5_000) {
            _complete(vaultId, bytes32(0), keccak256(abi.encode(statusCode, errorMessage, "http-failed")));
            return;
        }
        check.evidence = body;
        check.evidenceHash = keccak256(body);
        check.stage = CheckStage.LlmScheduled;
        check.llmScheduleId = _schedule(
            abi.encodeWithSelector(this.executeLlmStep.selector, uint256(0), vaultId), 1, 1
        );
        emit CheckStageChanged(vaultId, CheckStage.LlmScheduled, check.llmScheduleId);
    }

    function executeLlmStep(uint256 executionIndex, uint256 vaultId) external onlyScheduler {
        Check storage check = _checks[vaultId];
        require(check.stage == CheckStage.LlmScheduled, "wrong stage");
        address executor = _pickExecutor(CAPABILITY_LLM, vaultId, executionIndex);
        bytes memory responseFormat = abi.encode(
            "json_schema",
            abi.encode(
                "liveness_signal",
                "Classify the external liveness evidence.",
                '{"type":"object","properties":{"signal":{"type":"string","enum":["alive","unknown","inactive"]},"confidence":{"type":"integer","minimum":0,"maximum":100}},"required":["signal","confidence"],"additionalProperties":false}',
                "true"
            )
        );
        bytes memory input = abi.encode(
            executor,
            new bytes[](0),
            uint256(500),
            new bytes[](0),
            bytes(""),
            _messages(check.policy, check.evidence),
            "zai-org/GLM-4.7-FP8",
            int256(0), "", false, int256(2048), "", "", uint256(1), true, int256(0),
            "medium", responseFormat, int256(-1), "auto", "", false, int256(100), bytes(""),
            bytes(""), int256(-1), int256(1000), "ghost-vault", false,
            StorageRef({ platform: "", path: "", keyRef: "" })
        );
        bytes memory output = _executePrecompile(LLM_INFERENCE_PRECOMPILE, input);
        (bool hasError, bytes memory completionData,, string memory errorMessage,) =
            abi.decode(output, (bool, bytes, bytes, string, StorageRef));
        if (hasError || completionData.length == 0) {
            _complete(vaultId, check.evidenceHash, keccak256(abi.encode(errorMessage, "llm-failed")));
            return;
        }
        bytes memory content = _completionContent(completionData);
        (bool parsed, bytes memory confidenceRaw) =
            JQ_PRECOMPILE.staticcall(abi.encode(".confidence", string(content), uint8(1)));
        if (!parsed || confidenceRaw.length < 32 || abi.decode(confidenceRaw, (uint256)) > 100) {
            _complete(vaultId, check.evidenceHash, keccak256(abi.encode(completionData, "invalid-json")));
            return;
        }
        _complete(vaultId, check.evidenceHash, keccak256(completionData));
    }

    function getCheck(uint256 vaultId) external view returns (Check memory) { return _checks[vaultId]; }

    function _complete(uint256 vaultId, bytes32 evidenceHash, bytes32 resultHash) internal {
        delete _checks[vaultId];
        emit MonitoringCompleted(vaultId, evidenceHash, resultHash);
        core.onMonitoringResult(vaultId, evidenceHash, resultHash);
    }

    function _schedule(bytes memory data, uint32 numCalls, uint32 frequency) internal returns (uint256) {
        require(block.number < type(uint32).max - 2, "block overflow");
        uint256 maxFee = block.basefee * 2 + PRIORITY_FEE;
        return scheduler.schedule(
            data,
            CHECK_GAS,
            uint32(block.number + 2),
            numCalls,
            frequency,
            SCHEDULER_TTL,
            maxFee,
            PRIORITY_FEE,
            0,
            address(this)
        );
    }

    function _pickExecutor(uint8 capability, uint256 vaultId, uint256 executionIndex)
        internal
        view
        returns (address executor)
    {
        bool found;
        (executor, found) = registry.pickServiceByCapability(
            capability,
            true,
            uint256(keccak256(abi.encode(vaultId, executionIndex, block.prevrandao, capability))),
            32
        );
        require(found && executor != address(0), "no valid executor");
    }

    function _completionContent(bytes memory completionData) internal pure returns (bytes memory content) {
        (,,,,,, uint256 choicesCount, bytes[] memory choicesData,) = abi.decode(
            completionData, (string, string, uint256, string, string, string, uint256, bytes[], bytes)
        );
        require(choicesCount != 0 && choicesData.length != 0, "LLM returned no choices");
        (,, bytes memory messageData) = abi.decode(choicesData[0], (uint256, string, bytes));
        (, string memory messageContent,,,) = abi.decode(messageData, (string, string, string, uint256, bytes[]));
        content = bytes(messageContent);
    }

    function _messages(string memory policy, bytes memory evidence) internal pure returns (string memory) {
        return string.concat(
            '[{"role":"system","content":"Classify liveness evidence. Do not decide asset release. Return JSON only."},',
            '{"role":"user","content":"Vault policy:\\n', _escape(bytes(policy)),
            "\\n\\nExternal evidence:\\n", _escape(evidence), '"}]'
        );
    }

    function _escape(bytes memory input) internal pure returns (string memory) {
        bytes memory out = new bytes(input.length * 2 + 6);
        uint256 length;
        for (uint256 i; i < input.length; ++i) {
            bytes1 char = input[i];
            if (char == 0x22 || char == 0x5c) { out[length++] = 0x5c; out[length++] = char; }
            else if (char == 0x0a) { out[length++] = 0x5c; out[length++] = 0x6e; }
            else if (char == 0x0d) { out[length++] = 0x5c; out[length++] = 0x72; }
            else if (char == 0x09) { out[length++] = 0x5c; out[length++] = 0x74; }
            else if (uint8(char) >= 0x20) { out[length++] = char; }
        }
        assembly { mstore(out, length) }
        return string(out);
    }

    receive() external payable { }
}
