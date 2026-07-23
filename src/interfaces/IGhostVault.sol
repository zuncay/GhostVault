// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IGhostVaultCore {
    function monitoringContext(uint256 vaultId)
        external
        view
        returns (uint8 state, uint256 heartbeatDeadline, string memory statusUrl, string memory policy);

    function onMonitoringResult(uint256 vaultId, bytes32 evidenceHash, bytes32 resultHash) external;
}

interface IGhostVaultAgent {
    function scheduleMonitoring(uint256 vaultId, uint32 frequencyBlocks) external returns (uint256);
    function requestCheck(uint256 vaultId) external returns (uint256);
    function cancelMonitoring(uint256 scheduleId) external;
}

