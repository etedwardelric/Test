// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeMath} from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import {Ownable} from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";

import {IBEP20} from "./libs/SafeBEP20.sol";
import {SafeBEP20} from "./libs/SafeBEP20.sol";
import {MarsToken} from "./MarsToken.sol";
import {LockedTokenVault} from "./LockedTokenVault.sol";

// MasterChef is the master of Mars. He can make Mars and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Mars is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Mars
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMarsPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMarsPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Mars to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Mars distribution occurs.
        uint256 accMarsPerShare;   // Accumulated Mars per share, times 1e12. See below.
    }

    // The Mars TOKEN!
    MarsToken public mars;
    // The Locked Mars TOKEN!
    LockedTokenVault public lockedTokenVault;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    
    // Dev address.
    address public devAddress;
    // Project treasory Fee address
    address public pjtrAddress;

    // Mars tokens created per block.
    uint256 public marsPerBlock;
    // Bonus muliplier for early Mars makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Mars mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetPjtrAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    constructor(
        MarsToken _mars,
        address _devAddress,
        address _pjtrAddress,
        uint256 _marsPerBlock,
        uint256 _startBlock,
        uint256 _startReleaseBlockNum,
        uint256 _releaseBlocks
    ) public {
        mars = _mars;
        devAddress = _devAddress;
        pjtrAddress = _pjtrAddress;
        marsPerBlock = _marsPerBlock;
        startBlock = _startBlock;
        lockedTokenVault = new LockedTokenVault(_mars, _startReleaseBlockNum, _releaseBlocks);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accMarsPerShare : 0
        }));
    }

    // Update the given pool's Mars allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending Mars on frontend.
    function pendingMars(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMarsPerShare = pool.accMarsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 marsReward = multiplier.mul(marsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accMarsPerShare = accMarsPerShare.add(marsReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accMarsPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        (uint256 accDev, uint256 accPjtr, uint256 accShare) = (6, 11, 70);
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 marsReward = multiplier.mul(marsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 devFee = marsReward.mul(accDev).div(accDev.add(accPjtr).add(accShare));
        uint256 pjtrFee = marsReward.mul(accPjtr).div(accDev.add(accPjtr).add(accShare));
        uint256 shareReward = marsReward.sub(devFee).sub(pjtrFee);
        mars.mint(devAddress, devFee);
        mars.mint(pjtrAddress, pjtrFee);
        mars.mint(address(this), shareReward);
        pool.accMarsPerShare = pool.accMarsPerShare.add(shareReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for Mars allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accMarsPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                uint256 pending30Percent = pending.mul(3).div(10);
                safeMarsTransfer(msg.sender, pending30Percent);
                
                lockedTokenVault.lock(address(msg.sender), pending.sub(pending30Percent));
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMarsPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accMarsPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeMarsTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMarsPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe Mars transfer function, just in case if rounding error causes pool to not have enough Mars.
    function safeMarsTransfer(address _to, uint256 _amount) internal {
        uint256 marsBal = mars.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > marsBal) {
            transferSuccess = mars.transfer(_to, marsBal);
        } else {
            transferSuccess = mars.transfer(_to, _amount);
        }
        require(transferSuccess, "safeMarsTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) public {
        require(msg.sender == devAddress, "dev: wut?");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setPjtrAddress(address _pjtrAddress) public {
        require(msg.sender == pjtrAddress, "setFeeAddress: FORBIDDEN");
        pjtrAddress = _pjtrAddress;
        emit SetPjtrAddress(msg.sender, _pjtrAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _marsPerBlock) public onlyOwner {
        massUpdatePools();
        marsPerBlock = _marsPerBlock;
        emit UpdateEmissionRate(msg.sender, _marsPerBlock);
    }
}
