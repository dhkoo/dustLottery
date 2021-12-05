pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";

contract DustLottery is ERC721, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;

    enum Status {
        None,
        Ready,
        InProgress,
        Completed,
        Cancle,
        Closed
    }

    struct Lottery {
        uint256 roundId;
        uint256 prizeMoney;
        uint256 numOfRemainingTokens;
        uint256 numberOfWinners;
        uint256 entryFee;
        uint256 startTime;
        uint256 endTime;
        uint256[] winners;
        uint256[] receivedPrize;
        Status status;
    }

    event CreateLottery(uint256 indexed roundId, uint256 indexed endTime);
    event WinLottery(address indexed account, uint256 indexed tokenId);
    event ReceivedPrize(address indexed account, uint256 indexed tokenId);
    event LoseLottery(address indexed account, uint256 indexed tokneId);

    Lottery[] public lotteries;
    uint256 public constant MAX_SUPPLY = 10; // test value
    uint256[MAX_SUPPLY] public useOrNot;

    constructor() public ERC721("DUST LOTTERY", "DLO") {}

    function createLottery(
        uint256 numberOfWinners,
        uint256 entryFee,
        uint256 startTime) public onlyOwner {

        uint256 roundId = lotteries.length;
        uint256[] memory winners;
        uint256[] memory receivedPrize;

        Lottery memory lottery = Lottery(
            roundId,
            migratePrizeMoney(),
            MAX_SUPPLY,
            numberOfWinners,
            entryFee,
            startTime,
            startTime + 3600, // default; can be changed
            winners,
            receivedPrize,
            Status.Ready
        );

        lotteries.push(lottery);

        emit CreateLottery(lottery.roundId, lottery.endTime);
    }

    // only called when create lottery
    function migratePrizeMoney() internal returns (uint256) {
        if (lotteries.length == 0) {
            return 0;
        }
        Lottery storage lottery = lotteries[lotteries.length];
        lottery.status = Status.Closed;

        return address(this).balance;
    }

    function getWinners(uint256 roundId) public view returns (uint256[] memory) {
        require(roundId <= lotteries.length - 1, "NOT_EXIST_ROUND");
        return lotteries[roundId].winners;
    }

    function getReceived(uint256 roundId) public view returns (uint256[] memory) {
        require(roundId <= lotteries.length - 1, "NOT_EXIST_ROUND");
        return lotteries[roundId].receivedPrize;
    }

    // tokenId 0~99 come from FE
    // convert tokenId to right tokenId
    function mint(uint256 tokenId) public payable {
        Lottery storage lottery = lotteries[lotteries.length - 1];

        require(!address(msg.sender).isContract(), "CONTRACT_DISABLED");
        require(lotteryStatus(lottery.roundId) == Status.InProgress, "NOT_INPROGRESS");
        require(msg.value >= lottery.entryFee, "NOT_ENOUGH_PAYMENT");
        require(lottery.numOfRemainingTokens != 0, "NO_REMAINING_TOKENS");
        require(useOrNot[tokenId] != 1, "ALREADY_USED");

        lottery.prizeMoney += msg.value;
        --lottery.numOfRemainingTokens;
        useOrNot[tokenId] = 1;
        
        if (lottery.numOfRemainingTokens == 0) {
            lottery.status = Status.Completed;
        }
        tokenId += (lotteries.length - 1) * MAX_SUPPLY;
        _mint(msg.sender, tokenId);
    }

    function lotteryStatus(uint256 roundId) public view returns (Status) {
        if (roundId >= lotteries.length)
            return Status.None;

        Status status = lotteries[roundId].status;
        return status == Status.Ready && block.timestamp >= lotteries[roundId].startTime ?
            Status.InProgress : status;
    }
    
    function getTokenUsedInfo() public view returns (uint256[MAX_SUPPLY] memory) {
        return useOrNot;
    }

    function drawForWinners() public onlyOwner {
        Lottery storage lottery = lotteries[lotteries.length - 1];
        require(lottery.winners.length <= lottery.numberOfWinners, "ALREADY_DRAWN");
        require(lottery.status == Status.Completed || 
                block.number >= lottery.endTime && lottery.status == Status.InProgress &&
                lottery.numOfRemainingTokens <= MAX_SUPPLY.div(2),
                "NOT_AVAILABLE");

        uint256 remainder = lottery.numberOfWinners;

        while (remainder != 0) {
            uint256 number = 
                uint256(uint256(keccak256(abi.encodePacked(
                    block.timestamp,
                    block.number,
                    remainder))) % MAX_SUPPLY);

            bool isExist = false;
            for (uint8 i = 0; i < lottery.winners.length; ++i) {
                if (lottery.winners[i] == number)
                    isExist = true;
            }
            if (!isExist) {
                lottery.winners.push(number);
                --remainder;
            }
        }

        lottery.status = Status.Completed;
    }

    function claimReward(uint256 tokenId) public payable nonReentrant {
        require(msg.sender == ERC721.ownerOf(tokenId), "NOT_OWNED");
        Lottery storage lottery = lotteries[lotteries.length - 1];
        require(lottery.status == Status.Completed, "NOT_AVAILABLE");

        bool isWinner = false;
        tokenId -= (lotteries.length - 1) * MAX_SUPPLY;

        for (uint8 i = 0; i < lottery.numberOfWinners; ++i) {
            if (lottery.winners[i] == tokenId && !isReceivedPrize(tokenId)) {
                lottery.receivedPrize.push(tokenId);
                isWinner = true;
            }
        }
        if (isWinner) {
            uint256 ratio = 1e6 / lottery.numberOfWinners;
            payable(msg.sender).transfer(lottery.prizeMoney.mul(ratio).div(1e6));
            emit WinLottery(msg.sender, tokenId);
        } else {
            if (isReceivedPrize(tokenId))
                emit ReceivedPrize(msg.sender, tokenId);
            else
                emit LoseLottery(msg.sender, tokenId);
        }
    }

    function isReceivedPrize(uint256 tokenId) internal returns (bool) {
        Lottery memory lottery = lotteries[lotteries.length - 1];
        for (uint8 i = 0; i < lottery.receivedPrize.length; ++i) {
            if (lottery.receivedPrize[i] == tokenId)
                return true;
        }
        return false;
    }
}
