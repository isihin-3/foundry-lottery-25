// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    event RaffleEntered(address indexed player);
    event RecentWinner(address indexed winner);

    uint256 enteranceFee = 5 ether;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;
    address public PLAYER = makeAddr("Player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.DeployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        enteranceFee = config.enteranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    modifier raffelStart() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testInitialStateOfTheRaffle() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testWhenEnterWithNoEth() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__sendMoreEthToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEventEmits() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
    }

    function testDontAllowPlayerToEneterWhileRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
        vm.expectRevert();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        // assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool checkUpKeep,) = raffle.checkUpkeep("");
        assert(!checkUpKeep);
    }

    function testCheckUpKeepReturnsFalseRaffleIsntOPEN() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        (bool checkUpKeep,) = raffle.checkUpkeep("");
        assert(!checkUpKeep);
    }

    function testCheckUpKeepReturnFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        // vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // raffle.performUpkeep("");
        (bool checkUpKeep,) = raffle.checkUpkeep("");
        assert(!checkUpKeep);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        (bool checkUpKeep,) = raffle.checkUpkeep("");
        assert(checkUpKeep);
    }

    function testPerformUpkeepRevertsIfCheekUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numeberOfPlayer = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        numeberOfPlayer = 1;
        currentBalance = enteranceFee + currentBalance;
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__upkeepNotNeeded.selector, currentBalance, numeberOfPlayer, rState)
        );
        // console.log("this contract has balance of",address(this).balance);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitRequestId() public raffelStart {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    function testFullfillRandomWordCanOnlyBeCalledAfterPerformUpkeep(uint256 requestId) public raffelStart {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffelStart {
        uint256 addtionalEntry = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);
        for (uint256 i = startingIndex; i < startingIndex + addtionalEntry; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: enteranceFee}();
        }

        uint256 startingTimeStamp = raffle.getTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getTimeStamp();
        uint256 prize = enteranceFee * (addtionalEntry + 1);
        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
        // console.log(winnerBalance);
        // console.log(prize);
        // console.log(winnerStartingBalance);
    }
}
