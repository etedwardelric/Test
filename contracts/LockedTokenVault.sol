// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol';
import {IBEP20, SafeBEP20} from "./libs/SafeBEP20.sol";


contract LockedTokenVault is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 _TOKEN_;

    mapping(address => uint256) internal originBalances;
    mapping(address => uint256) internal claimedBalances;

    uint256 public _UNDISTRIBUTED_AMOUNT_;
    uint256 public _START_RELEASE_BLOCK_NUM_;
    uint256 public _RELEASE_BLOCKS_;

    constructor(
        IBEP20 _token,
        uint256 _startReleaseBlockNum,
        uint256 _releaseBlocks
    ) public {
        _TOKEN_ = _token;
        _START_RELEASE_BLOCK_NUM_ = _startReleaseBlockNum;
        _RELEASE_BLOCKS_ = _releaseBlocks;
    }

    event Claim(address indexed holder, uint256 origin, uint256 claimed, uint256 amount);

    modifier beforeStartRelease() {
        require(block.number < _START_RELEASE_BLOCK_NUM_, "RELEASE START");
        _;
    }

    modifier afterStartRelease() {
        require(block.number >= _START_RELEASE_BLOCK_NUM_, "RELEASE NOT START");
        _;
    }

    function lock(address holder, uint256 amount)
        external
        onlyOwner
    {
        require(holder != address(0), "bad");
        // for saving gas, no event for grant
        originBalances[holder] = originBalances[holder].add(amount);
        _UNDISTRIBUTED_AMOUNT_ = _UNDISTRIBUTED_AMOUNT_.sub(amount);
    }

    function transferLockedToken(address to) external {
        originBalances[to] = originBalances[to].add(originBalances[msg.sender]);
        claimedBalances[to] = claimedBalances[to].add(claimedBalances[msg.sender]);

        originBalances[msg.sender] = 0;
        claimedBalances[msg.sender] = 0;
    }

    function claim() external {
        uint256 claimableToken = getClaimableBalance(msg.sender);
        _tokenTransferOut(msg.sender, claimableToken);
        claimedBalances[msg.sender] = claimedBalances[msg.sender].add(claimableToken);
        emit Claim(
            msg.sender,
            originBalances[msg.sender],
            claimedBalances[msg.sender],
            claimableToken
        );
    }

    function isReleaseStart() external view returns (bool) {
        return block.number >= _START_RELEASE_BLOCK_NUM_;
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
        if (blockNumber < _START_RELEASE_BLOCK_NUM_) {
            return 1e18;
        }
        uint256 bocks = blockNumber.sub(_START_RELEASE_BLOCK_NUM_);
        if (bocks < _RELEASE_BLOCKS_) {
            uint256 remainingBlocks = _RELEASE_BLOCKS_.sub(bocks);
            return remainingBlocks.mul(1e18).div(_RELEASE_BLOCKS_);
        } else {
            return 0;
        }
    }

    function _tokenTransferIn(address from, uint256 amount) internal {
        IBEP20(_TOKEN_).safeTransferFrom(from, address(this), amount);
    }

    function _tokenTransferOut(address to, uint256 amount) internal {
        IBEP20(_TOKEN_).safeTransfer(to, amount);
    }
}