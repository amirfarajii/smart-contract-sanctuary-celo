pragma solidity ^0.5.3;


contract Context {
    
    
    constructor () internal { }
    

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; 
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    
    function owner() public view returns (address) {
        return _owner;
    }

    
    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    
    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}

interface IFreezer {
  function isFrozen(address) external view returns (bool);
}

contract Freezer is Ownable, Initializable, IFreezer {
  mapping(address => bool) public isFrozen;

  function initialize() external initializer {
    _transferOwnership(msg.sender);
  }

  
  function freeze(address target) external onlyOwner {
    isFrozen[target] = true;
  }

  
  function unfreeze(address target) external onlyOwner {
    isFrozen[target] = false;
  }
}