# adder

## installation

### macOS

pass

## notes

in case you need to build a json abi from a solidity contract, use [`solc-select`](https://github.com/crytic/solc-select) to manually switch between solidity compiler versions:
```
$ brew install solc-select
```
then build a json abi as such:
```
$ solc-select install 0.7.6
$ solc-select use 0.7.6
$ solc reference/uniswap/v3-periphery/contracts/SwapRouter.sol --abi > interfaces/ISwapRouter.json
```
