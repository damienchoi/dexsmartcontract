var CpublicDex = artifacts.require("./CpublicDex.sol");
var LSafeMath = artifacts.require("./LSafeMath.sol");

var SampleToken = artifacts.require("./test/SampleToken.sol");

module.exports = function(deployer, network, accounts) {
  
  if (network == "develop" || network == "development") {
    admin = accounts[1]
    feeAccount = accounts[2];
    feeMake = 0;
    feeTake = 3000000000000000;
    freeUntilDate= 0;
    deployer.deploy(SampleToken, 100000000*1000000000000000000 , "SampleToken", 18, "SMPL");    
  }
  
  if (network == "live" || network == "production" || network == "ropsten" || network == "private") {
    //TODO: set admin and fee accounts for production
    admin = ""
    feeAccount = "";
    feeMake = 0;
    feeTake = 0;
    freeUntilDate= 0;
  }

deployer.deploy(LSafeMath);
deployer.link(LSafeMath, CpublicDex);
deployer.deploy(CpublicDex, admin, feeAccount, feeMake, feeTake, freeUntilDate);
}

