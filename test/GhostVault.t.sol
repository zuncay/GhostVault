// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";
import { GhostToken } from "../src/GhostToken.sol";
import { VaultReceipt } from "../src/VaultReceipt.sol";
import { GhostVaultCore } from "../src/GhostVaultCore.sol";
import { GhostVaultAgent } from "../src/GhostVaultAgent.sol";
import { IGhostVaultAgent, IGhostVaultCore } from "../src/interfaces/IGhostVault.sol";
import {
    MockScheduler, MockTEERegistry, MockHTTPPrecompile, MockLLMPrecompile,
    MockJQPrecompile, MockRitualWallet
} from "./mocks/MockRitualSystem.sol";

contract GhostVaultTest is Test {
    address constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address constant WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address constant REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address constant HTTP = address(0x0801);
    address constant LLM = address(0x0802);
    address constant JQ = address(0x0803);

    GhostToken token;
    VaultReceipt receipt;
    GhostVaultCore core;
    GhostVaultAgent agent;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address guardian = address(0xCAFE);

    function setUp() public {
        vm.etch(SCHEDULER, address(new MockScheduler()).code);
        vm.etch(WALLET, address(new MockRitualWallet()).code);
        vm.etch(REGISTRY, address(new MockTEERegistry()).code);
        vm.etch(HTTP, address(new MockHTTPPrecompile()).code);
        vm.etch(LLM, address(new MockLLMPrecompile()).code);
        vm.etch(JQ, address(new MockJQPrecompile()).code);
        MockHTTPPrecompile(HTTP).configure(false);
        MockLLMPrecompile(LLM).configure("inactive", 88, false);
        MockJQPrecompile(JQ).configure("inactive", 88);

        token = new GhostToken(address(this));
        receipt = new VaultReceipt(address(this));
        core = new GhostVaultCore(address(this), token, receipt);
        agent = new GhostVaultAgent(address(this), IGhostVaultCore(address(core)));
        core.setAgent(IGhostVaultAgent(address(agent)));
        receipt.transferOwnership(address(core));
        token.transfer(alice, 10_000 ether);
        vm.prank(alice);
        token.approve(address(core), type(uint256).max);
    }

    function testBypassReleaseEndToEnd() public {
        agent.setBypassPrecompiles(true, keccak256("evidence"), keccak256("result"));
        uint256 vaultId = _createVault("");
        GhostVaultCore.Vault memory vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Armed));
        assertEq(vault.scheduleId, 1);
        vm.warp(block.timestamp + 1 hours + 1);
        core.pokeVault(vaultId);
        vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Grace));
        vm.warp(vault.releaseAt);
        core.finalizeRelease(vaultId);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(receipt.ownerOf(vaultId), bob);
    }

    function testRealSchedulerHttpLlmPipeline() public {
        uint256 vaultId = _createVault("https://status.example/alice.json");
        vm.warp(block.timestamp + 1 hours + 1);
        MockScheduler(SCHEDULER).trigger(1, 0);
        assertEq(uint8(agent.getCheck(vaultId).stage), uint8(GhostVaultAgent.CheckStage.HttpScheduled));
        MockScheduler(SCHEDULER).trigger(2, 0);
        assertEq(uint8(agent.getCheck(vaultId).stage), uint8(GhostVaultAgent.CheckStage.LlmScheduled));
        MockScheduler(SCHEDULER).trigger(3, 0);
        GhostVaultCore.Vault memory vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Grace));
        assertTrue(vault.evidenceHash != bytes32(0));
        assertTrue(vault.resultHash != bytes32(0));
    }

    function testAliveSignalDoesNotStartGrace() public {
        MockLLMPrecompile(LLM).configure("alive", 97, false);
        MockJQPrecompile(JQ).configure("alive", 97);
        uint256 vaultId = _createVault("https://status.example/alice.json");
        vm.warp(block.timestamp + 1 hours + 1);
        MockScheduler(SCHEDULER).trigger(1, 0);
        MockScheduler(SCHEDULER).trigger(2, 0);
        MockScheduler(SCHEDULER).trigger(3, 0);
        GhostVaultCore.Vault memory vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Armed));
        assertEq(vault.releaseAt, 0);
        assertTrue(vault.evidenceHash != bytes32(0));
        assertTrue(vault.resultHash != bytes32(0));
    }

    function testLowConfidenceInactiveDoesNotStartGrace() public {
        MockLLMPrecompile(LLM).configure("inactive", 60, false);
        MockJQPrecompile(JQ).configure("inactive", 60);
        uint256 vaultId = _createVault("https://status.example/alice.json");
        vm.warp(block.timestamp + 1 hours + 1);
        MockScheduler(SCHEDULER).trigger(1, 0);
        MockScheduler(SCHEDULER).trigger(2, 0);
        MockScheduler(SCHEDULER).trigger(3, 0);
        GhostVaultCore.Vault memory vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Armed));
        assertEq(vault.releaseAt, 0);
    }

    function testHttpFailureFailsClosedAndAllowsRetry() public {
        MockHTTPPrecompile(HTTP).configure(true);
        uint256 vaultId = _createVault("https://status.example/alice.json");
        vm.warp(block.timestamp + 1 hours + 1);
        MockScheduler(SCHEDULER).trigger(1, 0);
        MockScheduler(SCHEDULER).trigger(2, 0);
        GhostVaultCore.Vault memory vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Armed));
        assertEq(uint8(agent.getCheck(vaultId).stage), uint8(GhostVaultAgent.CheckStage.None));
        assertEq(vault.resultHash, bytes32(0));
    }

    function testLlmFailureFailsClosedAndAllowsRetry() public {
        MockLLMPrecompile(LLM).configure("inactive", 88, true);
        uint256 vaultId = _createVault("https://status.example/alice.json");
        vm.warp(block.timestamp + 1 hours + 1);
        MockScheduler(SCHEDULER).trigger(1, 0);
        MockScheduler(SCHEDULER).trigger(2, 0);
        MockScheduler(SCHEDULER).trigger(3, 0);
        GhostVaultCore.Vault memory vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Armed));
        assertEq(uint8(agent.getCheck(vaultId).stage), uint8(GhostVaultAgent.CheckStage.None));
        assertEq(vault.resultHash, bytes32(0));
    }

    function testRejectsMissingStatusUrl() public {
        vm.prank(alice);
        vm.expectRevert("invalid status URL");
        core.createVault(
            "Invalid recovery vault", bob, guardian, 100 ether, 1 hours, 10 minutes, 100,
            keccak256("encrypted-payload"), "https://storage.example/encrypted.bin", "",
            "External liveness evidence is required."
        );
    }

    function testMonitoringRenewsBeforeScheduleLifespanEnds() public {
        uint256 vaultId = _createVault("https://status.example/alice.json");
        assertEq(agent.activeScheduleByVault(vaultId), 1);
        MockScheduler(SCHEDULER).trigger(1, 2);
        assertEq(agent.activeScheduleByVault(vaultId), 2);
        assertEq(agent.vaultBySchedule(2), vaultId);
    }

    function testHeartbeatReactivatesDuringGrace() public {
        agent.setBypassPrecompiles(true, bytes32(0), bytes32(0));
        uint256 vaultId = _createVault("");
        vm.warp(block.timestamp + 1 hours + 1);
        core.pokeVault(vaultId);
        vm.prank(guardian);
        core.heartbeat(vaultId);
        GhostVaultCore.Vault memory vault = core.getVault(vaultId);
        assertEq(uint8(vault.state), uint8(GhostVaultCore.VaultState.Armed));
        assertEq(vault.releaseAt, 0);
    }

    function testCancelReturnsEscrow() public {
        uint256 beforeBalance = token.balanceOf(alice);
        uint256 vaultId = _createVault("");
        vm.prank(alice);
        core.cancelVault(vaultId);
        assertEq(token.balanceOf(alice), beforeBalance);
        assertEq(uint8(core.getVault(vaultId).state), uint8(GhostVaultCore.VaultState.Cancelled));
    }

    function testCannotFinalizeBeforeGraceEnds() public {
        agent.setBypassPrecompiles(true, bytes32(0), bytes32(0));
        uint256 vaultId = _createVault("");
        vm.warp(block.timestamp + 1 hours + 1);
        core.pokeVault(vaultId);
        vm.expectRevert("grace active");
        core.finalizeRelease(vaultId);
    }

    function testFundAgentWallet() public {
        vm.deal(address(this), 1 ether);
        agent.fundFees{ value: 0.2 ether }(10_000);
        assertEq(agent.feeBalance(), 0.2 ether);
    }

    function _createVault(string memory statusURL) internal returns (uint256 vaultId) {
        string memory effectiveStatusURL = bytes(statusURL).length == 0
            ? "https://status.example/default.json"
            : statusURL;
        vm.prank(alice);
        vaultId = core.createVault(
            "Alice recovery vault", bob, guardian, 100 ether, 1 hours, 10 minutes, 100,
            keccak256("encrypted-payload"), "https://storage.example/encrypted.bin", effectiveStatusURL,
            "Begin recovery if the owner misses the onchain heartbeat. External evidence is informational."
        );
    }
}
