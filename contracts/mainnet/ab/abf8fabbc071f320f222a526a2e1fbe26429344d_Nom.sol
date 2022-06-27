// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IFeeModule.sol";
import "./interfaces/INom.sol";

// NOTE: Name == Nom in the documentation and is used interchangeably
contract Nom is INom, Ownable {
  using SafeMath for uint256;

  // @dev Each name's expiration timestamp
  mapping (bytes32 => uint256) override public expirations;
  // @dev The upgradeable fee module for purchasing Noms
  IFeeModule public feeModule;
  // @dev Each name's resolution
  mapping (bytes32 => address) private resolutions;
  // @dev Each name's owner
  mapping (bytes32 => address) private owners;

  // @dev emitted when a Nom's ownership has changed
  // @param name The name whose owner changed
  // @param previousOwner The previous owner
  // @param newOwner The new owner
  event NameOwnerChanged(bytes32 indexed name, address indexed previousOwner, address indexed newOwner);
  // @dev emitted when a Nom's resolution has changed
  // @param name The name whose resolution changed
  // @param previousResolution The previous resolution
  // @param newResolution The new resolution
  event NameResolutionChanged(bytes32 indexed name, address indexed previousResolution, address indexed newResolution);
  // @dev emitted when Nom's fee module changes
  // @param previousFeeModule Address of the previous feeModule
  // @param newFeeModule Address of the new feeModule
  event FeeModuleChanged(address indexed previousFeeModule, address indexed newFeeModule);

  constructor(IFeeModule _feeModule) {
    feeModule = _feeModule;
  }

  // @dev Reserve a Nom for a duration of time
  // @param name The name to reserve
  // @param durationToReserve The length of time in seconds to reserve this name
  function reserve(bytes32 name, uint256 durationToReserve) override external {
    require(isExpired(name), "Cannot reserve a name that has not expired");
    bool paid = feeModule.pay(_msgSender(), durationToReserve);
    require(paid, "Failed to pay for the name");

    uint256 currentTime = block.timestamp;
    address previousOwner = owners[name]; 
    owners[name] = _msgSender();
    expirations[name] = currentTime.add(durationToReserve);
    resolutions[name] = address(0);
    emit NameOwnerChanged(name, previousOwner, owners[name]);
  }

  // @dev Extend a Nom reservation
  // @param name The name to extend the reservation of
  // @param durationToExtend The length of time in seconds to extend
  function extend(bytes32 name, uint256 durationToExtend) override external {
    require(!isExpired(name), "Cannot extend the reservation of a name that has expired");
    require(_msgSender() == owners[name], "Caller is not the owner of this name");
    bool paid = feeModule.pay(_msgSender(), durationToExtend);
    require(paid, "Failed to pay for the name");

    uint256 currentExpiration = expirations[name];
    expirations[name] = currentExpiration.add(durationToExtend);
  }

  // @dev Retrieve the address that a Nom points to
  // @param name The name to resolve
  // @returns resolution The address that the Nom points to
  function resolve(bytes32 name) override external view returns (address resolution) {
    if (isExpired(name)) {
      return address(0);
    }

    return resolutions[name];
  }

  // @dev Change the resolution of a Nom
  // @param name The name to change the resolution of
  // @param newResolution The new address that should be pointed to
  function changeResolution(bytes32 name, address newResolution) override external {
    require(!isExpired(name), "Cannot change resolution of an expired name");
    require(_msgSender() == owners[name], "Caller is not the owner of this name");

    address previousResolution = resolutions[name];
    resolutions[name] = newResolution;
    emit NameResolutionChanged(name, previousResolution, resolutions[name]);
  }

  // @dev Retrieve the owner of a Nom
  // @param name The name to find the owner of
  // @returns owner The address that owns the Nom
  function nameOwner(bytes32 name) override external view returns (address owner) {
    if (isExpired(name)) {
      return address(0);
    }

    return owners[name];
  }

  // @dev Change the owner of a Nom
  // @param name The name to change the owner of
  // @param newOwner The new owner
  function changeNameOwner(bytes32 name, address newOwner) override external {
    require(!isExpired(name), "Cannot change owner of an expired name");
    require(_msgSender() == owners[name], "Caller is not the owner of this name");

    address previousOwner = owners[name];
    owners[name] = newOwner;
    emit NameOwnerChanged(name, previousOwner, owners[name]);
  }

  // @dev Change the owner of a Nom
  // @param name The name to change the owner of
  // @param newOwner The new owner
  function setFeeModule(IFeeModule newFeeModule) onlyOwner external {
    IFeeModule previousFeeModule = feeModule;
    feeModule = newFeeModule;
    emit FeeModuleChanged(address(previousFeeModule), address(feeModule));
  }

  // @dev Check whether a Nom is expired
  // @param name The name to check the expiration of
  // @param expired Flag indicating whether this Nom is expired
  function isExpired(bytes32 name) override public view returns (bool expired) {
    return block.timestamp > expirations[name];
  }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// NOTE: Name == Nom in the documentation and is used interchangeably
interface INom {
  // @dev Reserve a Nom for a duration of time
  // @param name The name to reserve
  // @param durationToReserve The length of time in seconds to reserve this name
  function reserve(bytes32 name, uint256 durationToReserve) external;

  // @dev Extend a Nom reservation
  // @param name The name to extend the reservation of
  // @param durationToExtend The length of time in seconds to extend
  function extend(bytes32 name, uint256 durationToExtend) external;

  // @dev Retrieve the address that a Nom points to
  // @param name The name to resolve
  // @returns resolution The address that the Nom points to
  function resolve(bytes32 name) external view returns (address resolution);

  // @dev Get the expiration timestamp of a Nom 
  // @param name The name to get the expiration of
  // @returns expiration Time in seconds from epoch that this Nom expires
  function expirations(bytes32 name) external view returns (uint256 expiration);

  // @dev Change the resolution of a Nom
  // @param name The name to change the resolution of
  // @param newResolution The new address that should be pointed to
  function changeResolution(bytes32 name, address newResolution) external;

  // @dev Retrieve the owner of a Nom
  // @param name The name to find the owner of
  // @returns owner The address that owns the Nom
  function nameOwner(bytes32 name) external view returns (address owner);

  // @dev Change the owner of a Nom
  // @param name The name to change the owner of
  // @param newOwner The new owner
  function changeNameOwner(bytes32 name, address newOwner) external;

  // @dev Check whether a Nom is expired
  // @param name The name to check the expiration of
  // @param expired Flag indicating whether this Nom is expired
  function isExpired(bytes32 name) external view returns (bool expired);
}



// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeModule {
  // @dev Make a payment for a reservation
  // @param payer The address to pay for the reservation
  // @param durationToReserve The length of time in seconds to reserve
  // @returns success Whether the payment was sucessful
  function pay(address payer, uint256 durationToReserve) external returns (bool success);
}



// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
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
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


// SPDX-License-Identifier: MIT

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
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
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
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}