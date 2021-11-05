pragma solidity ^0.6.0;

import './interfaces/IUniswapV2Router01.sol';
import './interfaces/VenusController.sol';
import './interfaces/IERC20.sol';
import './libraries/Address.sol';
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';

contract VenusMarket {
    using Address for address;
    using SafeMath for *;
    VenusController public addrc;

    // 10/10000, 0.001
    uint256 public feeRate = 10;

    uint256 public orderID = 10000;
    mapping(uint256 => order_S) public orders;
    mapping(address => uint256) public userToOrder;

    event CreateOrder(uint256 _oid, address user, uint256 _price, address _tokenIn, address _tokenOut, uint256 _cycle, uint256 _endTime);
    event CancelOrder(uint256 _oid);

    event SetBlackUser(address _user, bool _canSell);

    struct order_S {
        //user address
        address owner;
        // price wei
        uint256 price;

        // tokenIn
        address tokenIn;
        // tokenOut
        address tokenOut;

        // next start time
        uint256 stepTime;
        // end time
        uint256 endTime;
        // Fixed investment cycle
        uint256 cycle;
        // order status, true: useful, false: useless
        bool status;
    }

    constructor (VenusController _addrc) public {
        addrc = _addrc;
    }

    // add Fixed investment
    function createOrder(
        uint256 _price,
        address _tokenIn,
        address _tokenOut,
        uint256 _cycle,
        uint256 _endTime
    ) public {
        require(orders[userToOrder[msg.sender]].status == false, "user already has order");

        orderID++;
        orders[orderID] = order_S({
        owner : msg.sender,
        price : _price,
        tokenIn : _tokenIn,
        tokenOut : _tokenOut,
        stepTime : block.timestamp,
        endTime : _endTime,
        cycle : _cycle,
        status : true
        });
        userToOrder[msg.sender] = orderID;

        emit CreateOrder(orderID, msg.sender, _price, _tokenIn, _tokenOut, _cycle, _endTime);
    }

    // cancel Fixed investment
    function cancelOrder(uint256 _oid) public {
        require(orders[_oid].status, "order is useless");
        require(orders[_oid].owner == msg.sender, "order owner doesn't match");

        delete orders[_oid];
        emit CancelOrder(_oid);
    }

    function trigOrder(uint256 _oid) onlyManager public {
        require(orders[_oid].status, "order is useless");

        order_S storage order = orders[_oid];
        if (order.endTime < block.timestamp) {
            order.status = false;
        } else if (order.stepTime < block.timestamp) {
            // swap
            swapExactTokensForTokens(_oid);
            // update step time
            order.stepTime += order.cycle * (block.timestamp - order.stepTime) / order.cycle;
        }
    }

    function swapExactTokensForTokens(uint256 _oid) internal {
        address _feeTo = nameAddr("FEETO");
        require(_feeTo != address(0), "not set FEETO address");

        order_S memory order = orders[_oid];
        uint256 feeAmount = order.price.mul(feeRate).div(10000);
        uint256 realAmount = order.price.sub(feeAmount);
        address[] memory path = new address[](4);
        path[0] = address(0);
        path[1] = order.owner;
        path[2] = order.tokenIn;
        path[3] = order.tokenOut;

        // fee trans
        TransferHelper.safeTransferFrom(order.tokenIn, order.owner, _feeTo, feeAmount);
        // order trans
        IUniswapV2Router01(nameAddr("ROUTER")).swapExactTokensForTokens(
            realAmount,
            0, // amountOutMin: we can skip computing this number because the math is tested
            path,
            order.owner,
            block.timestamp + 60 // delay 60 seconds
        );

        return;
    }

    function setFeeRate(uint256 _feeRate) onlyManager public {
        require(_feeRate > 0 && _feeRate < 10000, "fee rate must less than 100%");
        feeRate = _feeRate;
    }

    // "FEETO" address to receive fee
    // "ROUTER" uniswap router
    function nameAddr(string memory _name) public view returns (address){
        return addrc.getAddr(_name);
    }

    modifier onlyManager(){
        require(addrc.isManager(msg.sender), "onlyManager");
        _;
    }
}