// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import "@ensdomains/ens-contracts/contracts/root/Controllable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../metatx/RelayRecipient.sol";

interface NameResolver {
  function setName(bytes32 node, string memory name) external;
}

bytes32 constant lookup = 0x3031323334353637383961626364656600000000000000000000000000000000;

bytes32 constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

// namehash('addr.reverse')

contract ReverseRegistrar is Ownable, Controllable, RelayRecipient {
  ENS public immutable ens;
  NameResolver public immutable defaultResolver;

  event ReverseClaimed(address indexed addr, bytes32 indexed node);

  /**
   * @dev Constructor
   * @param _ens The address of the ENS registry.
   * @param _defaultResolver The address of the default reverse resolver.
   */
  constructor(ENS _ens, NameResolver _defaultResolver) {
    ens = _ens;
    defaultResolver = _defaultResolver;

    // Assign ownership of the reverse record to our deployer
    ReverseRegistrar oldRegistrar = ReverseRegistrar(
      _ens.owner(ADDR_REVERSE_NODE)
    );
    if (address(oldRegistrar) != address(0x0)) {
      oldRegistrar.claim(_msgSender());
    }
  }

  modifier authorised(address addr) {
    require(
      addr == _msgSender() ||
        controllers[_msgSender()] ||
        ens.isApprovedForAll(addr, _msgSender()) ||
        ownsContract(addr),
      "Caller is not a controller or authorised by address or the address itself"
    );
    _;
  }

  /**
   * @dev Transfers ownership of the reverse ENS record associated with the
   *      calling account.
   * @param owner The address to set as the owner of the reverse record in ENS.
   * @return The ENS node hash of the reverse record.
   */
  function claim(address owner) external returns (bytes32) {
    return _claimWithResolver(_msgSender(), owner, address(0x0));
  }

  /**
   * @dev Transfers ownership of the reverse ENS record associated with the
   *      calling account.
   * @param addr The reverse record to set
   * @param owner The address to set as the owner of the reverse record in ENS.
   * @return The ENS node hash of the reverse record.
   */
  function claimForAddr(address addr, address owner)
    external
    authorised(addr)
    returns (bytes32)
  {
    return _claimWithResolver(addr, owner, address(0x0));
  }

  /**
   * @dev Transfers ownership of the reverse ENS record associated with the
   *      calling account.
   * @param owner The address to set as the owner of the reverse record in ENS.
   * @param resolver The address of the resolver to set; 0 to leave unchanged.
   * @return The ENS node hash of the reverse record.
   */
  function claimWithResolver(address owner, address resolver)
    external
    returns (bytes32)
  {
    return _claimWithResolver(_msgSender(), owner, resolver);
  }

  /**
   * @dev Transfers ownership of the reverse ENS record specified with the
   *      address provided
   * @param addr The reverse record to set
   * @param owner The address to set as the owner of the reverse record in ENS.
   * @param resolver The address of the resolver to set; 0 to leave unchanged.
   * @return The ENS node hash of the reverse record.
   */
  function claimWithResolverForAddr(
    address addr,
    address owner,
    address resolver
  ) external authorised(addr) returns (bytes32) {
    return _claimWithResolver(addr, owner, resolver);
  }

  /**
   * @dev Sets the `name()` record for the reverse ENS record associated with
   * the calling account. First updates the resolver to the default reverse
   * resolver if necessary.
   * @param name The name to set for this address.
   * @return The ENS node hash of the reverse record.
   */
  function setName(string memory name) external returns (bytes32) {
    bytes32 node = _claimWithResolver(
      _msgSender(),
      address(this),
      address(defaultResolver)
    );
    defaultResolver.setName(node, name);
    return node;
  }

  /**
   * @dev Sets the `name()` record for the reverse ENS record associated with
   * the account provided. First updates the resolver to the default reverse
   * resolver if necessary.
   * Only callable by controllers and authorised users
   * @param addr The reverse record to set
   * @param owner The owner of the reverse node
   * @param name The name to set for this address.
   * @return The ENS node hash of the reverse record.
   */
  function setNameForAddr(
    address addr,
    address owner,
    string memory name
  ) external authorised(addr) returns (bytes32) {
    bytes32 node = _claimWithResolver(
      addr,
      address(this),
      address(defaultResolver)
    );
    defaultResolver.setName(node, name);
    ens.setSubnodeOwner(ADDR_REVERSE_NODE, sha3HexAddress(addr), owner);
    return node;
  }

  /**
   * @dev Returns the node hash for a given account's reverse records.
   * @param addr The address to hash
   * @return The ENS node hash.
   */
  function node(address addr) external pure returns (bytes32) {
    return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr)));
  }

  /**
   * @dev An optimised function to compute the sha3 of the lower-case
   *      hexadecimal representation of an Ethereum address.
   * @param addr The address to hash
   * @return ret The SHA3 hash of the lower-case hexadecimal encoding of the
   *         input address.
   */
  function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
    assembly {
      for {
        let i := 40
      } gt(i, 0) {

      } {
        i := sub(i, 1)
        mstore8(i, byte(and(addr, 0xf), lookup))
        addr := div(addr, 0x10)
        i := sub(i, 1)
        mstore8(i, byte(and(addr, 0xf), lookup))
        addr := div(addr, 0x10)
      }

      ret := keccak256(0, 40)
    }
  }

  /* Internal functions */

  function _claimWithResolver(
    address addr,
    address owner,
    address resolver
  ) internal returns (bytes32) {
    bytes32 label = sha3HexAddress(addr);
    bytes32 node = keccak256(abi.encodePacked(ADDR_REVERSE_NODE, label));
    address currentResolver = ens.resolver(node);
    bool shouldUpdateResolver = (resolver != address(0x0) &&
      resolver != currentResolver);
    address newResolver = shouldUpdateResolver ? resolver : currentResolver;

    ens.setSubnodeRecord(ADDR_REVERSE_NODE, label, owner, newResolver, 0);

    emit ReverseClaimed(addr, node);

    return node;
  }

  function ownsContract(address addr) internal view returns (bool) {
    try Ownable(addr).owner() returns (address owner) {
      return owner == _msgSender();
    } catch {
      return false;
    }
  }

  function _msgSender()
    internal
    view
    virtual
    override(Context, RelayRecipient)
    returns (address sender)
  {
    return super._msgSender();
  }

  function _msgData()
    internal
    view
    virtual
    override(Context, RelayRecipient)
    returns (bytes calldata)
  {
    return super._msgData();
  }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RelayRecipient is ERC2771Context, Ownable {
  mapping(address => bool) trustedForwarder;

  event SetTrustedForwarder(address indexed user, bool allowed);

  constructor() ERC2771Context(msg.sender) {}

  function isTrustedForwarder(address forwarder)
    public
    view
    override
    returns (bool)
  {
    return trustedForwarder[forwarder];
  }

  function _msgSender()
    internal
    view
    virtual
    override(ERC2771Context, Context)
    returns (address sender)
  {
    return super._msgSender();
  }

  function _msgData()
    internal
    view
    virtual
    override(ERC2771Context, Context)
    returns (bytes calldata)
  {
    return super._msgData();
  }

  function setTrustedForwarder(address _user, bool _allowed)
    external
    onlyOwner
  {
    trustedForwarder[_user] = _allowed;
    emit SetTrustedForwarder(_user, _allowed);
  }
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
// OpenZeppelin Contracts v4.4.1 (metatx/ERC2771Context.sol)

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Context variant with ERC2771 support.
 */
abstract contract ERC2771Context is Context {
    address private _trustedForwarder;

    constructor(address trustedForwarder) {
        _trustedForwarder = trustedForwarder;
    }

    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        return forwarder == _trustedForwarder;
    }

    function _msgSender() internal view virtual override returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender)) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
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


pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Controllable is Ownable {
    mapping(address => bool) public controllers;

    event ControllerChanged(address indexed controller, bool enabled);

    modifier onlyController {
        require(
            controllers[msg.sender],
            "Controllable: Caller is not a controller"
        );
        _;
    }

    function setController(address controller, bool enabled) public onlyOwner {
        controllers[controller] = enabled;
        emit ControllerChanged(controller, enabled);
    }
}


pragma solidity >=0.8.4;

interface ENS {

    // Logged when the owner of a node assigns a new owner to a subnode.
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);

    // Logged when the owner of a node transfers ownership to a new account.
    event Transfer(bytes32 indexed node, address owner);

    // Logged when the resolver for a node changes.
    event NewResolver(bytes32 indexed node, address resolver);

    // Logged when the TTL of a node changes
    event NewTTL(bytes32 indexed node, uint64 ttl);

    // Logged when an operator is added or removed.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external virtual;
    function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external virtual;
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external virtual returns(bytes32);
    function setResolver(bytes32 node, address resolver) external virtual;
    function setOwner(bytes32 node, address owner) external virtual;
    function setTTL(bytes32 node, uint64 ttl) external virtual;
    function setApprovalForAll(address operator, bool approved) external virtual;
    function owner(bytes32 node) external virtual view returns (address);
    function resolver(bytes32 node) external virtual view returns (address);
    function ttl(bytes32 node) external virtual view returns (uint64);
    function recordExists(bytes32 node) external virtual view returns (bool);
    function isApprovedForAll(address owner, address operator) external virtual view returns (bool);
}