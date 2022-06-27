// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./TimeLockedWallet.sol";

contract TimeLockedWalletFactory {
    TimeLockedWallet[] public wallets;
    mapping(address => TimeLockedWallet[]) wals;

    event TimeLockedWalletCreated(address _creator, address _owner);

    function getWallets(address _user)
        public
        view
        returns (TimeLockedWallet[] memory)
    {
        return wals[_user];
    }

    function createTimeLockedWallet(
        address _owner,
        IERC20 _token,
        uint256 _unlockDate
    ) external {
        TimeLockedWallet wallet = new TimeLockedWallet(
            _owner,
            _token,
            _unlockDate
        );
        wallets.push(wallet);

        // Add wallet to sender's wallets.
        wals[msg.sender].push(wallet);

        // If owner is the same as sender then add wallet to sender's wallets too.
        if (msg.sender != _owner) {
            wals[_owner].push(wallet);
        }

        // Emit event.
        Created(wallet, msg.sender, _owner, block.timestamp, _unlockDate);
    }

    // Prevents accidental sending of ether to the factory
    receive() external payable {
        revert();
    }

    event Created(
        TimeLockedWallet wallet,
        address from,
        address to,
        uint256 createdAt,
        uint256 unlockDate
    );
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TimeLockedWallet {

    address public owner;
    address public creator;
    uint256 public unlockDate;
    uint256 public createdAt;
    IERC20 public token;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    constructor(
        address _owner,
        IERC20 _token,
        uint256 _unlockDate
        ) public {
            owner = _owner;
            creator = msg.sender;
            unlockDate = _unlockDate;
            createdAt = block.timestamp;
            token = _token;
        }



    // keep all the ether sent to this address

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // callable by owner only, after specified time, only for Tokens implementing ERC20
    function stake(uint256 _stake) onlyOwner public {
     require(block.timestamp >= unlockDate, "Valid timestamp required");
       //now send all the token balance
     require(_stake > 0, "You need to send some funds");
     token.transferFrom(owner, address(this), _stake);
     emit StackedTokens(token, msg.sender, _stake);
    }

    // callable by owner only, after specified time, only for Tokens implementing ERC20
    function withdraw() onlyOwner public {
       require(block.timestamp >= unlockDate, "Not ready for collection yet");
       //now send all the token balance
       uint256 tokenBalance = token.balanceOf(address(this));
       token.transfer(owner, tokenBalance);
       emit WithdrewTokens(token, msg.sender, tokenBalance);
    }


    function info() public view returns(address, address, uint256, uint256, uint256) {
        uint256 tokenBalance = token.balanceOf(address(this));
        return (creator, owner, unlockDate, createdAt, tokenBalance);
    }

    event Received(address from, uint256 amount);
    event Withdrew(address to, uint256 amount);
    event WithdrewTokens(IERC20 tokenContract, address to, uint256 amount);
    event StackedTokens(IERC20 tokenContract, address to, uint256 amount);

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}