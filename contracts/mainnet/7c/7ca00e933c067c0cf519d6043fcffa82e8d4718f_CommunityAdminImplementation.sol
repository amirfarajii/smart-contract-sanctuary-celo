// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/ICommunity.sol";
import "./interfaces/CommunityAdminStorageV1.sol";
import "./Community.sol";
import "../token/interfaces/ITreasury.sol";

/**
 * @notice Welcome to CommunityAdmin, the main contract. This is an
 * administrative (for now) contract where the admins have control
 * over the list of communities. Being only able to add and
 * remove communities
 */
contract CommunityAdminImplementation is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    CommunityAdminStorageV1
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant DEFAULT_AMOUNT = 5e16;
    uint256 private constant TREASURY_SAFETY_FACTOR = 10;

    /**
     * @notice Triggered when a community has been added
     *
     * @param communityAddress  Address of the community that has been added
     * @param managers          Addresses of the initial managers
     * @param claimAmount       Value of the claimAmount
     * @param maxClaim          Value of the maxClaim
     * @param decreaseStep      Value of the decreaseStep
     * @param baseInterval      Value of the baseInterval
     * @param incrementInterval Value of the incrementInterval
     * @param minTranche        Value of the minTranche
     * @param maxTranche        Value of the maxTranche
     *
     * For further information regarding each parameter, see
     * *Community* smart contract initialize method.
     */
    event CommunityAdded(
        address indexed communityAddress,
        address[] managers,
        uint256 claimAmount,
        uint256 maxClaim,
        uint256 decreaseStep,
        uint256 baseInterval,
        uint256 incrementInterval,
        uint256 minTranche,
        uint256 maxTranche
    );

    /**
     * @notice Triggered when a community has been removed
     *
     * @param communityAddress  Address of the community that has been removed
     */
    event CommunityRemoved(address indexed communityAddress);

    /**
     * @notice Triggered when a community has been migrated
     *
     * @param managers                 Addresses of the new community's initial managers
     * @param communityAddress         New community address
     * @param previousCommunityAddress Old community address
     */
    event CommunityMigrated(
        address[] managers,
        address indexed communityAddress,
        address indexed previousCommunityAddress
    );

    /**
     * @notice Triggered when the treasury address has been updated
     *
     * @param oldTreasury             Old treasury address
     * @param newTreasury             New treasury address
     */
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /**
     * @notice Triggered when the communityTemplate address has been updated
     *
     * @param oldCommunityTemplate    Old communityTemplate address
     * @param newCommunityTemplate    New communityTemplate address
     */
    event CommunityTemplateUpdated(
        address indexed oldCommunityTemplate,
        address indexed newCommunityTemplate
    );

    /**
     * @notice Triggered when a community has been funded
     *
     * @param community           Address of the community
     * @param amount              Amount of the funding
     */
    event CommunityFunded(address indexed community, uint256 amount);

    /**
     * @notice Triggered when an amount of an ERC20 has been transferred from this contract to an address
     *
     * @param token               ERC20 token address
     * @param to                  Address of the receiver
     * @param amount              Amount of the transaction
     */
    event TransferERC20(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Enforces sender to be a valid community
     */
    modifier onlyCommunities() {
        require(communities[msg.sender] == CommunityState.Valid, "CommunityAdmin: NOT_COMMUNITY");
        _;
    }

    /**
     * @notice Used to initialize a new CommunityAdmin contract
     *
     * @param _communityTemplate    Address of the Community implementation
     *                              used for deploying new communities
     * @param _cUSD                 Address of the cUSD token
     */
    function initialize(ICommunity _communityTemplate, IERC20 _cUSD) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        communityTemplate = _communityTemplate;
        cUSD = _cUSD;

        communityProxyAdmin = new ProxyAdmin();
    }

    /**
     * @notice Returns the current implementation version
     */
    function getVersion() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Returns the address of a community from communityList
     *
     * @param _index index of the community
     * @return address of the community
     */
    function communityListAt(uint256 _index) external view override returns (address) {
        return communityList.at(_index);
    }

    /**
     * @notice Returns the number of communities
     *
     * @return uint256 number of communities
     */
    function communityListLength() external view override returns (uint256) {
        return communityList.length();
    }

    /**
     * @notice Updates the address of the treasury
     *
     * @param _newTreasury address of the new treasury contract
     */
    function updateTreasury(ITreasury _newTreasury) external override onlyOwner {
        address oldTreasuryAddress = address(treasury);
        treasury = _newTreasury;

        emit TreasuryUpdated(oldTreasuryAddress, address(_newTreasury));
    }

    /**
     * @notice Updates the address of the the communityTemplate
     *
     * @param _newCommunityTemplate address of the new communityTemplate contract
     */
    function updateCommunityTemplate(ICommunity _newCommunityTemplate) external override onlyOwner {
        address _oldCommunityTemplateAddress = address(communityTemplate);
        communityTemplate = _newCommunityTemplate;

        emit CommunityTemplateUpdated(_oldCommunityTemplateAddress, address(_newCommunityTemplate));
    }

    /**
     * @notice Adds a new community
     *
     * @param _managers addresses of the community managers
     * @param _claimAmount base amount to be claim by the beneficiary
     * @param _maxClaim limit that a beneficiary can claim at in total
     * @param _decreaseStep value decreased from maxClaim for every beneficiary added
     * @param _baseInterval base interval to start claiming
     * @param _incrementInterval increment interval used in each claim
     * @param _minTranche minimum amount that the community will receive when requesting funds
     * @param _maxTranche maximum amount that the community will receive when requesting funds
     */
    function addCommunity(
        address[] memory _managers,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval,
        uint256 _minTranche,
        uint256 _maxTranche
    ) external override onlyOwner {
        require(
            _managers.length > 0,
            "CommunityAdmin::addCommunity: Community should have at least one manager"
        );
        address _communityAddress = deployCommunity(
            _managers,
            _claimAmount,
            _maxClaim,
            _decreaseStep,
            _baseInterval,
            _incrementInterval,
            _minTranche,
            _maxTranche,
            ICommunity(address(0))
        );
        require(_communityAddress != address(0), "CommunityAdmin::addCommunity: NOT_VALID");
        communities[_communityAddress] = CommunityState.Valid;
        communityList.add(_communityAddress);

        emit CommunityAdded(
            _communityAddress,
            _managers,
            _claimAmount,
            _maxClaim,
            _decreaseStep,
            _baseInterval,
            _incrementInterval,
            _minTranche,
            _maxTranche
        );

        transferToCommunity(ICommunity(_communityAddress), _minTranche);
        treasury.transfer(cUSD, address(_managers[0]), DEFAULT_AMOUNT);
    }

    /**
     * @notice Migrates a community by deploying a new contract.
     *
     * @param _managers address of the community managers
     * @param _previousCommunity address of the community to be migrated
     */
    function migrateCommunity(address[] memory _managers, ICommunity _previousCommunity)
        external
        override
        onlyOwner
        nonReentrant
    {
        require(
            communities[address(_previousCommunity)] != CommunityState.Migrated,
            "CommunityAdmin::migrateCommunity: this community has been migrated"
        );

        communities[address(_previousCommunity)] = CommunityState.Migrated;

        bool _isCommunityNew = isCommunityNewType(_previousCommunity);

        address newCommunityAddress;
        if (_isCommunityNew) {
            newCommunityAddress = deployCommunity(
                _managers,
                _previousCommunity.claimAmount(),
                _previousCommunity.getInitialMaxClaim(),
                _previousCommunity.decreaseStep(),
                _previousCommunity.baseInterval(),
                _previousCommunity.incrementInterval(),
                _previousCommunity.minTranche(),
                _previousCommunity.maxTranche(),
                _previousCommunity
            );
        } else {
            newCommunityAddress = deployCommunity(
                _managers,
                _previousCommunity.claimAmount(),
                _previousCommunity.maxClaim(),
                1e16,
                (_previousCommunity.baseInterval() / 5),
                (_previousCommunity.incrementInterval() / 5),
                1e16,
                5e18,
                _previousCommunity
            );
        }

        require(newCommunityAddress != address(0), "CommunityAdmin::migrateCommunity: NOT_VALID");

        if (_isCommunityNew) {
            uint256 balance = cUSD.balanceOf(address(_previousCommunity));
            _previousCommunity.transfer(cUSD, newCommunityAddress, balance);
        }

        communities[newCommunityAddress] = CommunityState.Valid;
        communityList.add(newCommunityAddress);

        emit CommunityMigrated(_managers, newCommunityAddress, address(_previousCommunity));
    }

    /**
     * @notice Adds a new manager to a community
     *
     * @param _community address of the community
     * @param _account address to be added as community manager
     */
    function addManagerToCommunity(ICommunity _community, address _account)
        external
        override
        onlyOwner
    {
        _community.addManager(_account);
    }

    /**
     * @notice Removes an existing community. All community funds are transferred to the treasury
     *
     * @param _community address of the community
     */
    function removeCommunity(ICommunity _community) external override onlyOwner nonReentrant {
        require(
            communities[address(_community)] == CommunityState.Valid,
            "CommunityAdmin::removeCommunity: this isn't a valid community"
        );
        communities[address(_community)] = CommunityState.Removed;

        _community.transfer(cUSD, address(treasury), cUSD.balanceOf(address(_community)));
        emit CommunityRemoved(address(_community));
    }

    /**
     * @dev Funds an existing community if it hasn't enough funds
     */
    function fundCommunity() external override onlyCommunities {
        ICommunity _community = ICommunity(msg.sender);
        uint256 _balance = cUSD.balanceOf(msg.sender);
        require(
            _balance < _community.minTranche(),
            "CommunityAdmin::fundCommunity: this community has enough funds"
        );
        require(
            block.number > _community.lastFundRequest() + _community.baseInterval(),
            "CommunityAdmin::fundCommunity: this community is not allowed to request yet"
        );

        uint256 _trancheAmount = calculateCommunityTrancheAmount(ICommunity(msg.sender));

        if (_trancheAmount > _balance) {
            uint256 _amount = _trancheAmount - _balance;
            uint256 _treasurySafetyBalance = cUSD.balanceOf(address(treasury)) /
                TREASURY_SAFETY_FACTOR;
            require(
                _amount <= _treasurySafetyBalance,
                "CommunityAdmin::fundCommunity: Not enough funds"
            );
            transferToCommunity(_community, _amount);
        }
    }

    /**
     * @notice Transfers an amount of an ERC20 from this contract to an address
     *
     * @param _token address of the ERC20 token
     * @param _to address of the receiver
     * @param _amount amount of the transaction
     */
    function transfer(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external override onlyOwner nonReentrant {
        _token.safeTransfer(_to, _amount);

        emit TransferERC20(address(_token), _to, _amount);
    }

    /**
     * @notice Transfers an amount of an ERC20 from  community to an address
     *
     * @param _community address of the community
     * @param _token address of the ERC20 token
     * @param _to address of the receiver
     * @param _amount amount of the transaction
     */
    function transferFromCommunity(
        ICommunity _community,
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external override onlyOwner nonReentrant {
        _community.transfer(_token, _to, _amount);
    }

    /** @notice Updates the beneficiary params of a community
     *
     * @param _community address of the community
     * @param _claimAmount  base amount to be claim by the beneficiary
     * @param _maxClaim limit that a beneficiary can claim  in total
     * @param _decreaseStep value decreased from maxClaim each time a is beneficiary added
     * @param _baseInterval base interval to start claiming
     * @param _incrementInterval increment interval used in each claim
     */
    function updateBeneficiaryParams(
        ICommunity _community,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval
    ) external override onlyOwner {
        _community.updateBeneficiaryParams(
            _claimAmount,
            _maxClaim,
            _decreaseStep,
            _baseInterval,
            _incrementInterval
        );
    }

    /** @notice Updates params of a community
     *
     * @param _community address of the community
     * @param _minTranche minimum amount that the community will receive when requesting funds
     * @param _maxTranche maximum amount that the community will receive when requesting funds
     */
    function updateCommunityParams(
        ICommunity _community,
        uint256 _minTranche,
        uint256 _maxTranche
    ) external override onlyOwner {
        _community.updateCommunityParams(_minTranche, _maxTranche);
    }

    /**
     * @notice Updates proxy implementation address of a community
     *
     * @param _communityProxy address of the community
     * @param _newCommunityTemplate address of new implementation contract
     */
    function updateProxyImplementation(address _communityProxy, address _newCommunityTemplate)
        external
        override
        onlyOwner
    {
        communityProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(_communityProxy)),
            _newCommunityTemplate
        );
    }

    /**
     * @dev Transfers cUSDs from the treasury to a community
     *
     * @param _community address of the community
     * @param _amount amount of the transaction
     */
    function transferToCommunity(ICommunity _community, uint256 _amount) internal nonReentrant {
        treasury.transfer(cUSD, address(_community), _amount);
        _community.addTreasuryFunds(_amount);

        emit CommunityFunded(address(_community), _amount);
    }

    /**
     * @dev Internal implementation of deploying a new community
     *
     * @param _managers addresses of the community managers
     * @param _claimAmount base amount to be claim by the beneficiary
     * @param _maxClaim limit that a beneficiary can claim at in total
     * @param _decreaseStep value decreased from maxClaim for every beneficiary added
     * @param _baseInterval base interval to start claiming
     * @param _incrementInterval increment interval used in each claim
     * @param _minTranche minimum amount that the community will receive when requesting funds
     * @param _maxTranche maximum amount that the community will receive when requesting funds
     * @param _previousCommunity address of the previous community. Used for migrating communities
     */
    function deployCommunity(
        address[] memory _managers,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval,
        uint256 _minTranche,
        uint256 _maxTranche,
        ICommunity _previousCommunity
    ) internal returns (address) {
        TransparentUpgradeableProxy _community = new TransparentUpgradeableProxy(
            address(communityTemplate),
            address(communityProxyAdmin),
            abi.encodeWithSignature(
                "initialize(address[],uint256,uint256,uint256,uint256,uint256,uint256,uint256,address)",
                _managers,
                _claimAmount,
                _maxClaim,
                _decreaseStep,
                _baseInterval,
                _incrementInterval,
                _minTranche,
                _maxTranche,
                address(_previousCommunity)
            )
        );

        return address(_community);
    }

    /** @dev Calculates the tranche amount of a community.
     *        Enforces the tranche amount to be between community minTranche and maxTranche
     * @param _community address of the community
     * @return uint256 the value of the tranche amount
     */
    function calculateCommunityTrancheAmount(ICommunity _community)
        internal
        view
        returns (uint256)
    {
        uint256 _validBeneficiaries = _community.validBeneficiaryCount();
        uint256 _claimAmount = _community.claimAmount();
        uint256 _treasuryFunds = _community.treasuryFunds();
        uint256 _privateFunds = _community.privateFunds();
        uint256 _minTranche = _community.minTranche();
        uint256 _maxTranche = _community.maxTranche();

        // `treasuryFunds` can't be zero.
        // Otherwise, migrated communities will have zero.
        _treasuryFunds = _treasuryFunds > 0 ? _treasuryFunds : 1e18;

        uint256 _trancheAmount = (_validBeneficiaries *
            _claimAmount *
            (_treasuryFunds + _privateFunds)) / _treasuryFunds;

        if (_trancheAmount < _minTranche) {
            _trancheAmount = _minTranche;
        } else if (_trancheAmount > _maxTranche) {
            _trancheAmount = _maxTranche;
        }

        return _trancheAmount;
    }

    /**
     * @notice Checks if a community is deployed with the new type of smart contract
     *
     * @param _community address of the community
     * @return bool true if the community is deployed with the new type of smart contract
     */
    function isCommunityNewType(ICommunity _community) internal pure returns (bool) {
        return _community.impactMarketAddress() == address(0);
    }
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../community/interfaces/ICommunityAdmin.sol";

