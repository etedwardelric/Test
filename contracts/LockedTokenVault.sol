// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol';
import {IBEP20, SafeBEP20} from "./libs/SafeBEP20.sol";


contract LockedTokenVault is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 token;

    mapping(address => uint256) internal originBalances;
    mapping(address => uint256) internal claimedBalances;

    uint256 public unclaimedAmount;
    uint256 public startReleaseBlockNum;
    uint256 public releaseBlocks;

    constructor(
        IBEP20 _token,
        uint256 _startReleaseBlockNum,
        uint256 _releaseBlocks
    ) public {
        token = _token;
        startReleaseBlockNum = _startReleaseBlockNum;
        releaseBlocks = _releaseBlocks;
    }

    event Claim(address indexed holder, uint256 origin, uint256 claimed, uint256 amount);

    modifier beforeStartRelease() {
        require(block.number < startReleaseBlockNum, "RELEASE START");
        _;
    }

    modifier afterStartRelease() {
        require(block.number >= startReleaseBlockNum, "RELEASE NOT START");
        _;
    }

    function lockToken(address holder, uint256 amount) external onlyOwner
    {
        require(holder != address(0), "bad");
        // for saving gas, no event for grant
        originBalances[holder] = originBalances[holder].add(amount);
        unclaimedAmount = unclaimedAmount.add(amount);
    }

    function transferLockedToken(address to) external {
        originBalances[to] = originBalances[to].add(originBalances[msg.sender]);
        claimedBalances[to] = claimedBalances[to].add(claimedBalances[msg.sender]);

        originBalances[msg.sender] = 0;
        claimedBalances[msg.sender] = 0;
    }

    function claim() external {
        uint256 claimableToken = getClaimableBalance(msg.sender);
        claimedBalances[msg.sender] = claimedBalances[msg.sender].add(claimableToken);
        unclaimedAmount = unclaimedAmount.sub(claimableToken);
        _tokenTransferOut(msg.sender, claimableToken);
        emit Claim(
            msg.sender,
            originBalances[msg.sender],
            claimedBalances[msg.sender],
            claimableToken
        );
    }

    function isReleaseStart() external view returns (bool) {
        return block.number >= startReleaseBlockNum;
    }

    function getOriginBalance(address holder) external view returns (uint256) {
        return originBalances[holder];
    }

    function getClaimedBalance(address holder) external view returns (uint256) {
        return claimedBalances[holder];
    }

    function getClaimableBalance(address holder) public view returns (uint256) {
        uint256 remainingToken = getRemainingBalance(holder);
        return originBalances[holder].sub(remainingToken).sub(claimedBalances[holder]);
    }
    
    function getRemainingBalance(address holder) public view returns (uint256) {
        uint256 remainingRatio = getRemainingRatio(block.timestamp);
        return originBalances[holder].mul(remainingRatio).div(1e18);
    }

    function getRemainingRatio(uint256 blockNumber) public view returns (uint256) {
        if (blockNumber < startReleaseBlockNum) {
            return 1e18;
        }
        uint256 bocks = blockNumber.sub(startReleaseBlockNum);
        if (bocks < releaseBlocks) {
            uint256 remainingBlocks = releaseBlocks.sub(bocks);
            return remainingBlocks.mul(1e18).div(releaseBlocks);
        } else {
            return 0;
        }
    }

    function _tokenTransferOut(address to, uint256 amount) internal {
        IBEP20(token).safeTransfer(to, amount);
    }
}