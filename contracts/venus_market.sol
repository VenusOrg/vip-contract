pragma solidity >=0.7.5;

import './interfaces/IUniswapV2Router01.sol';
import './interfaces/ISwapRouter.sol';
import './interfaces/VenusController.sol';
import './interfaces/IERC20.sol';
import './libraries/Address.sol';
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';
pragma abicoder v2;

contract VenusMarket {
    using Address for address;
    using SafeMath for *;
    VenusController public addrc;

    // 10/10000, 0.001
    uint256 public feeRate = 10;
    // router fee
    uint24 fee = 3000;

    // total trading amount in USD unit
    uint256 public tradingSum = 0;
    // order id start from 10000
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
        // Minimum
        uint256 minimum;

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
        uint256 _minimum,
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
        minimum : _minimum,
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
            order.stepTime += order.cycle * (block.timestamp - order.stepTime + order.cycle - 1) / order.cycle;
        }
    }

    function swapExactTokensForTokens(uint256 _oid) internal {
        address _feeTo = nameAddr("FEETO");
        require(_feeTo != address(0), "not set FEETO address");

        order_S memory order = orders[_oid];
        uint256 feeAmount = order.price.mul(feeRate).div(10000);
        uint256 realAmount = order.price.sub(feeAmount);

        // fee trans
        TransferHelper.safeTransferFrom(order.tokenIn, order.owner, _feeTo, feeAmount);
        // order trans
        ISwapRouter(nameAddr("ROUTER-V3")).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
        tokenIn : order.tokenIn,
        tokenOut : order.tokenOut,
        fee : fee,
        sender : order.owner,
        recipient : order.owner,
        deadline : order.endTime,
        amountIn : realAmount,
        amountOutMinimum : order.minimum,
        sqrtPriceLimitX96 : 0
        }));

        tradingSum += order.price;
        return;
    }

    function setFeeRate(uint256 _feeRate) onlyManager public {
        require(_feeRate > 0 && _feeRate < 10000, "fee rate must less than 100%");
        feeRate = _feeRate;
    }

    function getUserCount() public view returns (uint256){
        // in v1, one user address can only create one order, so the user count is the same as
        // order count, `10000` is the beginning number. in the future the logic maybe change
        return orderID - 10000;
    }

    function getTradingSum() public view returns (uint256){
        // in usd unit
        return tradingSum;
    }

    // "FEETO" address to receive fee
    // "ROUTER" uniswap router
    function nameAddr(string memory _name) public view returns (address){
        return addrc.getAddr(_name);
    }
    // set uniswap v3 router fee
    function setRouterFee(uint24 fee) onlyManager public {
        fee = fee;
    }

    modifier onlyManager(){
        require(addrc.isManager(msg.sender), "onlyManager");
        _;
    }
}