// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./KolorLandNFT.sol";

struct OffsetEmission {
    uint256 vcuOffset;
    uint256 offsetDate;
    uint256 vcuPrice;
    uint256 tokenId;
    address account;
}

contract KolorMarketplace is Ownable, ReentrancyGuard, IERC721Receiver {
    // Address of the nft contract and kolor
    address public KolorLandNFTAddress;

    // mapping from account to its offsets
    mapping(address => mapping(uint256 => OffsetEmission))
        public offsetsByAddress;
    mapping(address => uint256) public totalOffsetsOfAddress;

    // mapping from token id land to its offsets
    mapping(uint256 => mapping(uint256 => OffsetEmission)) public offsetsByLand;
    mapping(uint256 => uint256) public totalOffsetsOfLand;

    mapping(address => bool) public isAuthorized;

    constructor() {
        isAuthorized[msg.sender] = true;
    }

    modifier onlyAuthorized() {
        require(isAuthorized[msg.sender], "You're not allowed to do that");
        _;
    }

    function setNFTAddress(address _NFTAddress) public onlyOwner {
        KolorLandNFTAddress = _NFTAddress;
    }

    /**
        @dev Withdraw a published land from the marketplace

     */
    function removeLand(uint256 tokenId) public onlyAuthorized nonReentrant {
        IKolorLandNFT ilandInterface = IKolorLandNFT(KolorLandNFTAddress);

        ERC721 erc721 = ERC721(KolorLandNFTAddress);
        erc721.safeTransferFrom(address(this), owner(), tokenId);

        // update the land state to paused
        ilandInterface.updateLandState(tokenId, State.Paused);
    }

    /**
        @dev Register a new buying of vcu tokens

     */
    function offsetEmissions(
        uint256 tokenId,
        uint256 emissions,
        uint256 vcuPrice,
        address account
    ) external onlyAuthorized nonReentrant {
        IKolorLandNFT ilandInterface = IKolorLandNFT(KolorLandNFTAddress);
        KolorLandNFT kolorLand = KolorLandNFT(KolorLandNFTAddress);
        IERC721 erc721 = IERC721(KolorLandNFTAddress);

        require(
            ilandInterface.stateOf(tokenId) == State.Published,
            "This land NFT is not available!"
        );

        require(
            ilandInterface.getVCUSLeft(tokenId) >= emissions,
            "This land hasn't that much TCO2 to offset"
        );

        require(erc721.ownerOf(tokenId) != address(0), "Token doesn't exists!");

        // Add a new account to token Info
        ilandInterface.addBuyer(tokenId, account);

        // Create new information about this offset
        addOffsetEmissions(tokenId, emissions, vcuPrice, account);

        //Add Offset emissions in nft contract info
        kolorLand.offsetEmissions(tokenId, emissions);
    }

    /** @dev Adds a new offset structure to a account to represent
        its newly offset
    */
    function addOffsetEmissions(
        uint256 tokenId,
        uint256 emissions,
        uint256 vcuPrice,
        address account
    ) internal {
        addOffsetsEmissionsOfBuyer(tokenId, emissions, vcuPrice, account);
        addOffsetsEmmisionsOfLand(tokenId, emissions, vcuPrice, account);
    }

    /**
        @dev updates registry of emissions per client 
    
    */
    function addOffsetsEmissionsOfBuyer(
        uint256 tokenId,
        uint256 emissions,
        uint256 vcuPrice,
        address account
    ) public onlyAuthorized {
        uint256 currentOffsetsOf = totalOffsetsOfAddress[account];

        // add offset
        offsetsByAddress[account][currentOffsetsOf].vcuOffset = emissions;
        offsetsByAddress[account][currentOffsetsOf].offsetDate = block
            .timestamp;
        offsetsByAddress[account][currentOffsetsOf].tokenId = tokenId;
        offsetsByAddress[account][currentOffsetsOf].vcuPrice = vcuPrice;
        offsetsByAddress[account][currentOffsetsOf].account = account;

        // get the current offset emissions of this address
        totalOffsetsOfAddress[account]++;
    }

    /**
        @dev updates registry of emissions per land 
    
    */
    function addOffsetsEmmisionsOfLand(
        uint256 tokenId,
        uint256 emissions,
        uint256 vcuPrice,
        address account
    ) public onlyAuthorized {
        uint256 currentOffsetsOf = totalOffsetsOfLand[tokenId];

        // add offset
        offsetsByLand[tokenId][currentOffsetsOf].vcuOffset = emissions;
        offsetsByLand[tokenId][currentOffsetsOf].offsetDate = block.timestamp;
        offsetsByLand[tokenId][currentOffsetsOf].tokenId = tokenId;

        offsetsByLand[tokenId][currentOffsetsOf].vcuPrice = vcuPrice;
        offsetsByLand[tokenId][currentOffsetsOf].account = account;

        // get the current offset emissions of this land
        totalOffsetsOfLand[tokenId]++;
    }

    function _totalOffsetsOfAddress(address account)
        public
        view
        returns (uint256)
    {
        return totalOffsetsOfAddress[account];
    }

    function _totalOffsetsOfLand(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        return totalOffsetsOfLand[tokenId];
    }

    /**
        @dev returns offsets of given land
    */
    function offsetsOfLand(uint256 tokenId)
        public
        view
        returns (OffsetEmission[] memory)
    {
        uint256 _totalOffsetsOf = _totalOffsetsOfLand(tokenId);

        OffsetEmission[] memory offsets = new OffsetEmission[](_totalOffsetsOf);

        for (uint256 i = 0; i < _totalOffsetsOf; i++) {
            offsets[i] = offsetInfoByLand(i, tokenId);
        }

        return offsets;
    }

    /**
        @dev returns offsets of given account
    */
    function offsetsOfAddress(address account)
        public
        view
        returns (OffsetEmission[] memory)
    {
        uint256 _totalOffsetsOf = _totalOffsetsOfAddress(account);

        OffsetEmission[] memory offsets = new OffsetEmission[](_totalOffsetsOf);

        for (uint256 i = 0; i < _totalOffsetsOf; i++) {
            offsets[i] = offsetInfoByAddress(i, account);
        }

        return offsets;
    }

    /**
        @dev returns offset info of given land and offset
        
    */
    function offsetInfoByLand(uint256 offsetId, uint256 tokenId)
        public
        view
        returns (OffsetEmission memory)
    {
        return offsetsByLand[tokenId][offsetId];
    }

    /**
        @dev returns offset info of given account and offset
        
    */
    function offsetInfoByAddress(uint256 offsetId, address account)
        public
        view
        returns (OffsetEmission memory)
    {
        return offsetsByAddress[account][offsetId];
    }

    function authorize(address manager) public onlyOwner {
        isAuthorized[manager] = !isAuthorized[manager];
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

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
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
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


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

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
abstract contract ReentrancyGuard {
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

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
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
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./extensions/IERC721Metadata.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/Strings.sol";
import "../../utils/introspection/ERC165.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not token owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);

        _afterTokenTransfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/IERC721.sol)

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/IERC721Receiver.sol)

pragma solidity ^0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/extensions/ERC721Burnable.sol)

