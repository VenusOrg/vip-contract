pragma solidity ^0.6.0;

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {codehash := extcodehash(account)}
        return (codehash != 0x0 && codehash != accountHash);
    }

    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }
}

library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }


    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }


    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }


    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }


    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }


    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }


    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

//SPDX-License-Identifier: UNLICENSED
// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }
}

interface VenusController {
    function isManager(address _mAddr) external view returns (bool);

    function getAddr(string calldata _name) external view returns (address);
}

contract VenusMarket {
    using Address for address;
    using SafeMath for *;
    VenusController public addrc;

    uint256 public feeRate;

    uint256 orderID = 10000;
    mapping(uint256 => order_S) public orders;
    uint256[] orderList;
    mapping(address => uint256) public userToOrder;

    event CreateOrder(uint256 _oid, address user, uint256 _price, address _receiveToken, uint256 _cycle, uint256 _endTime);
    event CancelOrder(uint256 _oid);

    // black list
    mapping(address => bool) public blackUser;

    event SetBlackUser(address _user, bool _canSell);

    // mix cycle, one day
    uint256 public minCycle = 86400;

    struct order_S {
        //user address
        address user;
        // order id
        uint256 oid;
        // price wei
        uint256 price;
        // coin type
        address reciveToken;

        // next start time
        uint256 stepTime;
        // end time
        uint256 endTime;
        // Fixed investment cycle
        uint256 cycle;
    }

    constructor (VenusController _addrc) public {
        addrc = _addrc;
    }

    // add Fixed investment
    function createOrder(
        uint256 _price,
        address _receiveToken,
        uint256 _cycle,
        uint256 _endTime
    ) allowed public {
        require(userToOrder[msg.sender] != 0, "user already has order");
        require(Address.isContract(_receiveToken), "not contract Addr");
        orderID++;
        orderList.push(orderID);
        orders[orderID] = order_S({
        user : msg.sender,
        oid : orderID,
        price : _price,
        reciveToken : _receiveToken,
        stepTime : block.timestamp,
        endTime : _endTime,
        cycle : _cycle
        });

        if (_cycle < minCycle) {
            minCycle = _cycle;
        }

        emit CreateOrder(orderID, msg.sender, _price, _receiveToken, _cycle, _endTime);
    }

    // cancel Fixed investment
    function cancelOrder(uint256 _oid) allowed public {
        deleteOrder(_oid);
    }

    function deleteOrder(uint256 _oid) internal {
        require(_oid < orderID, "order id out of range");
        require(userToOrder[msg.sender] != 0, "order is not exist");

        // delete order id
        uint256 latestIdx = orderList.length - 1;
        userToOrder[msg.sender] = 0;
        uint256 tmp = orderList[latestIdx];
        orderList[latestIdx] = orderList[_oid];
        orderList[_oid] = tmp;
        orderList.pop();

        emit CancelOrder(_oid);
    }

    function trigTask() onlyManager public {
        uint256 len = orderList.length;
        for (uint256 i = 0; i < len; i++) {
            order_S memory order = orders[orderList[i]];
            // delete useless
            if ((order.stepTime + order.cycle >= order.endTime)
                || !canPay(order.user, order.reciveToken, order.price)) {
                deleteOrder(order.oid);
            }
            // try Fixed investment
            if (order.stepTime + order.cycle >= block.timestamp) {
                // TODO Fixed investment operation
                // salePay();
                order.stepTime += order.cycle;
                orders[orderList[i]] = order;
            }
        }
    }

    function canPay(address _owner, address _receiveToken, uint256 _price) internal returns (bool){
        // TODO check approved
        // TODO check balance
        return false;
    }

    // TODO fill content
    function salePay() internal {

    }

    function setFeeRate(uint256 _feeRate) onlyManager public {
        feeRate = _feeRate;
    }

    function setBlackUser(address _user, bool _canUse) onlyManager public {
        blackUser[_user] = _canUse;
        emit SetBlackUser(_user, _canUse);
    }

    function nameAddr(string memory _name) public view returns (address){
        return addrc.getAddr(_name);
    }

    modifier allowed(){
        require(blackUser[msg.sender], "This account is not allowed");
        _;
    }

    modifier onlyManager(){
        require(addrc.isManager(msg.sender), "onlyManager");
        _;
    }
}