interface ITreasury {
    function getVersion() external returns(uint256);
    function communityAdmin() external view returns(ICommunityAdmin);
    function updateCommunityAdmin(ICommunityAdmin _communityAdmin) external;
    function transfer(IERC20 _token, address _to, uint256 _amount) external;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface ICommunityOld {
    function cooldown(address _account) external returns(uint256);
    function lastInterval(address _account) external returns(uint256);
    function claimed(address _account) external returns(uint256);
    function beneficiaries(address _account) external returns(uint256);
    function claimAmount() external returns(uint256);
    function baseInterval() external returns(uint256);
    function incrementInterval() external returns(uint256);
    function maxClaim() external returns(uint256);
    function previousCommunityContract() external returns(address);
    function impactMarketAddress() external returns(address);
    function cUSDAddress() external returns(address);
    function locked() external returns(bool);
    function addManager(address _account) external;
    function removeManager(address _account) external;
    function addBeneficiary(address _account) external;
    function lockBeneficiary(address _account) external;
    function unlockBeneficiary(address _account) external;
    function removeBeneficiary(address _account) external;
    function claim() external;
    function edit(uint256 _claimAmount, uint256 _maxClaim, uint256 _baseInterval, uint256 _incrementInterval) external;
    function lock() external;
    function unlock() external;
    function migrateFunds(address _newCommunity, address _newCommunityManager) external;
    function hasRole(bytes32 role, address account) external view returns(bool);
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICommunity.sol";
import "../../token/interfaces/ITreasury.sol";

interface ICommunityAdmin {
    enum CommunityState {
        NONE,
        Valid,
        Removed,
        Migrated
    }

    function getVersion() external returns(uint256);
    function cUSD() external view returns(IERC20);
    function treasury() external view returns(ITreasury);
    function communities(address _community) external view returns(CommunityState);
    function communityTemplate() external view returns(ICommunity);
    function communityProxyAdmin() external view returns(ProxyAdmin);
    function communityListAt(uint256 _index) external view returns (address);
    function communityListLength() external view returns (uint256);

    function updateTreasury(ITreasury _newTreasury) external;
    function updateCommunityTemplate(ICommunity _communityTemplate_) external;
    function updateBeneficiaryParams(
        ICommunity _community,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval
    ) external;
    function updateCommunityParams(
        ICommunity _community,
        uint256 _minTranche,
        uint256 _maxTranche
    ) external;
    function updateProxyImplementation(address _communityProxy, address _newLogic) external;
    function addCommunity(
        address[] memory _managers,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval,
        uint256 _minTranche,
        uint256 _maxTranche
    ) external;
    function migrateCommunity(
        address[] memory _managers,
        ICommunity _previousCommunity
    ) external;
    function addManagerToCommunity(ICommunity _community_, address _account_) external;
    function removeCommunity(ICommunity _community) external;
    function fundCommunity() external;
    function transfer(IERC20 _token, address _to, uint256 _amount) external;
    function transferFromCommunity(
        ICommunity _community,
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICommunityAdmin.sol";

interface ICommunity {
    enum BeneficiaryState {
        NONE, //the beneficiary hasn't been added yet
        Valid,
        Locked,
        Removed
    }

    struct Beneficiary {
        BeneficiaryState state;  //beneficiary state
        uint256 claims;          //total number of claims
        uint256 claimedAmount;   //total amount of cUSD received
        uint256 lastClaim;       //block number of the last claim
    }

    function getVersion() external returns(uint256);
    function previousCommunity() external view returns(ICommunity);
    function claimAmount() external view returns(uint256);
    function baseInterval() external view returns(uint256);
    function incrementInterval() external view returns(uint256);
    function maxClaim() external view returns(uint256);
    function validBeneficiaryCount() external view returns(uint);
    function treasuryFunds() external view returns(uint);
    function privateFunds() external view returns(uint);
    function communityAdmin() external view returns(ICommunityAdmin);
    function cUSD() external view  returns(IERC20);
    function locked() external view returns(bool);
    function beneficiaries(address _beneficiaryAddress) external view returns(
        BeneficiaryState state,
        uint256 claims,
        uint256 claimedAmount,
        uint256 lastClaim
    );
    function decreaseStep() external view returns(uint);
    function beneficiaryListAt(uint256 _index) external view returns (address);
    function beneficiaryListLength() external view returns (uint256);
    function impactMarketAddress() external pure returns (address);
    function minTranche() external view returns(uint256);
    function maxTranche() external view returns(uint256);
    function lastFundRequest() external view returns(uint256);

    function updateCommunityAdmin(ICommunityAdmin _communityAdmin) external;
    function updatePreviousCommunity(ICommunity _newPreviousCommunity) external;
    function updateBeneficiaryParams(
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval
    ) external;
    function updateCommunityParams(
        uint256 _minTranche,
        uint256 _maxTranche
    ) external;
    function donate(address _sender, uint256 _amount) external;
    function addTreasuryFunds(uint256 _amount) external;
    function transfer(IERC20 _token, address _to, uint256 _amount) external;
    function addManager(address _managerAddress) external;
    function removeManager(address _managerAddress) external;
    function addBeneficiary(address _beneficiaryAddress) external;
    function lockBeneficiary(address _beneficiaryAddress) external;
    function unlockBeneficiary(address _beneficiaryAddress) external;
    function removeBeneficiary(address _beneficiaryAddress) external;
    function claim() external;
    function lastInterval(address _beneficiaryAddress) external view returns (uint256);
    function claimCooldown(address _beneficiaryAddress) external view returns (uint256);
    function lock() external;
    function unlock() external;
    function requestFunds() external;
    function beneficiaryJoinFromMigrated() external;
    function getInitialMaxClaim() external view returns (uint256);
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./ICommunity.sol";
import "./ICommunityAdmin.sol";

/**
 * @title Storage for Community
 * @notice For future upgrades, do not change CommunityStorageV1. Create a new
 * contract which implements CommunityStorageV1 and following the naming convention
 * CommunityStorageVX.
 */
abstract contract CommunityStorageV1 is ICommunity {
    bool public override locked;
    uint256 public override claimAmount;
    uint256 public override baseInterval;
    uint256 public override incrementInterval;
    uint256 public override maxClaim;
    uint256 public override validBeneficiaryCount;
    uint256 public override treasuryFunds;
    uint256 public override privateFunds;
    uint256 public override decreaseStep;
    uint256 public override minTranche;
    uint256 public override maxTranche;
    uint256 public override lastFundRequest;

    ICommunity public override previousCommunity;
    ICommunityAdmin public override communityAdmin;

    mapping(address => Beneficiary) public override beneficiaries;
    EnumerableSet.AddressSet internal beneficiaryList;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./ICommunityAdmin.sol";
import "../../token/interfaces/ITreasury.sol";

/**
 * @title Storage for CommunityAdmin
 * @notice For future upgrades, do not change CommunityAdminStorageV1. Create a new
 * contract which implements CommunityAdminStorageV1 and following the naming convention
 * CommunityAdminStorageVX.
 */
abstract contract CommunityAdminStorageV1 is ICommunityAdmin {
    IERC20 public override cUSD;
    ITreasury public override treasury;
    ICommunity public override communityTemplate;
    ProxyAdmin public override communityProxyAdmin;

    mapping(address => CommunityState) public override communities;
    EnumerableSet.AddressSet internal communityList;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/ICommunity.sol";
import "./interfaces/ICommunityOld.sol";
import "./interfaces/ICommunityAdmin.sol";
import "./interfaces/CommunityStorageV1.sol";

/**
 * @notice Welcome to the Community contract. For each community
 * there will be one proxy contract deployed by CommunityAdmin.
 * The implementation of the proxy is this contract. This enable
 * us to save tokens on the contract itself, and avoid the problems
 * of having everything in one single contract.
 *Each community has it's own members and and managers.
 */
contract Community is
    Initializable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    CommunityStorageV1
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 private constant DEFAULT_AMOUNT = 5e16;

    /**
     * @notice Triggered when a manager has been added
     *
     * @param manager           Address of the manager that triggered the event
     *                          or address of the CommunityAdmin if it's first manager
     * @param account           Address of the manager that has been added
     */
    event ManagerAdded(address indexed manager, address indexed account);

    /**
     * @notice Triggered when a manager has been removed
     *
     * @param manager           Address of the manager that triggered the event
     * @param account           Address of the manager that has been removed
     */
    event ManagerRemoved(address indexed manager, address indexed account);

    /**
     * @notice Triggered when a beneficiary has been added
     *
     * @param manager           Address of the manager that triggered the event
     * @param beneficiary       Address of the beneficiary that has been added
     */
    event BeneficiaryAdded(address indexed manager, address indexed beneficiary);

    /**
     * @notice Triggered when a beneficiary has been locked
     *
     * @param manager           Address of the manager that triggered the event
     * @param beneficiary       Address of the beneficiary that has been locked
     */
    event BeneficiaryLocked(address indexed manager, address indexed beneficiary);

    /**
     * @notice Triggered when a beneficiary has been unlocked
     *
     * @param manager           Address of the manager that triggered the event
     * @param beneficiary       Address of the beneficiary that has been unlocked
     */
    event BeneficiaryUnlocked(address indexed manager, address indexed beneficiary);

    /**
     * @notice Triggered when a beneficiary has been removed
     *
     * @param manager           Address of the manager that triggered the event
     * @param beneficiary       Address of the beneficiary that has been removed
     */
    event BeneficiaryRemoved(address indexed manager, address indexed beneficiary);

    /**
     * @notice Triggered when a beneficiary has claimed
     *
     * @param beneficiary       Address of the beneficiary that has claimed
     * @param amount            Amount of the claim
     */
    event BeneficiaryClaim(address indexed beneficiary, uint256 amount);

    /**
     * @notice Triggered when a community has been locked
     *
     * @param manager           Address of the manager that triggered the event
     */
    event CommunityLocked(address indexed manager);

    /**
     * @notice Triggered when a community has been unlocked
     *
     * @param manager           Address of the manager that triggered the event
     */
    event CommunityUnlocked(address indexed manager);

    /**
     * @notice Triggered when a manager has requested funds for community
     *
     * @param manager           Address of the manager that triggered the event
     */
    event FundsRequested(address indexed manager);

    /**
     * @notice Triggered when someone has donated cUSD
     *
     * @param donor             Address of the donor
     * @param amount            Amount of the donation
     */
    event Donate(address indexed donor, uint256 amount);

    /**
     * @notice Triggered when a beneficiary from previous community has joined in the current community
     *
     * @param beneficiary       Address of the beneficiary
     */
    event BeneficiaryJoined(address indexed beneficiary);

    /**
     * @notice Triggered when beneficiary params has been updated
     *
     * @param oldClaimAmount       Old claimAmount value
     * @param oldMaxClaim          Old maxClaim value
     * @param oldDecreaseStep      Old decreaseStep value
     * @param oldBaseInterval      Old baseInterval value
     * @param oldIncrementInterval Old incrementInterval value
     * @param newClaimAmount       New claimAmount value
     * @param newMaxClaim          New maxClaim value
     * @param newDecreaseStep      New decreaseStep value
     * @param newBaseInterval      New baseInterval value
     * @param newIncrementInterval New incrementInterval value
     *
     * For further information regarding each parameter, see
     * *Community* smart contract initialize method.
     */
    event BeneficiaryParamsUpdated(
        uint256 oldClaimAmount,
        uint256 oldMaxClaim,
        uint256 oldDecreaseStep,
        uint256 oldBaseInterval,
        uint256 oldIncrementInterval,
        uint256 newClaimAmount,
        uint256 newMaxClaim,
        uint256 newDecreaseStep,
        uint256 newBaseInterval,
        uint256 newIncrementInterval
    );

    /**
     * @notice Triggered when community params has been updated
     *
     * @param oldMinTranche        Old minTranche value
     * @param oldMaxTranche        Old maxTranche value
     * @param newMinTranche        New minTranche value
     * @param newMaxTranche        New maxTranche value
     *
     * For further information regarding each parameter, see
     * *Community* smart contract initialize method.
     */
    event CommunityParamsUpdated(
        uint256 oldMinTranche,
        uint256 oldMaxTranche,
        uint256 newMinTranche,
        uint256 newMaxTranche
    );

    /**
     * @notice Triggered when communityAdmin has been updated
     *
     * @param oldCommunityAdmin   Old communityAdmin address
     * @param newCommunityAdmin   New communityAdmin address
     */
    event CommunityAdminUpdated(
        address indexed oldCommunityAdmin,
        address indexed newCommunityAdmin
    );

    /**
     * @notice Triggered when previousCommunity has been updated
     *
     * @param oldPreviousCommunity   Old previousCommunity address
     * @param newPreviousCommunity   New previousCommunity address
     */
    event PreviousCommunityUpdated(
        address indexed oldPreviousCommunity,
        address indexed newPreviousCommunity
    );

    /**
     * @notice Triggered when an amount of an ERC20 has been transferred from this contract to an address
     *
     * @param token               ERC20 token address
     * @param to                  Address of the receiver
     * @param amount              Amount of the transaction
     */
    event TransferERC20(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Used to initialize a new Community contract
     *
     * @param _managers            Community's initial managers.
     *                             Will be able to add others
     * @param _claimAmount         Base amount to be claim by the beneficiary
     * @param _maxClaim            Limit that a beneficiary can claim in total
     * @param _decreaseStep        Value decreased from maxClaim each time a beneficiary is added
     * @param _baseInterval        Base interval to start claiming
     * @param _incrementInterval   Increment interval used in each claim
     * @param _previousCommunity   Previous smart contract address of community
     * @param _minTranche          Minimum amount that the community will receive when requesting funds
     * @param _maxTranche          Maximum amount that the community will receive when requesting funds
     */
    function initialize(
        address[] memory _managers,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval,
        uint256 _minTranche,
        uint256 _maxTranche,
        ICommunity _previousCommunity
    ) external initializer {
        require(
            _baseInterval > _incrementInterval,
            "Community::initialize: baseInterval must be greater than incrementInterval"
        );
        require(
            _maxClaim > _claimAmount,
            "Community::initialize: maxClaim must be greater than claimAmount"
        );

        require(
            _minTranche <= _maxTranche,
            "Community::initialize: minTranche should not be greater than maxTranche"
        );

        __AccessControl_init();
        __Ownable_init();
        __ReentrancyGuard_init();

        claimAmount = _claimAmount;
        baseInterval = _baseInterval;
        incrementInterval = _incrementInterval;
        maxClaim = _maxClaim;
        minTranche = _minTranche;
        maxTranche = _maxTranche;
        previousCommunity = _previousCommunity;
        communityAdmin = ICommunityAdmin(msg.sender);
        decreaseStep = _decreaseStep;
        locked = false;

        transferOwnership(msg.sender);

        // MANAGER_ROLE is the admin for the MANAGER_ROLE
        // so every manager is able to add or remove other managers
        _setRoleAdmin(MANAGER_ROLE, MANAGER_ROLE);

        _setupRole(MANAGER_ROLE, msg.sender);
        emit ManagerAdded(msg.sender, msg.sender);

        for (uint256 i = 0; i < _managers.length; i++) {
            addManager(_managers[i]);
        }
    }

    /**
     * @notice Returns the current implementation version
     */
    function getVersion() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Enforces sender to be a valid beneficiary
     */
    modifier onlyValidBeneficiary() {
        require(
            beneficiaries[msg.sender].state == BeneficiaryState.Valid,
            "Community: NOT_VALID_BENEFICIARY"
        );
        _;
    }

    /**
     * @notice Enforces sender to have manager role
     */
    modifier onlyManagers() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Community: NOT_MANAGER");
        _;
    }

    /**
     * @notice Returns the cUSD contract address
     */
    function cUSD() public view override returns (IERC20) {
        return communityAdmin.cUSD();
    }

    /**
     * @notice Returns the length of the beneficiaryList
     */
    function beneficiaryListLength() external view override returns (uint256) {
        return beneficiaryList.length();
    }

    /**
     * @notice Returns an address from the beneficiaryList
     *
     * @param index_ index value
     * @return address of the beneficiary
     */
    function beneficiaryListAt(uint256 index_) external view override returns (address) {
        return beneficiaryList.at(index_);
    }

    /**
     * @notice Returns the 0 address
     * only used for backwards compatibility
     */
    function impactMarketAddress() public pure override returns (address) {
        return address(0);
    }

    /** Updates the address of the communityAdmin
     *
     * @param _newCommunityAdmin address of the new communityAdmin
     */
    function updateCommunityAdmin(ICommunityAdmin _newCommunityAdmin) external override onlyOwner {
        address _oldCommunityAdminAddress = address(communityAdmin);
        communityAdmin = _newCommunityAdmin;

        addManager(address(communityAdmin));

        emit CommunityAdminUpdated(_oldCommunityAdminAddress, address(_newCommunityAdmin));
    }

    /** Updates the address of the previousCommunity
     *
     * @param _newPreviousCommunity address of the new previousCommunity
     */
    function updatePreviousCommunity(ICommunity _newPreviousCommunity) external override onlyOwner {
        address _oldPreviousCommunityAddress = address(previousCommunity);
        previousCommunity = _newPreviousCommunity;

        emit PreviousCommunityUpdated(_oldPreviousCommunityAddress, address(_newPreviousCommunity));
    }

    /** Updates beneficiary params
     *
     * @param _claimAmount  base amount to be claim by the beneficiary
     * @param _maxClaim limit that a beneficiary can claim  in total
     * @param _decreaseStep value decreased from maxClaim each time a is beneficiary added
     * @param _baseInterval base interval to start claiming
     * @param _incrementInterval increment interval used in each claim
     */
    function updateBeneficiaryParams(
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval
    ) external override onlyOwner {
        require(
            _baseInterval > _incrementInterval,
            "Community::constructor: baseInterval must be greater than incrementInterval"
        );
        require(
            _maxClaim > _claimAmount,
            "Community::constructor: maxClaim must be greater than claimAmount"
        );

        uint256 _oldClaimAmount = claimAmount;
        uint256 _oldMaxClaim = maxClaim;
        uint256 _oldDecreaseStep = decreaseStep;
        uint256 _oldBaseInterval = baseInterval;
        uint256 _oldIncrementInterval = incrementInterval;

        claimAmount = _claimAmount;
        maxClaim = _maxClaim;
        decreaseStep = _decreaseStep;
        baseInterval = _baseInterval;
        incrementInterval = _incrementInterval;

        emit BeneficiaryParamsUpdated(
            _oldClaimAmount,
            _oldMaxClaim,
            _oldDecreaseStep,
            _oldBaseInterval,
            _oldIncrementInterval,
            _claimAmount,
            _maxClaim,
            _decreaseStep,
            _baseInterval,
            _incrementInterval
        );
    }

    /** @notice Updates params of a community
     *
     * @param _minTranche minimum amount that the community will receive when requesting funds
     * @param _maxTranche maximum amount that the community will receive when requesting funds
     */
    function updateCommunityParams(uint256 _minTranche, uint256 _maxTranche)
        external
        override
        onlyOwner
    {
        require(
            _minTranche <= _maxTranche,
            "Community::updateCommunityParams: minTranche should not be greater than maxTranche"
        );

        uint256 _oldMinTranche = minTranche;
        uint256 _oldMaxTranche = maxTranche;

        minTranche = _minTranche;
        maxTranche = _maxTranche;

        emit CommunityParamsUpdated(_oldMinTranche, _oldMaxTranche, _minTranche, _maxTranche);
    }

    /**
     * @notice Adds a new manager
     *
     * @param _account address of the manager to be added
     */
    function addManager(address _account) public override onlyManagers {
        if (!hasRole(MANAGER_ROLE, _account)) {
            super.grantRole(MANAGER_ROLE, _account);
            emit ManagerAdded(msg.sender, _account);
        }
    }

    /**
     * @notice Remove an existing manager
     *
     * @param _account address of the manager to be removed
     */
    function removeManager(address _account) external override onlyManagers {
        require(
            hasRole(MANAGER_ROLE, _account),
            "Community::removeManager: This account doesn't have manager role"
        );
        require(
            _account != address(communityAdmin),
            "Community::removeManager: You are not allow to remove communityAdmin"
        );
        super.revokeRole(MANAGER_ROLE, _account);
        emit ManagerRemoved(msg.sender, _account);
    }

    /**
     * @notice Enforces managers to use addManager method
     */
    function grantRole(bytes32, address) public pure override {
        require(false, "Community::grantRole: You are not allow to use this method");
    }

    /**
     * @notice Enforces managers to use removeManager method
     */
    function revokeRole(bytes32, address) public pure override {
        require(false, "Community::revokeRole: You are not allow to use this method");
    }

    /**
     * @notice Adds a new beneficiary
     *
     * @param _beneficiaryAddress address of the beneficiary to be added
     */
    function addBeneficiary(address _beneficiaryAddress)
        external
        override
        onlyManagers
        nonReentrant
    {
        Beneficiary storage _beneficiary = beneficiaries[_beneficiaryAddress];
        require(
            _beneficiary.state == BeneficiaryState.NONE,
            "Community::addBeneficiary: Beneficiary exists"
        );
        _changeBeneficiaryState(_beneficiary, BeneficiaryState.Valid);
        // solhint-disable-next-line not-rely-on-time
        _beneficiary.lastClaim = block.number;

        beneficiaryList.add(_beneficiaryAddress);

        // send default amount when adding a new beneficiary
        cUSD().safeTransfer(_beneficiaryAddress, DEFAULT_AMOUNT);

        emit BeneficiaryAdded(msg.sender, _beneficiaryAddress);
    }

    /**
     * @notice Locks a valid beneficiary
     *
     * @param _beneficiaryAddress address of the beneficiary to be locked
     */
    function lockBeneficiary(address _beneficiaryAddress) external override onlyManagers {
        Beneficiary storage _beneficiary = beneficiaries[_beneficiaryAddress];

        require(
            _beneficiary.state == BeneficiaryState.Valid,
            "Community::lockBeneficiary: NOT_YET"
        );
        _changeBeneficiaryState(_beneficiary, BeneficiaryState.Locked);
        emit BeneficiaryLocked(msg.sender, _beneficiaryAddress);
    }

    /**
     * @notice  Unlocks a locked beneficiary
     *
     * @param _beneficiaryAddress address of the beneficiary to be unlocked
     */
    function unlockBeneficiary(address _beneficiaryAddress) external override onlyManagers {
        Beneficiary storage _beneficiary = beneficiaries[_beneficiaryAddress];

        require(
            _beneficiary.state == BeneficiaryState.Locked,
            "Community::unlockBeneficiary: NOT_YET"
        );
        _changeBeneficiaryState(_beneficiary, BeneficiaryState.Valid);
        emit BeneficiaryUnlocked(msg.sender, _beneficiaryAddress);
    }

    /**
     * @notice Remove an existing beneficiary
     *
     * @param _beneficiaryAddress address of the beneficiary to be removed
     */
    function removeBeneficiary(address _beneficiaryAddress) external override onlyManagers {
        Beneficiary storage _beneficiary = beneficiaries[_beneficiaryAddress];

        require(
            _beneficiary.state == BeneficiaryState.Valid ||
                _beneficiary.state == BeneficiaryState.Locked,
            "Community::removeBeneficiary: NOT_YET"
        );
        _changeBeneficiaryState(_beneficiary, BeneficiaryState.Removed);
        emit BeneficiaryRemoved(msg.sender, _beneficiaryAddress);
    }

    /**
     * @dev Transfers cUSD to a valid beneficiary
     */
    function claim() external override onlyValidBeneficiary nonReentrant {
        Beneficiary storage _beneficiary = beneficiaries[msg.sender];

        require(!locked, "LOCKED");
        require(claimCooldown(msg.sender) <= block.number, "Community::claim: NOT_YET");
        require(
            (_beneficiary.claimedAmount + claimAmount) <= maxClaim,
            "Community::claim: MAX_CLAIM"
        );

        _beneficiary.claimedAmount += claimAmount;
        _beneficiary.claims++;
        _beneficiary.lastClaim = block.number;

        cUSD().safeTransfer(msg.sender, claimAmount);
        emit BeneficiaryClaim(msg.sender, claimAmount);
    }

    /**
     * @notice Returns the number of blocks that a beneficiary have to wait between claims
     *
     * @param _beneficiaryAddress address of the beneficiary
     * @return uint256 number of blocks for the lastInterval
     */
    function lastInterval(address _beneficiaryAddress) public view override returns (uint256) {
        Beneficiary storage _beneficiary = beneficiaries[_beneficiaryAddress];
        if (_beneficiary.claims == 0) {
            return 0;
        }
        return baseInterval + (_beneficiary.claims - 1) * incrementInterval;
    }

    /**
     * @notice Returns the block number when a beneficiary can claim again
     *
     * @param _beneficiaryAddress address of the beneficiary
     * @return uint256 number of block when the beneficiary can claim
     */
    function claimCooldown(address _beneficiaryAddress) public view override returns (uint256) {
        return beneficiaries[_beneficiaryAddress].lastClaim + lastInterval(_beneficiaryAddress);
    }

    /**
     * @notice Locks the community claims
     */
    function lock() external override onlyManagers {
        locked = true;
        emit CommunityLocked(msg.sender);
    }

    /**
     * @notice Unlocks the community claims
     */
    function unlock() external override onlyManagers {
        locked = false;
        emit CommunityUnlocked(msg.sender);
    }

    /**
     * @notice Requests treasury funds from the communityAdmin
     */
    function requestFunds() external override onlyManagers {
        communityAdmin.fundCommunity();

        lastFundRequest = block.number;

        emit FundsRequested(msg.sender);
    }

    /**
     * @notice Transfers cUSDs from donor to this community
     * Used by donationToCommunity method from DonationMiner contract
     *
     * @param _sender address of the sender
     * @param _amount amount to be donated
     */
    function donate(address _sender, uint256 _amount) external override nonReentrant {
        cUSD().safeTransferFrom(_sender, address(this), _amount);
        privateFunds += _amount;

        emit Donate(msg.sender, _amount);
    }

    /**
     * @notice Increases the treasuryFunds value
     * Used by communityAdmin after an amount of cUSD are sent from the treasury
     *
     * @param _amount amount to be added to treasuryFunds
     */
    function addTreasuryFunds(uint256 _amount) external override onlyOwner {
        treasuryFunds += _amount;
    }

    /**
     * @notice Transfers an amount of an ERC20 from this contract to an address
     *
     * @param _token address of the ERC20 token
     * @param _to address of the receiver
     * @param _amount amount of the transaction
     */
    function transfer(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external override onlyOwner nonReentrant {
        _token.safeTransfer(_to, _amount);

        emit TransferERC20(address(_token), _to, _amount);
    }

    /**
     * @notice Allows a beneficiary from the previousCommunity to join in this community
     */
    function beneficiaryJoinFromMigrated() external override {
        // no need to check if it's a beneficiary, as the state is copied
        Beneficiary storage _beneficiary = beneficiaries[msg.sender];

        require(
            _beneficiary.state == BeneficiaryState.NONE,
            "Community::beneficiaryJoinFromMigrated: Beneficiary exists"
        );

        //if the previousCommunity is deployed with the new type of smart contract
        if (previousCommunity.impactMarketAddress() == address(0)) {
            (
                BeneficiaryState _oldBeneficiaryState,
                uint256 _oldBeneficiaryClaims,
                uint256 _oldBeneficiaryClaimedAmount,
                uint256 _oldBeneficiaryLastClaim
            ) = previousCommunity.beneficiaries(msg.sender);

            _changeBeneficiaryState(_beneficiary, _oldBeneficiaryState);
            _beneficiary.claims = _oldBeneficiaryClaims;
            _beneficiary.lastClaim = _oldBeneficiaryLastClaim;
            _beneficiary.claimedAmount = _oldBeneficiaryClaimedAmount;
        } else {
            ICommunityOld _oldCommunity = ICommunityOld(address(previousCommunity));
            uint256 _oldBeneficiaryLastInterval = _oldCommunity.lastInterval(msg.sender);
            _changeBeneficiaryState(
                _beneficiary,
                BeneficiaryState(_oldCommunity.beneficiaries(msg.sender))
            );

            uint256 _oldBeneficiaryCooldown = _oldCommunity.cooldown(msg.sender);

            if (_oldBeneficiaryCooldown >= _oldBeneficiaryLastInterval + _firstBlockTimestamp()) {
                // seconds to blocks conversion
                _beneficiary.lastClaim =
                    (_oldBeneficiaryCooldown -
                        _oldBeneficiaryLastInterval -
                        _firstBlockTimestamp()) /
                    5;
            } else {
                _beneficiary.lastClaim = 0;
            }

            _beneficiary.claimedAmount = _oldCommunity.claimed(msg.sender);

            uint256 _previousBaseInterval = _oldCommunity.baseInterval();
            if (_oldBeneficiaryLastInterval >= _previousBaseInterval) {
                _beneficiary.claims =
                    (_oldBeneficiaryLastInterval - _previousBaseInterval) /
                    _oldCommunity.incrementInterval() +
                    1;
            } else {
                _beneficiary.claims = 0;
            }
        }

        beneficiaryList.add(msg.sender);

        emit BeneficiaryJoined(msg.sender);
    }

    /**
     * @notice Returns the initial maxClaim
     */
    function getInitialMaxClaim() external view override returns (uint256) {
        return maxClaim + validBeneficiaryCount * decreaseStep;
    }

    /**
     * @notice Changes the state of a beneficiary
     *
     * @param _beneficiary address of the beneficiary
     * @param _newState new state
     */
    function _changeBeneficiaryState(Beneficiary storage _beneficiary, BeneficiaryState _newState)
        internal
    {
        if (_beneficiary.state == _newState) {
            return;
        }

        if (_newState == BeneficiaryState.Valid) {
            require(
                maxClaim - decreaseStep >= claimAmount,
                "Community::_changeBeneficiaryState: This community has reached the maximum number of valid beneficiaries"
            );
            validBeneficiaryCount++;
            maxClaim -= decreaseStep;
        } else if (_beneficiary.state == BeneficiaryState.Valid) {
            validBeneficiaryCount--;
            maxClaim += decreaseStep;
        }

        _beneficiary.state = _newState;
    }

    function _firstBlockTimestamp() public view returns (uint256) {
        if (block.chainid == 42220) {
            //celo mainnet
            return 1587571205;
        } else if (block.chainid == 44787) {
            //alfajores testnet
            return 1594921556;
        } else if (block.chainid == 44787) {
            //baklava testnet
            return 1593012289;
        } else {
            return block.timestamp - block.number; //local
        }
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165Upgradeable {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165Upgradeable.sol";
import "../../proxy/utils/Initializable.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165Upgradeable is Initializable, IERC165Upgradeable {
    function __ERC165_init() internal initializer {
        __ERC165_init_unchained();
    }

    function __ERC165_init_unchained() internal initializer {
    }
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165Upgradeable).interfaceId;
    }
    uint256[50] private __gap;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library StringsUpgradeable {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}


// SPDX-License-Identifier: MIT

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
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
    uint256[50] private __gap;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
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
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

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
}


// SPDX-License-Identifier: MIT

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
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControlUpgradeable {
    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) external;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IAccessControlUpgradeable.sol";
import "../utils/ContextUpgradeable.sol";
import "../utils/StringsUpgradeable.sol";
import "../utils/introspection/ERC165Upgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControlUpgradeable is Initializable, ContextUpgradeable, IAccessControlUpgradeable, ERC165Upgradeable {
    function __AccessControl_init() internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
    }

    function __AccessControl_init_unchained() internal initializer {
    }
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     */
    function _checkRole(bytes32 role, address account) internal view {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        StringsUpgradeable.toHexString(uint160(account), 20),
                        " is missing role ",
                        StringsUpgradeable.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    function _grantRole(bytes32 role, address account) private {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            if (lastIndex != toDeleteIndex) {
                bytes32 lastvalue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastvalue;
                // Update the index for the moved value
                set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex
            }

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, and `uint256`._
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
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
        return msg.data;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
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
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
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
        return _verifyCallResult(success, returndata, errorMessage);
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
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
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

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
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
        IERC20 token,
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
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
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
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
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

pragma solidity ^0.8.0;

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
    function transferFrom(
        address sender,
        address recipient,
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

pragma solidity ^0.8.0;

import "../ERC1967/ERC1967Proxy.sol";

/**
 * @dev This contract implements a proxy that is upgradeable by an admin.
 *
 * To avoid https://medium.com/nomic-labs-blog/malicious-backdoors-in-ethereum-proxies-62629adf3357[proxy selector
 * clashing], which can potentially be used in an attack, this contract uses the
 * https://blog.openzeppelin.com/the-transparent-proxy-pattern/[transparent proxy pattern]. This pattern implies two
 * things that go hand in hand:
 *
 * 1. If any account other than the admin calls the proxy, the call will be forwarded to the implementation, even if
 * that call matches one of the admin functions exposed by the proxy itself.
 * 2. If the admin calls the proxy, it can access the admin functions, but its calls will never be forwarded to the
 * implementation. If the admin tries to call a function on the implementation it will fail with an error that says
 * "admin cannot fallback to proxy target".
 *
 * These properties mean that the admin account can only be used for admin actions like upgrading the proxy or changing
 * the admin, so it's best if it's a dedicated account that is not used for anything else. This will avoid headaches due
 * to sudden errors when trying to call a function from the proxy implementation.
 *
 * Our recommendation is for the dedicated account to be an instance of the {ProxyAdmin} contract. If set up this way,
 * you should think of the `ProxyAdmin` instance as the real administrative interface of your proxy.
 */
contract TransparentUpgradeableProxy is ERC1967Proxy {
    /**
     * @dev Initializes an upgradeable proxy managed by `_admin`, backed by the implementation at `_logic`, and
     * optionally initialized with `_data` as explained in {ERC1967Proxy-constructor}.
     */
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {
        assert(_ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        _changeAdmin(admin_);
    }

    /**
     * @dev Modifier used internally that will delegate the call to the implementation unless the sender is the admin.
     */
    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @dev Returns the current admin.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-getProxyAdmin}.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function admin() external ifAdmin returns (address admin_) {
        admin_ = _getAdmin();
    }

    /**
     * @dev Returns the current implementation.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-getProxyImplementation}.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     */
    function implementation() external ifAdmin returns (address implementation_) {
        implementation_ = _implementation();
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-changeProxyAdmin}.
     */
    function changeAdmin(address newAdmin) external virtual ifAdmin {
        _changeAdmin(newAdmin);
    }

    /**
     * @dev Upgrade the implementation of the proxy.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgrade}.
     */
    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /**
     * @dev Upgrade the implementation of the proxy, and then call a function from the new implementation as specified
     * by `data`, which should be an encoded function call. This is useful to initialize new storage variables in the
     * proxied contract.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgradeAndCall}.
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable ifAdmin {
        _upgradeToAndCall(newImplementation, data, true);
    }

    /**
     * @dev Returns the current admin.
     */
    function _admin() internal view virtual returns (address) {
        return _getAdmin();
    }

    /**
     * @dev Makes sure the admin cannot access the fallback function. See {Proxy-_beforeFallback}.
     */
    function _beforeFallback() internal virtual override {
        require(msg.sender != _getAdmin(), "TransparentUpgradeableProxy: admin cannot fallback to proxy target");
        super._beforeFallback();
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./TransparentUpgradeableProxy.sol";
import "../../access/Ownable.sol";

/**
 * @dev This is an auxiliary contract meant to be assigned as the admin of a {TransparentUpgradeableProxy}. For an
 * explanation of why you would want to use this see the documentation for {TransparentUpgradeableProxy}.
 */
contract ProxyAdmin is Ownable {
    /**
     * @dev Returns the current implementation of `proxy`.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function getProxyImplementation(TransparentUpgradeableProxy proxy) public view virtual returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("implementation()")) == 0x5c60da1b
        (bool success, bytes memory returndata) = address(proxy).staticcall(hex"5c60da1b");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @dev Returns the current admin of `proxy`.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function getProxyAdmin(TransparentUpgradeableProxy proxy) public view virtual returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("admin()")) == 0xf851a440
        (bool success, bytes memory returndata) = address(proxy).staticcall(hex"f851a440");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @dev Changes the admin of `proxy` to `newAdmin`.
     *
     * Requirements:
     *
     * - This contract must be the current admin of `proxy`.
     */
    function changeProxyAdmin(TransparentUpgradeableProxy proxy, address newAdmin) public virtual onlyOwner {
        proxy.changeAdmin(newAdmin);
    }

    /**
     * @dev Upgrades `proxy` to `implementation`. See {TransparentUpgradeableProxy-upgradeTo}.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function upgrade(TransparentUpgradeableProxy proxy, address implementation) public virtual onlyOwner {
        proxy.upgradeTo(implementation);
    }

    /**
     * @dev Upgrades `proxy` to `implementation` and calls a function on the new implementation. See
     * {TransparentUpgradeableProxy-upgradeToAndCall}.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function upgradeAndCall(
        TransparentUpgradeableProxy proxy,
        address implementation,
        bytes memory data
    ) public payable virtual onlyOwner {
        proxy.upgradeToAndCall{value: msg.value}(implementation, data);
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {BeaconProxy} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This abstract contract provides a fallback function that delegates all calls to another contract using the EVM
 * instruction `delegatecall`. We refer to the second contract as the _implementation_ behind the proxy, and it has to
 * be specified by overriding the virtual {_implementation} function.
 *
 * Additionally, delegation to the implementation can be triggered manually through the {_fallback} function, or to a
 * different contract through the {_delegate} function.
 *
 * The success and return data of the delegated call will be returned back to the caller of the proxy.
 */
abstract contract Proxy {
    /**
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internall call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev This is a virtual function that should be overriden so it returns the address to which the fallback function
     * and {_fallback} should delegate.
     */
    function _implementation() internal view virtual returns (address);

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internall call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _beforeFallback();
        _delegate(_implementation());
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable virtual {
        _fallback();
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if call data
     * is empty.
     */
    receive() external payable virtual {
        _fallback();
    }

    /**
     * @dev Hook that is called before falling back to the implementation. Can happen as part of a manual `_fallback`
     * call, or as part of the Solidity `fallback` or `receive` functions.
     *
     * If overriden should call `super._beforeFallback()`.
     */
    function _beforeFallback() internal virtual {}
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../beacon/IBeacon.sol";
import "../../utils/Address.sol";
import "../../utils/StorageSlot.sol";

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 *
 * _Available since v4.1._
 *
 * @custom:oz-upgrades-unsafe-allow delegatecall
 */
abstract contract ERC1967Upgrade {
    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallSecure(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        address oldImplementation = _getImplementation();

        // Initial upgrade and setup call
        _setImplementation(newImplementation);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }

        // Perform rollback test if not already in progress
        StorageSlot.BooleanSlot storage rollbackTesting = StorageSlot.getBooleanSlot(_ROLLBACK_SLOT);
        if (!rollbackTesting.value) {
            // Trigger rollback using upgradeTo from the new implementation
            rollbackTesting.value = true;
            Address.functionDelegateCall(
                newImplementation,
                abi.encodeWithSignature("upgradeTo(address)", oldImplementation)
            );
            rollbackTesting.value = false;
            // Check rollback was effective
            require(oldImplementation == _getImplementation(), "ERC1967Upgrade: upgrade breaks further upgrades");
            // Finally reset to the new implementation and log the upgrade
            _upgradeTo(newImplementation);
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)) and is validated in the constructor.
     */
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Emitted when the beacon is upgraded.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Returns the current beacon.
     */
    function _getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(_BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        require(Address.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        require(
            Address.isContract(IBeacon(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlot.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(
        address newBeacon,
        bytes memory data,
        bool forceCall
    ) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        }
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Proxy.sol";
import "./ERC1967Upgrade.sol";

/**
 * @dev This contract implements an upgradeable proxy. It is upgradeable because calls are delegated to an
 * implementation address that can be changed. This address is stored in storage in the location specified by
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967], so that it doesn't conflict with the storage layout of the
 * implementation behind the proxy.
 */
contract ERC1967Proxy is Proxy, ERC1967Upgrade {
    /**
     * @dev Initializes the upgradeable proxy with an initial implementation specified by `_logic`.
     *
     * If `_data` is nonempty, it's used as data in a delegate call to `_logic`. This will typically be an encoded
     * function call, and allows initializating the storage of the proxy like a Solidity constructor.
     */
    constructor(address _logic, bytes memory _data) payable {
        assert(_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        _upgradeToAndCall(_logic, _data, false);
    }

    /**
     * @dev Returns the current implementation address.
     */
    function _implementation() internal view virtual override returns (address impl) {
        return ERC1967Upgrade._getImplementation();
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
    constructor() {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}