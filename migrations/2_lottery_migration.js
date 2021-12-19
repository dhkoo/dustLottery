const DustLottery = artifacts.require("DustLottery");

let devAddr;
module.exports = function(deployer, network, accounts) {
    devAddr = accounts[0];
    deployer.deploy(DustLottery, devAddr);
};
