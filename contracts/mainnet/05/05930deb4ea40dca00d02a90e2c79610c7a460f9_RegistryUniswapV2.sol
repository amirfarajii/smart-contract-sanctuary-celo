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


contract RegistryUniswapV2 {

    struct Pair {
        IUniswapV2Pair pair;
        address token0;
        address token1;
        State state;
    }

    struct State {
        uint reserve0;
        uint reserve1;
    }

    function findPairs(
        IUniswapV2Factory factory,
        address[] calldata tokenWhitelist
    ) external view returns (Pair[] memory result) {
        Pair[] memory temp = new Pair[](factory.allPairsLength());
        uint length = 0;
        for (uint i = 0; i < factory.allPairsLength(); i++) {
            Pair memory p;
            p.pair = IUniswapV2Pair(factory.allPairs(i));
            p.token0 = p.pair.token0();
            p.token1 = p.pair.token1();

            // allow all pairs if the whitelist is empty
            bool isOnWhitelist = tokenWhitelist.length == 0;
            for (uint j = 0; j < tokenWhitelist.length; j++) {
                address w = tokenWhitelist[i];
                if (p.token0 == w || p.token1 == w) {
                    isOnWhitelist = true;
                    break;
                }
            }

            if (isOnWhitelist) {
                (p.state.reserve0, p.state.reserve1, ) = p.pair.getReserves();
                temp[length++] = p;
            }
        }

        result = new Pair[](length);
        for (uint i = 0; i < length; i++) {
            result[i] = temp[i];
        }
    }

    function refreshPairs(
        IUniswapV2Pair[] calldata pairs
    ) external view returns (State[] memory result) {
        result = new State[](pairs.length);
        for (uint i = 0; i < pairs.length; i++) {
            State memory s;
            (s.reserve0, s.reserve1, ) = pairs[i].getReserves();
            result[i] = s;
        }
    }
}