// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription,FundSubcription,AddConsumer} from "./Interaction.s.sol";

contract DeployRaffle is Script {
    uint256 deployKey = vm.envUint("PRIVATE_KEY");
    function run() external {
        DeployContract();
    }

    function DeployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) =
                createSubscription.createSubscription(config.vrfCoordinator);
            FundSubcription fundSubscription = new FundSubcription();
            fundSubscription.fundSubscription(config.vrfCoordinator,config.subscriptionId,config.link);
        }

        vm.startBroadcast();
        Raffle raffle = new Raffle(
            config.enteranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(raffle),config.vrfCoordinator,config.subscriptionId);
        return (raffle, helperConfig);
    }
}
