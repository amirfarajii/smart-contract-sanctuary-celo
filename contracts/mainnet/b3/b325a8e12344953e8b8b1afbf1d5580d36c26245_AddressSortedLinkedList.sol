pragma solidity ^0.5.3;


library Math {
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}

library SafeMath {
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        
        
        
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        
        require(b > 0, errorMessage);
        uint256 c = a / b;
        

        return c;
    }

    
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library LinkedList {
  using SafeMath for uint256;

  struct Element {
    bytes32 previousKey;
    bytes32 nextKey;
    bool exists;
  }

  struct List {
    bytes32 head;
    bytes32 tail;
    uint256 numElements;
    mapping(bytes32 => Element) elements;
  }

  
  function insert(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) public {
    require(key != bytes32(0), "Key must be defined");
    require(!contains(list, key), "Can't insert an existing element");
    require(
      previousKey != key && nextKey != key,
      "Key cannot be the same as previousKey or nextKey"
    );

    Element storage element = list.elements[key];
    element.exists = true;

    if (list.numElements == 0) {
      list.tail = key;
      list.head = key;
    } else {
      require(
        previousKey != bytes32(0) || nextKey != bytes32(0),
        "Either previousKey or nextKey must be defined"
      );

      element.previousKey = previousKey;
      element.nextKey = nextKey;

      if (previousKey != bytes32(0)) {
        require(
          contains(list, previousKey),
          "If previousKey is defined, it must exist in the list"
        );
        Element storage previousElement = list.elements[previousKey];
        require(previousElement.nextKey == nextKey, "previousKey must be adjacent to nextKey");
        previousElement.nextKey = key;
      } else {
        list.tail = key;
      }

      if (nextKey != bytes32(0)) {
        require(contains(list, nextKey), "If nextKey is defined, it must exist in the list");
        Element storage nextElement = list.elements[nextKey];
        require(nextElement.previousKey == previousKey, "previousKey must be adjacent to nextKey");
        nextElement.previousKey = key;
      } else {
        list.head = key;
      }
    }

    list.numElements = list.numElements.add(1);
  }

  
  function push(List storage list, bytes32 key) public {
    insert(list, key, bytes32(0), list.tail);
  }

  
  function remove(List storage list, bytes32 key) public {
    Element storage element = list.elements[key];
    require(key != bytes32(0) && contains(list, key), "key not in list");
    if (element.previousKey != bytes32(0)) {
      Element storage previousElement = list.elements[element.previousKey];
      previousElement.nextKey = element.nextKey;
    } else {
      list.tail = element.nextKey;
    }

    if (element.nextKey != bytes32(0)) {
      Element storage nextElement = list.elements[element.nextKey];
      nextElement.previousKey = element.previousKey;
    } else {
      list.head = element.previousKey;
    }

    delete list.elements[key];
    list.numElements = list.numElements.sub(1);
  }

  
  function update(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) public {
    require(
      key != bytes32(0) && key != previousKey && key != nextKey && contains(list, key),
      "key on in list"
    );
    remove(list, key);
    insert(list, key, previousKey, nextKey);
  }

  
  function contains(List storage list, bytes32 key) public view returns (bool) {
    return list.elements[key].exists;
  }

  
  function headN(List storage list, uint256 n) public view returns (bytes32[] memory) {
    require(n <= list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    bytes32 key = list.head;
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = key;
      key = list.elements[key].previousKey;
    }
    return keys;
  }

  
  function getKeys(List storage list) public view returns (bytes32[] memory) {
    return headN(list, list.numElements);
  }
}

