// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A sample Raffle Contract
 * @author Rahul Kumar Mahto
 * @notice This contract s for creating a sample Raffle
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* errors */
    error Raffle__sendMoreEthToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__NotOpen();
    error Raffle__upkeepNotNeeded(uint256 balance, uint256 playerLength, uint256 raffleState);

    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1

    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint16 private constant NUM_WORDS = 1;
    address payable[] private s_players; // each address must be payable so you can send them ETH in the future.
    uint256 private immutable i_enteranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyhash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address private s_recentWinner;
    uint256 private s_lastTimestamp;
    RaffleState private s_raffleState;

    /* events */
    event RaffleEntered(address indexed player);
    event RecentWinner(address indexed winner);
    event RequestRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 enteranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        // if we are inhreating a contract and that contract has already a constructor then we have to put it in our constructor as well in this way
        i_enteranceFee = enteranceFee;
        i_interval = interval;
        i_keyhash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimestamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        /**
         * we will not using because it stores error(string) which is not efficent for gas
         */
        // require(msg.value >= i_enteranceFee,"Not enough funds to enter");
        // require(msg.value >= i_enteranceFee, sendMoreEthToEnterRaffle());
        // ->it is still less gas efficent than if and also works on specific versions of solidity
        if (msg.value < i_enteranceFee) {
            revert Raffle__sendMoreEthToEnterRaffle();
        }
        if (RaffleState.OPEN != s_raffleState) {
            revert Raffle__NotOpen();
        }
        s_players.push(payable(msg.sender)); // while pushing it needs to be typecasted to enter in the payable array
        emit RaffleEntered(msg.sender);
    }
    /**
     * @dev This is the function that the Chainlink nodes will call to see
     * if the lottery is ready to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH
     * 4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */

    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimestamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__upkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyhash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });
        uint256 requestID = s_vrfCoordinator.requestRandomWords(request);

        emit RequestRaffleWinner(requestID);
    }

    // this is a abtract function which is made in the parent abstract contract so we have to use it once using override
    // beacaue in the parent contract it is virtual and by using override we can write our own logic in the function
    // CEI -> Checks, Effects, Interaction -> always keeps in this way in a function
    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] calldata randomWords
    ) internal override {
        // Checks(like if statements, require )

        // Effects (Internal contract state)
        uint256 indesOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indesOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        emit RecentWinner(s_recentWinner);

        // Interaction (External contract Interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_enteranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getTimeStamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
