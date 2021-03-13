const {
  BN,           // Big Number support
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');

const MarsToken = artifacts.require("MarsToken");
const MasterChef = artifacts.require("MasterChef");
const LockedTokenVault = artifacts.require("LockedTokenVault");

contract("Test", (accounts) => {
    before(async () => {

    });
    it("approve mars token", async () => {
        const marsToken = await MarsToken.deployed();
        const masterChef = await MasterChef.deployed();
        const lockedTokenVault = await LockedTokenVault.deployed();
        await marsToken.approve(masterChef.address, new BN("100000000000000000000000"));

        let balance = await marsToken.balanceOf("0x226dAe0B18204C50CA4D959fE25fc2d47Bd5206d");
        console.log(balance.toString());
        let allownce = await marsToken.allowance("0x226dAe0B18204C50CA4D959fE25fc2d47Bd5206d", masterChef.address);
        console.log(allownce.toString());

        await masterChef.addPool(20, marsToken.address, true);
        await masterChef.addPool(5, "0x43A3be7B27F05644EbDB6F5433DF73e9dCe3C668", true);
        await masterChef.deposit(0, new BN("10000000000000000000000"));
        const userInfo = await masterChef.userInfo(0, "0x226dAe0B18204C50CA4D959fE25fc2d47Bd5206d");
        console.log(userInfo.amount.toString() + "/" + userInfo.rewardDebt.toString());

        balance = await marsToken.balanceOf("0x226dAe0B18204C50CA4D959fE25fc2d47Bd5206d");
        console.log(balance.toString());
        allownce = await marsToken.allowance("0x226dAe0B18204C50CA4D959fE25fc2d47Bd5206d", masterChef.address);
        console.log(allownce.toString());
    });
});