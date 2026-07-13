// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { HeliosAccess } from "../src/security/HeliosAccess.sol";
import { HeliosReceiptToken } from "../src/token/HeliosReceiptToken.sol";
import { HeliosRestakeVault } from "../src/core/HeliosRestakeVault.sol";
import { OperatorRegistry } from "../src/core/OperatorRegistry.sol";
import { DelegationManager } from "../src/core/DelegationManager.sol";
import { WithdrawalQueue } from "../src/core/WithdrawalQueue.sol";
import { EpochRewarder } from "../src/core/EpochRewarder.sol";
import { ReserveVault } from "../src/core/ReserveVault.sol";
import { SlashingController } from "../src/core/SlashingController.sol";
import { HeliosLens } from "../src/views/HeliosLens.sol";
import { HeliosMonitor } from "../src/monitoring/HeliosMonitor.sol";
import { HeliosConstants } from "../src/types/HeliosTypes.sol";

contract DeployHelios is Script {
    struct Deployment {
        HeliosAccess access;
        HeliosRestakeVault vault;
        HeliosReceiptToken receipt;
        OperatorRegistry registry;
        DelegationManager delegation;
        WithdrawalQueue queue;
        EpochRewarder rewarder;
        ReserveVault reserve;
        SlashingController slashing;
        HeliosLens lens;
        HeliosMonitor monitor;
    }

    function run() external returns (Deployment memory deployment) {
        address stakingToken = vm.envAddress("STAKING_TOKEN");
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        address governor = vm.envAddress("GOVERNOR");
        address guardian = vm.envAddress("GUARDIAN");

        vm.startBroadcast();

        deployment.access = new HeliosAccess(governor, guardian);
        deployment.vault =
            new HeliosRestakeVault(stakingToken, rewardToken, address(deployment.access));
        deployment.receipt = new HeliosReceiptToken(
            "Helios Restaked Share", "hrsSTK", 18, address(deployment.vault)
        );
        deployment.registry = new OperatorRegistry(address(deployment.access));
        deployment.delegation = new DelegationManager(
            address(deployment.access), address(deployment.receipt), address(deployment.registry)
        );
        deployment.queue = new WithdrawalQueue(address(deployment.access));
        deployment.rewarder = new EpochRewarder(rewardToken, address(deployment.access));
        deployment.reserve = new ReserveVault(stakingToken, address(deployment.access));
        deployment.slashing =
            new SlashingController(address(deployment.access), address(deployment.registry));

        deployment.delegation.setVault(address(deployment.vault));
        deployment.queue.setVault(address(deployment.vault));
        deployment.rewarder.setVault(address(deployment.vault));
        deployment.rewarder.setDelegationManager(address(deployment.delegation));
        deployment.reserve.setVault(address(deployment.vault));
        deployment.slashing.setVault(address(deployment.vault));
        deployment.registry
            .setAccountingModule(address(deployment.delegation), address(deployment.vault));

        deployment.vault
            .initializeModules(
                address(deployment.receipt),
                address(deployment.registry),
                address(deployment.delegation),
                address(deployment.queue),
                address(deployment.rewarder),
                address(deployment.reserve),
                address(deployment.slashing)
            );

        deployment.access.grantRole(HeliosConstants.SLASHER_ROLE, governor);
        deployment.access.grantRole(HeliosConstants.REWARDER_ROLE, governor);
        deployment.access.grantRole(HeliosConstants.KEEPER_ROLE, governor);

        deployment.lens = new HeliosLens(
            address(deployment.vault),
            address(deployment.registry),
            address(deployment.delegation),
            address(deployment.queue),
            address(deployment.rewarder),
            address(deployment.reserve),
            address(deployment.slashing)
        );
        deployment.monitor = new HeliosMonitor(
            address(deployment.vault),
            address(deployment.registry),
            address(deployment.queue),
            address(deployment.reserve)
        );

        vm.stopBroadcast();
    }
}
