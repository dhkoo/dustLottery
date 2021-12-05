pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";

contract DustLottery is ERC721, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public prizeMoney;
    uint256 public entryFee = 5 * 1e18;
    uint256 public constant MAX_SUPPLY = 10;
    uint256 public mintingCount = 0;

    uint256 public constant numberOfWinners = 3;
    bool public isDrawn = false;

    mapping(uint256 => bool) public winners; // 당첨 번호
    mapping(uint256 => bool) public receivedReward; // 수령 확인

    constructor() public ERC721("DUST LOTTERY", "DLO") {}

    function mint() public payable {
        require(msg.value >= entryFee, "NOT_ENOUGH_PAYMENT");
        require(mintingCount < MAX_SUPPLY, "EXCEED_MAX_SUPPLY");

        prizeMoney += msg.value;
        //TODO: randomlized..
        _mint(msg.sender, ++mintingCount);
    }

    function drawForWinners() public onlyOwner {
        require(!isDrawn, "ALREADY_DRAW"); 

        uint256 remainder = numberOfWinners;

        while (remainder != 0) {
            uint256 number = 
                uint256(uint256(keccak256(abi.encodePacked(
                    block.timestamp,
                    block.number,
                    remainder))) % MAX_SUPPLY) + 1; 

            if (winners[number] == false) {
                winners[number] = true;
                --remainder;
            }
        }
        isDrawn = true;
    }

    function claimReward() public payable nonReentrant {
        uint256 total = balanceOf(msg.sender);
        uint256 winCount = 0;
        for (uint256 i = 0; i < total; ++i) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i);
            if (winners[tokenId] == true) {
                if (receivedReward[tokenId] == false) {
                    receivedReward[tokenId] = true;
                    ++winCount;
                }
            }
        }
        if (winCount != 0) {
            uint256 ratio = winCount.mul(1e6).div(numberOfWinners);
            payable(msg.sender).transfer(prizeMoney.mul(ratio).div(1e6));
        }
    }

    function isWinner() public view returns (bool isWinner, uint256 winCount) {
        uint256 total = balanceOf(msg.sender);
        for (uint256 i = 0; i < total; ++i) {
            if (winners[tokenOfOwnerByIndex(msg.sender, i)] == true) {
                isWinner = true;
                ++winCount;
            }
        }
    }
}
