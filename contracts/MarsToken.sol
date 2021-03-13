// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./libs/SafeBEP20.sol";
import "./libs/BEP20.sol";

// MarsToken with Governance.
contract MarsToken is BEP20('Mars', 'XMS') {
    using SafeMath for uint256;
    address public minter;
    
    constructor () public {
        uint256 initAmout = 13000000;
        _mint(msg.sender, initAmout.mul(10**decimals()));
        minter = msg.sender;
    }
    
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public {
        require(_to != address(0), "zero address");
        require(msg.sender == minter, "not minter");        
        _mint(_to, _amount);
    }

    function setMinter(address _minter) public onlyOwner {
        require(_minter != address(0), "zero address");
        minter = _minter;
    }
}