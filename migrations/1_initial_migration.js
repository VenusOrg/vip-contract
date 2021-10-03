const controller = artifacts.require("addressController");

module.exports = function (deployer) {
    deployer.deploy(controller);
};
