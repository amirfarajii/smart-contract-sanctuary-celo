//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@ubeswap/governance/contracts/voting/VotingToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMintableToken.sol";

contract SPACTToken is IMintableToken, VotingToken, Ownable {
    /**
     * @notice Construct a Staking PACT Token
     */
    constructor() VotingToken("StakingPactToken", "SPACT", 18) {}

    /**
     * @notice Mint new voting power
     * @param _account     The address of the destination account
     * @param _amount      The amount of voting power to be minted
     */
    function mint(address _account, uint96 _amount) external override onlyOwner {
        _mintVotes(_account, _amount);
    }

    /**
     * @notice Burn voting power
     * @param _account     The address of the source account
     * @param _amount      The amount of voting power to be burned
     */
    function burn(address _account, uint96 _amount) external override onlyOwner {
        _burnVotes(_account, _amount);
    }
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface IMintableToken {
    function mint(address _account, uint96 _amount) external;
    function burn(address _account, uint96 _amount) external;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../interfaces/INonTransferrableToken.sol";
import "./VotingPower.sol";

/**
 * A non-transferrable token that can vote.
 */
contract VotingToken is INonTransferrableToken, VotingPower {
    string private _symbol;
    uint8 private immutable _decimals;

    /**
     * @dev Sets the values for `name`, `symbol`, and `decimals`. All three of
     * these values are immutable: they can only be set once during
     * construction.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) VotingPower(name_) {
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name()
        public
        view
        override(INonTransferrableToken, VotingPower)
        returns (string memory)
    {
        return VotingPower.name();
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return totalVotingPower();
    }

    function balanceOf(address _account)
        public
        view
        override
        returns (uint256)
    {
        return votingPower(_account);
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../interfaces/IHasVotes.sol";
import "../interfaces/IVotingDelegates.sol";

/**
 * Power to vote. Heavily based on Uni.
 */
contract VotingPower is IHasVotes, IVotingDelegates {
    // Name of the token. This cannot be changed after creating the token.
    string private _name;

    // Total amount of voting power available.
    uint96 private totalVotingPowerSupply;

    constructor(string memory name_) {
        _name = name_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @notice Mint new voting power
     * @param dst The address of the destination account
     * @param amount The amount of voting power to be minted
     */
    function _mintVotes(address dst, uint96 amount) internal {
        require(dst != address(0), "VotingPower::_mintVotes: cannot mint to the zero address");

        // transfer the amount to the recipient
        balances[dst] = add96(balances[dst], amount, "VotingPower::_mintVotes: mint amount overflows");
        totalVotingPowerSupply = add96(
            totalVotingPowerSupply, amount, "VotingPower::_mintVotes: total supply overflows"
        );
        emit Transfer(address(0), dst, amount);

        // move delegates
        _moveDelegates(address(0), delegates[dst], amount);
    }

    /**
     * @notice Burn voting power
     * @param src The address of the source account
     * @param amount The amount of voting power to be burned
     */
    function _burnVotes(address src, uint96 amount) internal {
        require(src != address(0), "VotingPower::_burnVotes: cannot burn from the zero address");

        // transfer the amount to the recipient
        balances[src] = sub96(balances[src], amount, "VotingPower::_burnVotes: burn amount underflows");
        totalVotingPowerSupply = sub96(
            totalVotingPowerSupply, amount, "VotingPower::_burnVotes: total supply underflows"
        );
        emit Transfer(src, address(0), amount);

        // move delegates
        _moveDelegates(delegates[src], address(0), amount);
    }

    /**
     * @notice Get the amount of voting power of an account
     * @param account The address of the account to get the balance of
     * @return The amount of voting power held
     */
    function votingPower(address account) public view override returns (uint96) {
        return balances[account];
    }

    function totalVotingPower() public view override returns (uint96) {
        return totalVotingPowerSupply;
    }

    ////////////////////////////////
    //
    // The below code is copied from ../uniswap-governance/contracts/Uni.sol.
    // Changes are marked with "XXX".
    //
    ////////////////////////////////

    // XXX: deleted name, symbol, decimals, totalSupply, minter, mintingAllowedAfter,
    // minimumTimeBetweenMints, mintCap, allowances

    // Official record of token balances for each account
    // XXX: internal => private visibility
    mapping (address => uint96) private balances;

    /// @notice A record of each accounts delegate
    mapping (address => address) public override delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // XXX: deleted PERMIT_TYPEHASH

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    // XXX: deleted MinterChanged

    // XXX: deleted DelegateChanged, DelegateVotesChanged, Transfer and moved them to IVotingPower

    // XXX: deleted Approval

    // XXX: deleted constructor, setMinter, mint, allowance, approve, permit, balanceOf

    // XXX: deleted transfer, transferFrom

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public override {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public override {
        // XXX_CHANGED: name => _name
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(_name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Uni::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "Uni::delegateBySig: invalid nonce");
        // XXX: added linter disable
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= expiry, "Uni::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view override returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view override returns (uint96) {
        require(blockNumber < block.number, "Uni::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _transferTokens(address src, address dst, uint96 amount) internal {
        require(src != address(0), "Uni::_transferTokens: cannot transfer from the zero address");
        require(dst != address(0), "Uni::_transferTokens: cannot transfer to the zero address");

        balances[src] = sub96(balances[src], amount, "Uni::_transferTokens: transfer amount exceeds balance");
        balances[dst] = add96(balances[dst], amount, "Uni::_transferTokens: transfer amount overflows");
        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    function _moveDelegates(address srcRep, address dstRep, uint96 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = sub96(srcRepOld, amount, "Uni::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, "Uni::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes) internal {
      uint32 blockNumber = safe32(block.number, "Uni::_writeCheckpoint: block number exceeds 32 bits");

      if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      } else {
          checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function getChainId() internal view returns (uint) {
        uint256 chainId;
        // XXX: added linter disable
        // solhint-disable-next-line no-inline-assembly
        assembly { chainId := chainid() }
        return chainId;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * Interface for a contract that keeps track of voting delegates.
 */
interface IVotingDelegates {
    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /// @notice An event emitted when an account's voting power is transferred.
    // - If `from` is `address(0)`, power was minted.
    // - If `to` is `address(0)`, power was burned.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Name of the contract.
    // Required for signing.
    function name() external view returns (string memory);

    /// @notice A record of each accounts delegate
    function delegates(address delegatee) external view returns (address);

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external;

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Get the amount of voting power of an account
     * @param account The address of the account to get the balance of
     * @return The amount of voting power held
     */
    function votingPower(address account) external view returns (uint96);

    /// @notice Total voting power in existence.
    function totalVotingPower() external view returns (uint96);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * A token that cannot be transferred.
 */
interface INonTransferrableToken {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    // Views
    function totalSupply() external view returns (uint256);

    function balanceOf(address _account) external view returns (uint256);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * Reads the votes that an account has.
 */
interface IHasVotes {
    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96);

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint96);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}