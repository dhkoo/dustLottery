pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

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

    enum Result {
        WINNER,
        LOSER,
        RECEIVED
    }

    struct Lottery {
        uint256 roundId;
        uint256 prizeMoney;
        uint256 numOfRemainingTokens;
        uint256 numberOfWinners;
        uint256 entryFee;
        uint256 startBlock;
        uint256 endBlock;
        uint256[] winners;
        uint256[] receivedPrize;
        uint256[MAX_SUPPLY] mintOrNot;
        Status status;
    }

    event CreateLottery(uint256 indexed roundId, uint256 indexed numberOfWinners, uint256 indexed entryFee);
    event WinLottery(address indexed account, uint256 indexed tokenId);
    event ReceivedPrize(address indexed account, uint256 indexed tokenId);
    event LoseLottery(address indexed account, uint256 indexed tokneId);

    Lottery[] public lotteries;
    uint256 public constant MAX_SUPPLY = 10; // test value
    uint256 public constant DEFAULT_RUNTIME = 3600;
    address public devAddr;
    uint256 private commission;

    constructor(address _devAddr) public ERC721("DUST LOTTERY", "DLO") {
        devAddr = _devAddr;
    }

    function createLottery(
        uint256 _numberOfWinners,
        uint256 _entryFee) public onlyOwner {

        closePrevLottery();

        uint256 roundId = lotteries.length;
        uint256 prizeMoney;
        uint256[] memory winners;
        uint256[] memory receivedPrize;
        uint256[MAX_SUPPLY] memory mintOrNot;

        if (lotteries.length != 0) {
            Lottery memory prevLottery = lotteries[lotteries.length - 1];
            uint256 ownerlessWinnerCount;
            for (uint8 i = 0; i < prevLottery.winners.length; ++i) {
                if (prevLottery.mintOrNot[prevLottery.winners[i]] == 0) {
                    ++ownerlessWinnerCount;
                }
            }
            prizeMoney = prevLottery.prizeMoney.div(ownerlessWinnerCount);
        }

        Lottery memory lottery = Lottery(
            roundId,
            prizeMoney,
            MAX_SUPPLY,
            _numberOfWinners,
            _entryFee,
            0,
            0,
            winners,
            receivedPrize,
            mintOrNot,
            Status.Ready
        );

        lotteries.push(lottery);

        emit CreateLottery(lottery.roundId, lottery.numberOfWinners, lottery.entryFee);
    }

    // consider only latest round
    function closePrevLottery() internal onlyOwner {
        Lottery storage lottery = lotteries[lotteries.length - 1];
        if (lottery.status == Status.Completed) {
            lottery.status = Status.Closed;
            payable(devAddr).transfer(commission);
        }
    }

    // consider only latest round
    function startLotteryAtfer(uint256 _seconds) external onlyOwner {
        require(lotteries.length > 0);
        Lottery storage lottery = lotteries[lotteries.length - 1];
        require(lottery.status == Status.Ready &&
                lottery.startBlock == 0 && lottery.endBlock == 0);

        lottery.startBlock = block.number + _seconds;
        lottery.endBlock = lottery.startBlock + DEFAULT_RUNTIME;
    }

    // consider only latest round
    function delayLotteryEndTime(uint256 _seconds) external onlyOwner {
        Lottery storage lottery = lotteries[lotteries.length - 1];
        require(getLotteryStatus(lottery.roundId) == Status.InProgress);
        lottery.endBlock += _seconds;
    }

    // consider only latest round
    function updateLotteryStatus(Status _status) external onlyOwner {
        Lottery storage lottery = lotteries[lotteries.length - 1];
        lottery.status = _status;
    }

    function getRoundInfo(uint256 _roundId) public view returns (Lottery memory) {
        require(lotteries.length > 0 && _roundId < lotteries.length, "NOT_EXIST_ROUND");
        return lotteries[_roundId];
    }

    function getWinners(uint256 _roundId) public view returns (uint256[] memory) {
        require(lotteries.length > 0 && _roundId < lotteries.length, "NOT_EXIST_ROUND");
        return lotteries[_roundId].winners;
    }

    function getReceived(uint256 _roundId) public view returns (uint256[] memory) {
        require(lotteries.length > 0 && _roundId < lotteries.length, "NOT_EXIST_ROUND");
        return lotteries[_roundId].receivedPrize;
    }

    // tokenId 0~99 come from FE
    // convert tokenId to right tokenId
    // consider only latest round
    function mint(uint256 _tokenId) public payable {
        Lottery storage lottery = lotteries[lotteries.length - 1];

        require(!address(msg.sender).isContract(), "CONTRACT_DISABLED");
        require(getLotteryStatus(lottery.roundId) == Status.InProgress, "NOT_INPROGRESS");
        require(msg.value >= lottery.entryFee, "NOT_ENOUGH_PAYMENT");
        require(lottery.numOfRemainingTokens != 0, "NO_REMAINING_TOKENS");
        require(lottery.mintOrNot[_tokenId] != 1, "ALREAD_MINTED");

        uint256 fee = uint256(msg.value).div(10);
        commission += fee;
        lottery.prizeMoney += uint256(msg.value).sub(fee);

        --lottery.numOfRemainingTokens;
        lottery.mintOrNot[_tokenId] = 1;
        
        if (lottery.numOfRemainingTokens == 0) {
            lottery.status = Status.Completed;
        }
        _tokenId += (lotteries.length - 1) * MAX_SUPPLY;
        _mint(msg.sender, _tokenId);
    }

    function getLotteryStatus(uint256 _roundId) public view returns (Status) {
        require(lotteries.length > 0 && _roundId < lotteries.length, "NOT_EXIST_ROUND");

        Status status = lotteries[_roundId].status;
        return status == Status.Ready && block.number >= lotteries[_roundId].startBlock ?
            Status.InProgress : status;
    }
    
    function getTokenUsedInfo(uint256 _roundId) public view returns (uint256[MAX_SUPPLY] memory) {
        return lotteries[_roundId].mintOrNot;
    }

    function drawForWinners() public onlyOwner {
        Lottery storage lottery = lotteries[lotteries.length - 1];
        require(lottery.winners.length <= lottery.numberOfWinners, "ALREADY_DRAWN");
        require(lottery.status == Status.Completed || 
                block.number >= lottery.endBlock && lottery.status == Status.InProgress &&
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

    function checkWinner(uint256 _roundId, uint256 _tokenId) public view returns (Result) {
        Lottery storage lottery = lotteries[_roundId];
        require(lottery.status == Status.Completed, "NOT_AVAILABLE");

        bool isWinner = false;
        _tokenId -= (lotteries.length - 1) * MAX_SUPPLY;

        for (uint8 i = 0; i < lottery.numberOfWinners; ++i) {
            if (lottery.winners[i] == _tokenId && !isReceivedPrize(_roundId, _tokenId)) {
                isWinner = true;
            }
        }
        if (isWinner) {
            if (isReceivedPrize(_roundId, _tokenId)) {
                return Result.RECEIVED;
            }
            return Result.WINNER;
        }
        return Result.LOSER;
    }

    // need to approve
    function claimReward(uint256 _roundId, uint256 _tokenId) public payable nonReentrant {
        require(msg.sender == ERC721.ownerOf(_tokenId), "NOT_OWNED");
        Lottery storage lottery = lotteries[_roundId];
        require(lottery.status == Status.Completed, "NOT_AVAILABLE");

        if (checkWinner(_roundId, _tokenId) == Result.WINNER) {
            transferFrom(msg.sender, address(this), _tokenId);
            lottery.receivedPrize.push(_tokenId);
            uint256 ratio = 1e6 / lottery.numberOfWinners;
            payable(msg.sender).transfer(lottery.prizeMoney.mul(ratio).div(1e6));
            _burn(_tokenId);
        }
    }

    function isReceivedPrize(uint256 _roundId, uint256 _tokenId) internal view returns (bool) {
        Lottery memory lottery = lotteries[_roundId];
        for (uint8 i = 0; i < lottery.receivedPrize.length; ++i) {
            if (lottery.receivedPrize[i] == _tokenId)
                return true;
        }
        return false;
    }

    function userTokenIds() external view returns (uint256[] memory tokenIds) {
        uint256 count = balanceOf(msg.sender);
        for (uint8 i = 0; i < count; ++i) {
            tokenIds[i] = tokenOfOwnerByIndex(msg.sender, i);
        }
    }
}