library SortedLinkedList {
  using SafeMath for uint256;
  using LinkedList for LinkedList.List;

  struct List {
    LinkedList.List list;
    mapping(bytes32 => uint256) values;
  }

  
  function insert(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
    require(
      key != bytes32(0) && key != lesserKey && key != greaterKey && !contains(list, key),
      "invalid key"
    );
    require(
      (lesserKey != bytes32(0) || greaterKey != bytes32(0)) || list.list.numElements == 0,
      "greater and lesser key zero"
    );
    require(contains(list, lesserKey) || lesserKey == bytes32(0), "invalid lesser key");
    require(contains(list, greaterKey) || greaterKey == bytes32(0), "invalid greater key");
    (lesserKey, greaterKey) = getLesserAndGreater(list, value, lesserKey, greaterKey);
    list.list.insert(key, lesserKey, greaterKey);
    list.values[key] = value;
  }

  
  function remove(List storage list, bytes32 key) public {
    list.list.remove(key);
    list.values[key] = 0;
  }

  
  function update(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
    
    
    
    remove(list, key);
    insert(list, key, value, lesserKey, greaterKey);
  }

  
  function push(List storage list, bytes32 key) public {
    insert(list, key, 0, bytes32(0), list.list.tail);
  }

  
  function popN(List storage list, uint256 n) public returns (bytes32[] memory) {
    require(n <= list.list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      bytes32 key = list.list.head;
      keys[i] = key;
      remove(list, key);
    }
    return keys;
  }

  
  function contains(List storage list, bytes32 key) public view returns (bool) {
    return list.list.contains(key);
  }

  
  function getValue(List storage list, bytes32 key) public view returns (uint256) {
    return list.values[key];
  }

  
  function getElements(List storage list) public view returns (bytes32[] memory, uint256[] memory) {
    bytes32[] memory keys = getKeys(list);
    uint256[] memory values = new uint256[](keys.length);
    for (uint256 i = 0; i < keys.length; i = i.add(1)) {
      values[i] = list.values[keys[i]];
    }
    return (keys, values);
  }

  
  function getKeys(List storage list) public view returns (bytes32[] memory) {
    return list.list.getKeys();
  }

  
  function headN(List storage list, uint256 n) public view returns (bytes32[] memory) {
    return list.list.headN(n);
  }

  
  
  function getLesserAndGreater(
    List storage list,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) private view returns (bytes32, bytes32) {
    
    
    
    
    
    if (lesserKey == bytes32(0) && isValueBetween(list, value, lesserKey, list.list.tail)) {
      return (lesserKey, list.list.tail);
    } else if (
      greaterKey == bytes32(0) && isValueBetween(list, value, list.list.head, greaterKey)
    ) {
      return (list.list.head, greaterKey);
    } else if (
      lesserKey != bytes32(0) &&
      isValueBetween(list, value, lesserKey, list.list.elements[lesserKey].nextKey)
    ) {
      return (lesserKey, list.list.elements[lesserKey].nextKey);
    } else if (
      greaterKey != bytes32(0) &&
      isValueBetween(list, value, list.list.elements[greaterKey].previousKey, greaterKey)
    ) {
      return (list.list.elements[greaterKey].previousKey, greaterKey);
    } else {
      require(false, "get lesser and greater failure");
    }
  }

  
  function isValueBetween(List storage list, uint256 value, bytes32 lesserKey, bytes32 greaterKey)
    private
    view
    returns (bool)
  {
    bool isLesser = lesserKey == bytes32(0) || list.values[lesserKey] <= value;
    bool isGreater = greaterKey == bytes32(0) || list.values[greaterKey] >= value;
    return isLesser && isGreater;
  }
}

library AddressSortedLinkedList {
  using SafeMath for uint256;
  using SortedLinkedList for SortedLinkedList.List;

  function toBytes(address a) public pure returns (bytes32) {
    return bytes32(uint256(a) << 96);
  }

  function toAddress(bytes32 b) public pure returns (address) {
    return address(uint256(b) >> 96);
  }

  
  function insert(
    SortedLinkedList.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.insert(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  
  function remove(SortedLinkedList.List storage list, address key) public {
    list.remove(toBytes(key));
  }

  
  function update(
    SortedLinkedList.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.update(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  
  function contains(SortedLinkedList.List storage list, address key) public view returns (bool) {
    return list.contains(toBytes(key));
  }

  
  function getValue(SortedLinkedList.List storage list, address key) public view returns (uint256) {
    return list.getValue(toBytes(key));
  }

  
  function getElements(SortedLinkedList.List storage list)
    public
    view
    returns (address[] memory, uint256[] memory)
  {
    bytes32[] memory byteKeys = list.getKeys();
    address[] memory keys = new address[](byteKeys.length);
    uint256[] memory values = new uint256[](byteKeys.length);
    for (uint256 i = 0; i < byteKeys.length; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
      values[i] = list.values[byteKeys[i]];
    }
    return (keys, values);
  }

  
  function numElementsGreaterThan(
    SortedLinkedList.List storage list,
    uint256 threshold,
    uint256 max
  ) public view returns (uint256) {
    uint256 revisedMax = Math.min(max, list.list.numElements);
    bytes32 key = list.list.head;
    for (uint256 i = 0; i < revisedMax; i = i.add(1)) {
      if (list.getValue(key) < threshold) {
        return i;
      }
      key = list.list.elements[key].previousKey;
    }
    return revisedMax;
  }

  
  function headN(SortedLinkedList.List storage list, uint256 n)
    public
    view
    returns (address[] memory)
  {
    bytes32[] memory byteKeys = list.headN(n);
    address[] memory keys = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
    }
    return keys;
  }

  
  function getKeys(SortedLinkedList.List storage list) public view returns (address[] memory) {
    return headN(list, list.list.numElements);
  }
}