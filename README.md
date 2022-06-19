# vip-contract
solidity contract for vip protocol

# user address operation
* User approve venus_market contract in tokenIn erc20 contract
```text
tokenIn.approve(venus_market, value)
```

* User approve swapRouter contract in tokenIn erc20 contract
```text
tokenIn.approve(swapRouter, value)
```

* create order
```bash
createOrder(
 _price,    # the tokenIn balance how much you want transfer
 _minimum,  # The minimum expected value
 _tokenIn,  # tokenIn erc20 token
 _tokenOut, # tokenOut erc20 token
 _cycle,    # To be cast surely cycle
 _endTime,  # The end time
)
```