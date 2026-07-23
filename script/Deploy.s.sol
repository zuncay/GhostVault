// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { GhostToken } from "../src/GhostToken.sol";
import { VaultReceipt } from "../src/VaultReceipt.sol";
import { GhostVaultCore } from "../src/GhostVaultCore.sol";
import { GhostVaultAgent } from "../src/GhostVaultAgent.sol";
import { IGhostVaultAgent, IGhostVaultCore } from "../src/interfaces/IGhostVault.sol";

contract Deploy is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        uint256 feeDeposit = vm.envOr("DEPLOY_FEE_DEPOSIT_WEI", uint256(0.1 ether));
        vm.startBroadcast();
        GhostToken token = new GhostToken(deployer);
        VaultReceipt receipt = new VaultReceipt(deployer);
        GhostVaultCore core = new GhostVaultCore(deployer, token, receipt);
        GhostVaultAgent agent = new GhostVaultAgent(deployer, IGhostVaultCore(address(core)));
        core.setAgent(IGhostVaultAgent(address(agent)));
        receipt.transferOwnership(address(core));
        agent.fundFees{ value: feeDeposit }(100_000);
        vm.stopBroadcast();
        console2.log("GhostToken", address(token));
        console2.log("VaultReceipt", address(receipt));
        console2.log("GhostVaultCore", address(core));
        console2.log("GhostVaultAgent", address(agent));
    }
}
