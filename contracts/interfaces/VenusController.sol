pragma solidity ^0.6.0;

interface VenusController {
    function isManager(address _mAddr) external view returns (bool);

    function getAddr(string calldata _name) external view returns (address);
}