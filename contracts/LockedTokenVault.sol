// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IBEP20, SafeBEP20} from "./libs/SafeBEP20.sol";

contract LockedTokenVault is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 public token;
    address public masterChef;

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


    event LockToken(address indexed holder, uint256 origin, uint256 claimed, uint256 amount);
    event TransferLockedToken(address indexed from, address indexed to, uint256 origin, uint256 claimed);
    event Claim(address indexed holder, uint256 origin, uint256 claimed, uint256 amount);

    function setMasterChef(address _masterChef) public onlyOwner {
        require(_masterChef != address(0), "zero address");
        masterChef = _masterChef;
    }

    function lockToken(address holder, uint256 amount) external {
        require(holder != address(0), "zero address");
        require(msg.sender == masterChef, "not masterchef");
        // for saving gas, no event for grant
        originBalances[holder] = originBalances[holder].add(amount);
        unclaimedAmount = unclaimedAmount.add(amount);
        emit LockToken(holder, originBalances[holder], claimedBalances[holder], amount);
    }

    function transferLockedToken(address to) external {
        uint256 originBalance = originBalances[msg.sender];
        uint256 claimedBalance = claimedBalances[msg.sender];

        originBalances[msg.sender] = 0;
        claimedBalances[msg.sender] = 0;

        originBalances[to] = originBalances[to].add(originBalance);
        claimedBalances[to] = claimedBalances[to].add(claimedBalance);

        
        emit TransferLockedToken(msg.sender, to, originBalance, claimedBalance);
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