var MarsToken = artifacts.require("MarsToken");
var MasterChef = artifacts.require("MasterChef");
var LockedTokenVault = artifacts.require("LockedTokenVault");

module.exports = function(deployer) {
  deployer.then(function() {
    return deployer.deploy(MarsToken);
  }).then(function() {
    return deployer.deploy(LockedTokenVault, MarsToken.address, 80, 100);
  }).then(function() {
    return deployer.deploy(MasterChef,
      MarsToken.address,
      LockedTokenVault.address,
      "0x226dAe0B18204C50CA4D959fE25fc2d47Bd5206d",
      "0x226dAe0B18204C50CA4D959fE25fc2d47Bd5206d",
      1,
      30,
      50
      );
  }).then(function() {
    return LockedTokenVault.deployed();
  }).then(function(instance) {
    instance.setMasterChef(MasterChef.address);
  });
}