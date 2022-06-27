// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interface/ICreditFeeManager.sol";
import "./interface/ICreditManager.sol";
import "./interface/ICreditRoles.sol";
import "./interface/ICreditRequest.sol";
import "./interface/ICreditPool.sol";

contract CreditFeeManager is ICreditFeeManager, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== CONSTANTS ========== */

    uint32 private constant MAX_PPM = 1000000;

    /* ========== STATE VARIABLES ========== */

    IERC20Upgradeable public collateralToken;
    ICreditManager public creditManager;
    ICreditRoles public creditRoles;
    ICreditRequest public creditRequest;
    uint256 public underwriterFeePercent;
    mapping(address => mapping(address => uint256)) accruedFees;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _creditManager,
        address _creditRoles,
        address _creditRequest,
        uint256 _underwriterPercent
    ) external virtual initializer {
        __Ownable_init();
        creditManager = ICreditManager(_creditManager);
        collateralToken = IERC20Upgradeable(creditManager.getCollateralToken());
        creditRoles = ICreditRoles(_creditRoles);
        creditRequest = ICreditRequest(_creditRequest);
        require(
            _underwriterPercent <= MAX_PPM,
            "CreditFeeManager: underwriter percent must be less than 100%"
        );
        underwriterFeePercent = _underwriterPercent;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function collectFees(
        address _network,
        address _networkMember,
        uint256 _transactionAmount
    ) external override onlyNetwork {
        uint256 creditFee = creditManager.calculatePercentInCollateral(
            _network,
            underwriterFeePercent,
            _transactionAmount
        );
        collateralToken.safeTransferFrom(_networkMember, address(this), creditFee);
        creditRequest.verifyCreditLineExpiration(_network, _networkMember, _transactionAmount);
        accruedFees[_network][_networkMember] += creditFee;
        emit FeesCollected(_network, _networkMember, creditFee);
    }

    function distributeFees(address _network, address[] memory _networkMembers) external {
        for (uint256 i = 0; i < _networkMembers.length; i++) {
            uint256 fees = accruedFees[_network][_networkMembers[i]];
            accruedFees[_network][_networkMembers[i]] = 0;
            address underwriter = creditManager.getCreditLineUnderwriter(
                _network,
                _networkMembers[i]
            );
            if (underwriter == address(0)) {
                return;
            }
            address pool = creditManager.getCreditLine(_network, _networkMembers[i]).creditPool;
            uint256 leftoverFee = stakeNeededCollateralInPool(
                _network,
                _networkMembers[i],
                pool,
                underwriter,
                fees
            );
            if (leftoverFee > 0) {
                ICreditPool(pool).notifyRewardAmount(address(collateralToken), leftoverFee);
                emit PoolRewardsUpdated(pool, leftoverFee);
            }
        }
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyCreditOperator {
        IERC20Upgradeable(tokenAddress).safeTransfer(msg.sender, tokenAmount);
    }

    function updateUnderwriterFeePercent(uint256 _feePercent) external onlyCreditOperator {
        require(_feePercent <= MAX_PPM, "CreditFeeManager: invalid fee percent");
        underwriterFeePercent = _feePercent;
    }

    /* ========== VIEWS ========== */

    function calculateFees(address _network, uint256 _transactionAmount)
        external
        view
        override
        returns (uint256 creditFee)
    {
        creditFee = creditManager.calculatePercentInCollateral(
            _network,
            underwriterFeePercent,
            _transactionAmount
        );
    }

    function getCollateralToken() external view override returns (address) {
        return address(collateralToken);
    }

    function getUnderwriterPoolStakePercent(address _network, address _networkMember)
        public
        returns (uint256)
    {
        address pool = creditManager.getCreditLine(_network, _networkMember).creditPool;
        address underwriter = creditManager.getCreditLineUnderwriter(_network, _networkMember);
        uint256 underwriterCollateral = ICreditPool(pool).balanceOf(underwriter);
        uint256 totalCollateral = ICreditPool(pool).totalSupply();
        return (totalCollateral / underwriterCollateral) * MAX_PPM;
    }

    function getAccruedFees(address[] memory _members, address _network)
        external
        view
        returns (uint256 totalFees)
    {
        for (uint256 i = 0; i < _members.length; i++) {
            totalFees += accruedFees[_network][_members[i]];
        }
    }

    /* ========== PRIVATE ========== */

    function stakeNeededCollateralInPool(
        address _network,
        address _networkMember,
        address pool,
        address underwriter,
        uint256 creditFee
    ) private returns (uint256) {
        if (creditManager.isPoolValidLTV(_network, pool)) return creditFee;
        uint256 neededCollateral = creditManager.getNeededCollateral(_network, _networkMember);
        if (neededCollateral == 0) {
            return creditFee;
        }
        if (neededCollateral > creditFee) {
            collateralToken.safeTransfer(underwriter, creditFee);
            ICreditPool(pool).stakeFor(underwriter, creditFee);
            emit UnderwriterRewardsStaked(underwriter, creditFee);
            creditFee = 0;
        } else {
            collateralToken.safeTransfer(underwriter, neededCollateral);
            ICreditPool(pool).stakeFor(underwriter, neededCollateral);
            emit UnderwriterRewardsStaked(underwriter, neededCollateral);
            creditFee -= neededCollateral;
        }
        return creditFee;
    }

    function approveCreditPool(address _pool) external onlyCreditOperator {
        collateralToken.approve(
            _pool,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
    }

    /* ========== MODIFIERS ========== */

    modifier onlyCreditOperator() {
        require(
            creditRoles.isCreditOperator(msg.sender),
            "CreditFeeManager: Caller is not credit operator"
        );
        _;
    }

    modifier onlyNetwork() {
        require(creditRoles.isNetwork(msg.sender), "CreditFeeManager: Caller is not a network");
        _;
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditRoles {
    event UnderwriterAdded(address underwriter);

    event UnderwriterRemoved(address underwriter);

    function grantUnderwriter(address _underwriter) external;

    function revokeUnderwriter(address _underwriter) external;

    function grantNetwork(address _network) external;

    function revokeNetwork(address _network) external;

    function isUnderwriter(address _underwriter) external view returns (bool);

    function isNetwork(address _network) external view returns (bool);

    function isCreditOperator(address _operator) external view returns (bool);

    function isRequestOperator(address _operator) external returns (bool);

    function grantRequestOperator(address _requestOperator) external;

    function revokeRequestOperator(address _requestOperator) external;
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditRequest {
    struct CreditRequest {
        bool approved;
        bool unstaking;
        uint256 creditLimit;
    }

    event CreditRequestCreated(
        address network,
        address networkMember,
        address requester,
        uint256 creditLimit,
        bool approved
    );

    event CreditRequestUpdated(
        address network,
        address networkMember,
        uint256 creditLimit,
        bool approved
    );

    event CreditRequestRemoved(address network, address networkMember);

    event UnstakeRequestCreated(address network, address networkMember);

    function createRequest(
        address _network,
        address _networkMember,
        uint256 _creditLimit
    ) external;

    function approveRequest(address _network, address _networkMember) external;

    function updateRequestLimit(
        address _network,
        address _networkMember,
        uint256 _creditLimit,
        bool _approved
    ) external;

    function deleteRequest(address _network, address _networkMember) external;

    function verifyCreditLineExpiration(
        address _network,
        address _networkMember,
        uint256 _transactionValue
    ) external;
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditPool {
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external;

    function totalSupply() external view returns (uint256);

    function stakeFor(address _staker, uint256 _amount) external;

    function balanceOf(address _account) external view returns (uint256);

    function reduceTotalCredit(uint256 _amountToAdd) external;

    function increaseTotalCredit(uint256 _amountToRemove) external;

    function getUnderwriter() external view returns (address);

    function getTotalCredit() external view returns (uint256);
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditManager {
    struct CreditLine {
        address creditPool;
        uint256 issueDate;
        uint256 creditLimit;
    }

    event CreditLineCreated(
        address network,
        address networkMember,
        address pool,
        uint256 creditLimit,
        uint256 timestamp
    );

    event CreditPoolAdded(address pool, address underwriter);

    event CreditLineLimitUpdated(address network, address networkMember, uint256 creditLimit);

    event CreditLinePoolUpdated(address network, address networkMember, address pool);

    event CreditLineRemoved(address network, address networkMember);

    event CreditLineRenewed(address network, address networkMember, uint256 timestamp);

    function createCreditLine(
        address _networkMember,
        address _pool,
        uint256 _creditLimit,
        address _network
    ) external;

    function getCollateralToken() external returns (address);

    function getMinLTV() external returns (uint256);

    function getCreditLine(address _network, address _networkMember)
        external
        returns (CreditLine memory);

    function getCreditLineUnderwriter(address _network, address _networkMember)
        external
        returns (address);

    function isPoolValidLTV(address _network, address _networkMember) external returns (bool);

    function isCreditLineExpired(address _network, address _networkMember) external returns (bool);

    function swapCreditLinePool(
        address _network,
        address _networkMember,
        address _pool
    ) external;

    function extendCreditLine(
        address _network,
        address _networkMember,
        uint256 _creditLimit
    ) external;

    function convertNetworkToCollateral(address _network, uint256 _amount)
        external
        returns (uint256);

    function renewCreditLine(address _network, address _networkMember) external;

    function getNeededCollateral(address _network, address _networkMember)
        external
        returns (uint256);

    function calculatePercentInCollateral(
        address _networkToken,
        uint256 _percent,
        uint256 _amount
    ) external view returns (uint256);
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditFeeManager {
    event FeesCollected(address network, address member, uint256 totalFee);

    event PoolRewardsUpdated(address underwriter, uint256 totalRewards);

    event UnderwriterRewardsStaked(address underwriter, uint256 totalStaked);

    function collectFees(
        address _network,
        address _networkMember,
        uint256 _transactionValue
    ) external;

    function getCollateralToken() external returns (address);

    function calculateFees(address _network, uint256 _transactionAmount)
        external
        view
        returns (uint256 creditFee);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;

import "../IERC20Upgradeable.sol";
import "../../../utils/AddressUpgradeable.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(
        IERC20Upgradeable token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20Upgradeable token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

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
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

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


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.0;

import "../../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To initialize the implementation contract, you can either invoke the
 * initializer manually, or you can include a constructor to automatically mark it as initialized when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() initializer {}
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        // If the contract is initializing we ignore whether _initialized is set in order to support multiple
        // inheritance patterns, but we only do this in the context of a constructor, because in other contexts the
        // contract may have been reentered.
        require(_initializing ? _isConstructor() : !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} modifier, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}