pragma solidity ^0.8.0;

import "../ERC721.sol";
import "../../../utils/Context.sol";

/**
 * @title ERC721 Burnable Token
 * @dev ERC721 Token that can be burned (destroyed).
 */
abstract contract ERC721Burnable is Context, ERC721 {
    /**
     * @dev Burns `tokenId`. See {ERC721-_burn}.
     *
     * Requirements:
     *
     * - The caller must own `tokenId` or be an approved operator.
     */
    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");
        _burn(tokenId);
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/ERC721Enumerable.sol)

pragma solidity ^0.8.0;

import "../ERC721.sol";
import "./IERC721Enumerable.sol";

/**
 * @dev This implements an optional extension of {ERC721} defined in the EIP that adds
 * enumerability of all the token ids in the contract as well as all token ids owned by each
 * account.
 */
abstract contract ERC721Enumerable is ERC721, IERC721Enumerable {
    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721.balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721Enumerable.totalSupply(), "ERC721Enumerable: global index out of bounds");
        return _allTokens[index];
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = ERC721.balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = ERC721.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC721/extensions/IERC721Enumerable.sol)

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Enumerable is IERC721 {
    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/IERC721Metadata.sol)

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

pragma solidity ^0.8.1;

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
                /// @solidity memory-safe-assembly
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
// OpenZeppelin Contracts v4.4.1 (utils/Counters.sol)

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented, decremented or reset. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library Counters {
    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

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

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

pragma solidity ^0.8.0;

import "./IERC165.sol";

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
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

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
interface IERC165 {
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

enum State {
    Created,
    Paused,
    Removed,
    Published
}

interface IKolorLandNFT {
    /**
        @dev Updates the availibility of tokenized land to be
        purchased in a marketplace
    
     */
    function updateLandState(uint256 tokenId, State state) external;

    function addBuyer(uint256 tokenId, address newBuyer) external;

    function updateName(uint256 tokenId, string memory name) external;

    function landOwnerOf(uint256 tokenId)
        external
        view
        returns (address landOwner);

    function isBuyerOf(uint256 tokenId, address buyer)
        external
        view
        returns (bool);

    function initialTCO2Of(uint256 tokenId)
        external
        view
        returns (uint256 initialTCO2);

    function stateOf(uint256 tokenId) external view returns (State state);

    function safeTransferToMarketplace(address from, uint256 tokenId) external;

    function getVCUSLeft(uint256 tokenId) external view returns (uint256 vcus);
}


// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./IKolorLandNFT.sol";

struct GeoSpatialPoint {
    int256 latitude;
    int256 longitude;
    uint256 decimals;
    uint256 creationDate;
    uint256 updateDate;
}

struct Species {
    string speciesAlias;
    string scientificName;
    uint256 density;
    uint256 size;
    uint256 decimals;
    uint256 TCO2perSecond;
    uint256 TCO2perYear;
    uint256 landId;
    uint256 creationDate;
    uint256 updateDate;
}

struct NFTInfo {
    string name;
    string identifier;
    address landOwner;
    string landOwnerAlias;
    uint256 decimals;
    uint256 size;
    string country;
    string stateOrRegion;
    string city;
    State state;
    uint256 initialTCO2perYear;
    uint256 soldTCO2;
    uint256 creationDate;
}

contract KolorLandNFT is ERC721, ERC721Enumerable, Ownable, IKolorLandNFT {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    address public marketplace;

    constructor() ERC721("Kolor Land NFT", "KLand") {
        isAuthorized[msg.sender] = true;
    }

    string public baseURI;

    // NFT info
    mapping(uint256 => NFTInfo) private mintedNFTSInfo;

    // Owned lands to use in enumeration
    mapping(address => mapping(uint256 => uint256)) private ownedLands;
    mapping(uint256 => uint256) private landIndex;
    mapping(address => uint256) private _totalLandOwned;

    // mapping to get buyers of a land
    mapping(uint256 => mapping(address => bool)) public buyers;
    mapping(uint256 => uint256) public totalBuyers;

    // mappings of conflictive data such as species and location
    mapping(uint256 => mapping(uint256 => Species)) public species;
    mapping(uint256 => uint256) public totalSpecies;

    mapping(uint256 => mapping(uint256 => GeoSpatialPoint)) public points;
    mapping(uint256 => uint256) public totalPoints;

    mapping(address => bool) public isAuthorized; //hot wallet, owner is cold wallet

    function safeMint(
        address to,
        string memory name,
        string memory identifier,
        address landOwner,
        string memory landOwnerAlias,
        uint256 decimals,
        uint256 size,
        string memory country,
        string memory stateOrRegion,
        string memory city,
        uint256 initialTCO2
    ) public onlyAuthorized {
        uint256 currentTokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, currentTokenId);

        // Set all NFT information
        mintedNFTSInfo[currentTokenId].name = name;
        mintedNFTSInfo[currentTokenId].identifier = identifier;
        mintedNFTSInfo[currentTokenId].landOwner = landOwner;
        mintedNFTSInfo[currentTokenId].landOwnerAlias = landOwnerAlias;
        mintedNFTSInfo[currentTokenId].decimals = decimals;
        mintedNFTSInfo[currentTokenId].size = size;
        mintedNFTSInfo[currentTokenId].country = country;
        mintedNFTSInfo[currentTokenId].stateOrRegion = stateOrRegion;
        mintedNFTSInfo[currentTokenId].city = city;
        mintedNFTSInfo[currentTokenId].initialTCO2perYear = initialTCO2;
        mintedNFTSInfo[currentTokenId].creationDate = block.timestamp;
        mintedNFTSInfo[currentTokenId].state = State.Created;

        uint256 _landsOwned = _totalLandOwned[landOwner];
        // set the tokenId to current landowner collection index
        ownedLands[landOwner][_landsOwned] = currentTokenId;

        // update the tokenId index in landowner collection
        landIndex[currentTokenId] = _landsOwned;

        // increase total lands owned by address
        _totalLandOwned[landOwner]++;
    }

    function authorize(address manager) public onlyOwner {
        isAuthorized[manager] = !isAuthorized[manager];
    }

    function setMarketplace(address _marketplace) public onlyAuthorized {
        marketplace = _marketplace;
        isAuthorized[marketplace] = true;
    }

    modifier onlyMarketplace() {
        require(
            marketplace == msg.sender,
            "Kolor Land NFT: You're not allowed to do that!"
        );
        _;
    }

    modifier onlyAuthorized() {
        require(
            isAuthorized[msg.sender],
            "Kolor Land NFT: You're not allowed to do that!"
        );
        _;
    }

    modifier notBurned(uint256 tokenId) {
        require(_exists(tokenId), "ERC721Metadata: operation on burned token!");
        _;
    }

    modifier notPublishedNorRemoved(uint256 tokenId) {
        require(
            !isRemoved(tokenId) && !isPublished(tokenId),
            "Kolor Land NFT:  This land can't be transfered to Marketplace"
        );
        _;
    }

    function isLandOwner(address landOwner, uint256 tokenId)
        public
        view
        returns (bool)
    {
        return mintedNFTSInfo[tokenId].landOwner == landOwner;
    }

    function isRemoved(uint256 tokenId) public view returns (bool) {
        return mintedNFTSInfo[tokenId].state == State.Removed;
    }

    function isPublished(uint256 tokenId) public view returns (bool) {
        return mintedNFTSInfo[tokenId].state == State.Published;
    }

    /**
        @dev Override of functions defined on interface ILandNFT
    
     */
    function updateLandState(uint256 tokenId, State _state)
        public
        override
        notBurned(tokenId)
        onlyAuthorized
    {
        require(_state != State.Created, "Kolor Land NFT: Invalid State");
        mintedNFTSInfo[tokenId].state = _state;
    }

    /**  
        @dev adds a new buyer to this land 
    */
    function addBuyer(uint256 tokenId, address newBuyer)
        public
        override
        onlyMarketplace
        notBurned(tokenId)
    {
        if (!buyers[tokenId][newBuyer]) {
            buyers[tokenId][newBuyer] = true;
            totalBuyers[tokenId]++;
        }
    }

    function updateName(uint256 tokenId, string memory newName)
        public
        override
        onlyAuthorized
        notBurned(tokenId)
    {
        mintedNFTSInfo[tokenId].name = newName;
    }

    function landOwnerOf(uint256 tokenId)
        public
        view
        override
        returns (address)
    {
        address landOwner = mintedNFTSInfo[tokenId].landOwner;

        return landOwner;
    }

    function landIndexOf(uint256 tokenId) public view returns (uint256) {
        return landIndex[tokenId];
    }

    function isBuyerOf(uint256 tokenId, address buyer)
        public
        view
        override
        returns (bool)
    {
        return buyers[tokenId][buyer];
    }

    function initialTCO2Of(uint256 tokenId)
        public
        view
        override
        returns (uint256)
    {
        return mintedNFTSInfo[tokenId].initialTCO2perYear;
    }

    function stateOf(uint256 tokenId) public view override returns (State) {
        return mintedNFTSInfo[tokenId].state;
    }

    /**
        @dev transfers the token to the marketplace and marks it
        as published for buyers to invest

     */
    function safeTransferToMarketplace(address from, uint256 tokenId)
        public
        override
        notBurned(tokenId)
        onlyAuthorized
        notPublishedNorRemoved(tokenId)
    {
        // Transfer to the marketplace
        updateLandState(tokenId, State.Published);
        safeTransferFrom(from, marketplace, tokenId);
    }

    function getNFTInfo(uint256 tokenId) public view returns (NFTInfo memory) {
        return mintedNFTSInfo[tokenId];
    }

    function landOfOwnerByIndex(address landOwner, uint256 index)
        public
        view
        returns (uint256)
    {
        require(
            index < totalLandOwnedOf(landOwner), // TODO: REPLACE FOR TOTALLANDOWNED OF
            "landowner index out of bounds"
        );

        return ownedLands[landOwner][index];
    }

    function totalLandOwnedOf(address landOwner) public view returns (uint256) {
        return _totalLandOwned[landOwner];
    }

    function totalSpeciesOf(uint256 tokenId) public view returns (uint256) {
        return totalSpecies[tokenId];
    }

    function totalPointsOf(uint256 tokenId) public view returns (uint256) {
        return totalPoints[tokenId];
    }

    /** @dev set all species of a certain land */
    function setSpecies(uint256 tokenId, Species[] memory _species)
        public
        onlyAuthorized
        notBurned(tokenId)
    {
        require(
            totalSpeciesOf(tokenId) == 0,
            "Kolor Land NFT: Species of this land already been set"
        );
        uint256 _totalSpecies = _species.length;
        for (uint256 i = 0; i < _totalSpecies; i++) {
            species[tokenId][i].speciesAlias = _species[i].speciesAlias;
            species[tokenId][i].scientificName = _species[i].scientificName;
            species[tokenId][i].density = _species[i].density;
            species[tokenId][i].size = _species[i].size;
            species[tokenId][i].decimals = _species[i].decimals;
            species[tokenId][i].TCO2perSecond = _species[i].TCO2perSecond;
            species[tokenId][i].TCO2perYear = _species[i].TCO2perYear;
            species[tokenId][i].landId = tokenId;
            species[tokenId][i].creationDate = block.timestamp;
        }

        totalSpecies[tokenId] = _totalSpecies;
    }

    function addSpecies(uint256 tokenId, Species memory _species)
        public
        onlyAuthorized
        notBurned(tokenId)
    {
        uint256 _totalSpecies = totalSpeciesOf(tokenId);
        species[tokenId][_totalSpecies].speciesAlias = _species.speciesAlias;
        species[tokenId][_totalSpecies].scientificName = _species
            .scientificName;
        species[tokenId][_totalSpecies].density = _species.density;
        species[tokenId][_totalSpecies].size = _species.size;
        species[tokenId][_totalSpecies].decimals = _species.decimals;
        species[tokenId][_totalSpecies].TCO2perYear = _species.TCO2perYear;
        species[tokenId][_totalSpecies].landId = tokenId;
        species[tokenId][_totalSpecies].creationDate = block.timestamp;
        species[tokenId][_totalSpecies].TCO2perSecond = _species.TCO2perSecond;

        totalSpecies[tokenId]++;
    }

    function updateSpecies(
        uint256 tokenId,
        uint256 speciesIndex,
        Species memory _species
    ) public onlyAuthorized notBurned(tokenId) {
        require(
            validSpecie(speciesIndex, tokenId),
            "Kolor Land NFT: Invalid specie to update"
        );

        species[tokenId][speciesIndex].speciesAlias = _species.speciesAlias;
        species[tokenId][speciesIndex].scientificName = _species.scientificName;
        species[tokenId][speciesIndex].density = _species.density;
        species[tokenId][speciesIndex].size = _species.size;
        species[tokenId][speciesIndex].TCO2perYear = _species.TCO2perYear;
        species[tokenId][speciesIndex].landId = tokenId;
        species[tokenId][speciesIndex].updateDate = block.timestamp;
        species[tokenId][speciesIndex].TCO2perSecond = _species.TCO2perSecond;
    }

    function setPoints(uint256 tokenId, GeoSpatialPoint[] memory _points)
        public
        onlyAuthorized
        notBurned(tokenId)
    {
        require(
            totalPointsOf(tokenId) == 0,
            "Kolor Land NFT: Geospatial points of this land already been set"
        );
        uint256 _totalPoints = _points.length;

        for (uint256 i = 0; i < _totalPoints; i++) {
            points[tokenId][i].latitude = _points[i].latitude;
            points[tokenId][i].longitude = _points[i].longitude;
            points[tokenId][i].decimals = _points[i].decimals;
            points[tokenId][i].creationDate = block.timestamp;

            totalPoints[tokenId]++;
        }
    }

    function addPoint(uint256 tokenId, GeoSpatialPoint memory point)
        public
        onlyAuthorized
        notBurned(tokenId)
    {
        uint256 _totalPoints = totalPoints[tokenId];

        points[tokenId][_totalPoints].latitude = point.latitude;
        points[tokenId][_totalPoints].longitude = point.longitude;
        points[tokenId][_totalPoints].decimals = point.decimals;

        totalPoints[tokenId]++;
    }

    function updatePoint(
        uint256 tokenId,
        uint256 pointIndex,
        GeoSpatialPoint memory point
    ) public onlyAuthorized notBurned(tokenId) {
        require(
            validPoint(pointIndex, tokenId),
            "Kolor Land NFT: Invalid point to update"
        );

        points[tokenId][pointIndex].latitude = point.latitude;
        points[tokenId][pointIndex].longitude = point.longitude;
        points[tokenId][pointIndex].decimals = point.decimals;
    }

    function validSpecie(uint256 specieIndex, uint256 tokenId)
        internal
        view
        returns (bool)
    {
        if (specieIndex >= 0 && specieIndex < totalSpeciesOf(tokenId)) {
            return true;
        }

        return false;
    }

    function validPoint(uint256 pointIndex, uint256 tokenId)
        internal
        view
        returns (bool)
    {
        if (pointIndex >= 0 && pointIndex < totalPointsOf(tokenId)) {
            return true;
        }

        return false;
    }

    function offsetEmissions(uint256 tokenId, uint256 amount)
        public
        onlyMarketplace
        notBurned(tokenId)
    {
        mintedNFTSInfo[tokenId].soldTCO2 += amount;
    }

    function totalVCUBySpecies(uint256 tokenId, uint256 index)
        public
        view
        returns (uint256)
    {
        // Get the seconds elapsed until now
        uint256 speciesCreationDate = species[tokenId][index].creationDate;

        uint256 secondsElapsed = timestampDifference(
            speciesCreationDate,
            block.timestamp
        );

        // now we get the total vcus emitted until now
        return secondsElapsed * species[tokenId][index].TCO2perSecond;
    }

    function totalVCUSEmitedBy(uint256 tokenId) public view returns (uint256) {
        // Get total species of a land
        uint256 _totalSpecies = totalSpeciesOf(tokenId);

        uint256 totalVCUSEmitted = 0;
        // Iterate over all species and calculate its total vcu
        for (uint256 i = 0; i < _totalSpecies; i++) {
            uint256 currentVCUSEmitted = totalVCUBySpecies(tokenId, i);
            totalVCUSEmitted += currentVCUSEmitted;
        }

        return totalVCUSEmitted;
    }

    /**
        @dev returns vcus emitted from this land that are available
        for sale
    
     */
    function getVCUSLeft(uint256 tokenId)
        public
        view
        override
        returns (uint256)
    {
        // Get the ideal vcutokens from creation date until now
        uint256 totalVCUSEmited = totalVCUSEmitedBy(tokenId);

        // get the difference between the ideal minus the sold TCO2
        return totalVCUSEmited - mintedNFTSInfo[tokenId].soldTCO2;
    }

    function timestampDifference(uint256 timestamp1, uint256 timestamp2)
        public
        pure
        returns (uint256)
    {
        return timestamp2 - timestamp1;
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return
            string(
                abi.encodePacked(baseURI, mintedNFTSInfo[tokenId].identifier)
            );
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}