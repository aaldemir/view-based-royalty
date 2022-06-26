// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

/*
TODO:
    - all royalty recipients set on a token should be able to view the respective token's URI
    - accept stable coin payments (need users to approve this contract on the stable coin ERC20)
    - allocation percentage < 10% creates issues during _calculateRoyaltyToRecipient
*/

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PayPerView is ERC721 {
    using SafeMath for uint;
    using SafeMath for uint16;

    // map address to tokenId to expiration time
    mapping(address => mapping(uint => uint)) public viewExpiration;
    // map a token to recipients
    mapping(uint => address[]) public royaltyRecipientsByToken;
    // map allocation of royalty to recipients
    // in hundredths of a percent (1.5% is stored as 150)
    mapping(uint => mapping(address => uint16)) public allocationOfRoyalties;

    // each _id has its own duration
    mapping(uint => uint) private _viewDuration;
    // each _id has its own price to view
    // what denomination will this amount be? will it be USD in pennies? will the msg.value get converted to USD pennies before checking
    mapping(uint => uint) private _amountToView;
    // amount of royalty redeemable by an address for each token
    // tokenId => address => amount redeemable
    mapping(uint => mapping(address => uint)) private _redeemableRoyalty;
    // mapping of tokenId to bytes32 of the token URI
    // there is nothing stopping from someone viewing this in storage
    mapping (uint => string) private _concealedTokenURI;
    // map address to token ids it can redeem from
    // what if an address is removed from an allocation? or set allocation to zero
    mapping(address => uint[]) private _tokensAddressCanRedeemFrom;

    uint public tokenCount = 0;
    uint private constant AGGREGATE_ALLOCATION = 10000;
    uint32 private _defaultViewDuration;
    uint private _defaultAmountToView;

    constructor() ERC721("PayPerView", "PPV") {
        // default duration is 1 week
        _defaultViewDuration = 604800;

        // use .1 ETH for now
        _defaultAmountToView = 1*10**17;
    }

    /** PUBLIC FUNCTIONS */

    /**
    * View the total length of time in seconds a token is viewable per payment
    * and how much it costs to view the token.
    *
    * @param _id {uint} tokenId
    */
    function viewingDetailsFor(uint _id) public view returns(uint viewDuration, uint amountToView) {
        return (_viewDuration[_id], _amountToView[_id]);
    }

    /**
    * Checks if an address can view a token.
    * An address can view if approved, is owner, or has access through royalty payment.
    *
    * @param viewer {address}
    * @param _id {uint} tokenId
    */
    function canView(address viewer, uint _id) public view returns(bool) {
        require(_exists(_id), "token does not exist");
        return _canView(viewer, _id);
    }

    /**
    * Checks if an address can view a token.
    *
    * @param viewer {address}
    * @param _id {uint} tokenId
    */
    function addViewer(address viewer, uint _id) public payable {
        require(_exists(_id), "_id does not exist");
        _requireAmountIsEnoughToView(_id);
        for (uint8 i = 0; i < royaltyRecipientsByToken[_id].length; i++) {
            address recipient = royaltyRecipientsByToken[_id][i];
            _redeemableRoyalty[_id][recipient] = _redeemableRoyalty[_id][recipient].add(_calculateRoyaltyToRecipient(_id, msg.value, recipient));
        }
        // set the expiration time for when the viewer can no longer view the _id
        // should be the current time stamp plus the view duration
        viewExpiration[viewer][_id] = block.timestamp.add(_viewDuration[_id]);
    }

    /**
    * Retrieve URI for token.
    * msg.sender must be able to view the token.
    *
    * @param _id {uint} tokenId
    */
    function viewTokenConcealedURI(uint _id) public view returns(string memory){
        require(_exists(_id), "_id does not exist");
        require(_canView(msg.sender, _id), "can not view");
        return _concealedTokenURI[_id];
    }

    /**
    * Set the length of time a royalty payee can view the token.
    *
    * @param _id {uint} tokenId
    * @param _duration {uint} duration of time in seconds
    */
    function setViewDuration(uint _id, uint _duration) public {
        require(_exists(_id), "_id does not exist");
        require(_isApprovedOrOwner(msg.sender, _id), "not approved or owner");
        _setViewDuration(_id, _duration);
    }

    /**
    * Set the amount royalty payee must pay to view the token.
    *
    * @param _id {uint} tokenId
    * @param _amount {uint} in cents of $USD dollars
    */
    function setAmountToView(uint _id, uint _amount) public {
        require(_exists(_id), "_id does not exist");
        // what is the denomination of _amount? pennies in USD?
        require(_isApprovedOrOwner(msg.sender, _id), "not approved or owner");
        _setAmountToView(_id, _amount);
    }

    /**
    * Initiate a transaction to pull funds redeemable by msg.sender
    * for the given tokenId.
    *
    * @param _id {uint} tokenId
    */
    function redeemRoyalty(uint _id) public {
        require(_exists(_id), "_id does not exist");
        uint sendValue = _redeemableRoyalty[_id][msg.sender];
        require(sendValue != 0, "no send value");
        _redeemableRoyalty[_id][msg.sender] = 0;
        bool success = payable(msg.sender).send(sendValue);
        require(success, "failed to redeem");
    }

    /**
    * Set the addresses which can redeem royalties for a given token
    * and the percentage of royalties each address should be allocated.
    *
    * Everytime an allocation percentage or a user is to be changed,
    * pass this function a set of the values to use going forward
    * (rewrite as opposed to edit)
    *
    * @param _id {uint} tokenId
    * @param _recipients {address[]} addresses which can redeem royalties
    * @param _allocationPercentages {uint16[]} allocations in hundredths of a percent (aggregate should be 100000)
    */
    function setRoyaltyRecipients(uint _id, address[] calldata _recipients, uint16[] calldata _allocationPercentages) public {
        require(_exists(_id), "token does not exist");
        require(_isApprovedOrOwner(msg.sender, _id), "not approved or owner");
        require(_recipients.length == _allocationPercentages.length, "recipients and allocations are not same length");
        uint total = 0;
        for (uint i = 0; i < _allocationPercentages.length; i++) {
            address recipient = _recipients[i];
            require(recipient != address(0));
            require(_allocationPercentages[i] > 1000);
            allocationOfRoyalties[_id][recipient] = _allocationPercentages[i];
            if (!_canAddressRedeemFromToken(_id, recipient)) {
                // to list of tokens address can redeem from
                // check if token _id is in list to avoid duplicates
                _tokensAddressCanRedeemFrom[recipient].push(_id);
            }
            total = total.add(_allocationPercentages[i]);
        }
        royaltyRecipientsByToken[_id] = _recipients;
        require(total == AGGREGATE_ALLOCATION, "allocations do not add up to 100%");
    }

    /**
    * Mint a token using the custom view duration and amount values.
    *
    * @param _tokenURI {string} token URI should be concealed (encrypted)
    * @param _duration {uint256} length of time in seconds a viewer can access
    * @param _amount {uint256} amount required to view
    * @param _recipients {address[]} addresses which can redeem royalties
    * @param _allocationPercentages {uint16[]} allocations in hundredths of a percent (aggregate should be 100000)
    */
    function mintWithCustomParams(string memory _tokenURI, uint _duration, uint _amount, address[] calldata _recipients, uint16[] calldata _allocationPercentages) public {
        tokenCount = tokenCount.add(1);
        _mint(msg.sender, tokenCount);
        _setViewDuration(tokenCount, _duration);
        _setAmountToView(tokenCount, _amount);
        _concealedTokenURI[tokenCount] = _tokenURI;
        setRoyaltyRecipients(tokenCount, _recipients, _allocationPercentages);
    }

    /** EXTERNAL FUNCTIONS */

    /**
    * Mint a token using the default view duration and amount values.
    *
    * @param _tokenURI {string} token URI
    * @param _recipients {address[]} addresses which can redeem royalties
    * @param _allocationPercentages {uint16[]} allocations in hundredths of a percent (aggregate should be 100000)
    */
    function mintWithDefaultParams(string memory _tokenURI, address[] calldata _recipients, uint16[] calldata _allocationPercentages) external {
        mintWithCustomParams(_tokenURI, _defaultViewDuration, _defaultAmountToView, _recipients, _allocationPercentages);
    }

    function totalRoyaltyCollected(uint _id) external view returns(uint) {
        require(_exists(_id), "_id does not exist");
        uint total = 0;
        for (uint8 i = 0; i < royaltyRecipientsByToken[_id].length; i++) {
            address recipient = royaltyRecipientsByToken[_id][i];
            total = total.add(_redeemableAmountForRecipientByToken(_id, recipient));
        }
        return total;
    }

    function redeemableRoyaltyPerToken(uint _id) external view returns(uint) {
        return _redeemableAmountForRecipientByToken(_id, msg.sender);
    }

    function getTokenIdsAddressCanRedeemFrom() external view returns(uint[] memory) {
        return _tokensAddressCanRedeemFrom[msg.sender];
    }

    /** PRIVATE FUNCTION */

    function _canAddressRedeemFromToken(uint _id, address recipient) private view returns(bool) {
        uint[] memory tokenIds = _tokensAddressCanRedeemFrom[recipient];
        for (uint i = 0; i < tokenIds.length; i++) {
            if (_id == tokenIds[i]) {
                return true;
            }
        }
        return false;
    }

    function _setViewDuration(uint _id, uint _duration) private {
        _viewDuration[_id] = _duration;
    }

    function _setAmountToView(uint _id, uint _amount) private {
        require(_amount >= 100, "amount must be greater than 100 wei");
        _amountToView[_id] = _amount;
    }

    function _requireAmountIsEnoughToView(uint _id) private view {
        require(msg.value >= _amountToView[_id], "insufficient value");
    }

    function _canView(address viewer, uint _id) private view returns(bool) {
        uint currentViewExpiration = viewExpiration[viewer][_id];
        return _isApprovedOrOwner(viewer, _id) || currentViewExpiration > block.timestamp;
    }

    function _calculateRoyaltyToRecipient(uint _id, uint amount, address recipient) private view returns(uint) {
        uint portion = allocationOfRoyalties[_id][recipient].mul(10).div(AGGREGATE_ALLOCATION);
        return amount.div(10).mul(portion);
    }

    function _redeemableAmountForRecipientByToken(uint _id, address recipient) private view returns(uint) {
        return _redeemableRoyalty[_id][recipient];
    }

    // TODO: remove
    function getTokenURI(uint _id) external view returns(string memory) {
        return _concealedTokenURI[_id];
    }
}
