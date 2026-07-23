// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function balanceOf(address account) external view returns (uint256);
}

interface IScheduler {
    function schedule(
        bytes memory data,
        uint32 gasLimit,
        uint32 startBlock,
        uint32 numCalls,
        uint32 frequency,
        uint32 ttl,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint256 value,
        address payer
    ) external returns (uint256 callId);

    function cancel(uint256 callId) external;
    function getCallState(uint256 callId) external view returns (uint8);
}

interface ITEEServiceRegistry {
    function pickServiceByCapability(uint8 capability, bool checkValidity, uint256 seed, uint256 maxProbes)
        external
        view
        returns (address teeAddress, bool found);
}

