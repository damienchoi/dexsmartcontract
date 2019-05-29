const CpublicDex = artifacts.require("./CpublicDex.sol");

module.exports = function(deployer){
    deployer.deploy(CpublicDex);
};