// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;


interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}


interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

contract RegistryHelperUniswapV2 {

    struct PairState {
        uint reserve0;
        uint reserve1;
    }

    struct PairInfo {
        IUniswapV2Pair pair;
        address token0;
        address token1;
        PairState state;
    }

    function findPairs(
        IUniswapV2Factory factory,
        uint offset,
        uint limit
    ) external view returns (PairInfo[] memory result) {
        uint allPairsUpTo = factory.allPairsLength();

        if (allPairsUpTo > offset + limit) {
            allPairsUpTo = offset + limit;
        }

        // allocate a buffer array with the upper bound of the number of pairs returned
        result = new PairInfo[](allPairsUpTo - offset);
        for (uint i = offset; i < allPairsUpTo; i++) {
            IUniswapV2Pair uniPair = IUniswapV2Pair(factory.allPairs(i));
            address token0 = uniPair.token0();
            address token1 = uniPair.token1();
            (uint reserve0, uint reserve1, ) = uniPair.getReserves();
            result[i - offset] = PairInfo(uniPair, token0, token1, PairState(reserve0, reserve1));
        }
    }

    function refreshPairs(
        IUniswapV2Pair[] calldata pairs
    ) external view returns (PairState[] memory result) {
        result = new PairState[](pairs.length);
        for (uint i = 0; i < pairs.length; i++) {
            (uint reserve0, uint reserve1, ) = pairs[i].getReserves();
            result[i] = PairState(reserve0, reserve1);
        }
    }
}