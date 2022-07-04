// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

/*
TODO:
    - set amount to view value in USD
    - accept stable coin payments (need users to approve this contract on the stable coin ERC20)
    -   need to create a new addViewer that calls transferFrom on the stable's ERC20
    - all royalty recipients set on a token should be able to view the respective token's URI
    - add events:
    - allocation percentage < 10% creates issues during _calculateRoyaltyToRecipient
*/

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

contract PayPerView is ERC721 {
    using SafeMath for int;
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
    // each _id has its own price to view in USD pennies
    mapping(uint => uint64) private _amountToView;
    // amount of royalty redeemable by an address for each token
    // tokenId => address => amount redeemable
    mapping(uint => mapping(address => uint)) private _redeemableRoyalty;
    // mapping of tokenId to bytes32 of the token URI
    // there is nothing stopping from someone viewing this in storage
    mapping (uint => string) private _concealedTokenURI;
    // map address to token ids it can redeem from
    // what if an address is removed from an allocation? or set allocation to zero
    mapping(address => uint[]) private _tokensAddressCanRedeemFrom;

    AggregatorV3Interface internal priceFeed;
    uint private constant AGGREGATE_ALLOCATION = 10000;
    address private DEPLOYER;
    uint public tokenCount = 0;
    uint32 private _defaultViewDuration;
    uint16 private _defaultAmountToViewUSD;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        DEPLOYER = msg.sender;

        // set default default price to $5
        _defaultAmountToViewUSD = 500;

        // default duration is 1 week
        _defaultViewDuration = 604800;
    }

    function init(address _priceFeed) external {
        require(msg.sender == DEPLOYER, "only deployer can init");
        // AVAX-main AVAX/USD 0x0A77230d17318075983913bC2145DB16C7366156
        // AVAX-test AVAX/USD 0x5498BB86BC934c8D34FDA08E81D444153d0D06aD
        // AVAX-main USDC/USD 0xF096872672F44d6EBA71458D74fe67F9a77a23B9
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /** PRICE RELATED FUNCTIONS */

    /**
    * View the total length of time in seconds a token is viewable per payment
    * and how much it costs to view the token.
    *
    * @param dollars {uint16} dollars in pennies (1000 === $10)
    */
    function convertDollarsToNanoAvax(uint64 dollars) public view returns (uint) {
        uint price = uint(getLatestPrice());
        uint factoredDollars = uint(dollars) * 1e15;
        // returns value with 9 decimal places (last number rounded)
        return factoredDollars.div(price);
    }

    function getLatestPrice() public view returns (int) {
        // AVAX/USD returns value with 8 decimal places
        (,int price,,,) = priceFeed.latestRoundData();
        return price;
    }

    /** PUBLIC FUNCTIONS */

    /**
    * View the total length of time in seconds a token is viewable per payment
    * and how much it costs to view the token.
    *
    * @param _id {uint} tokenId
    */
    function viewingDetailsFor(uint _id) public view returns(uint viewDuration, uint64 amountToView) {
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
    * Adds a viewer by taking payment with the gas paying asset.
    * Allocates amounts to recipients based on allocation percentages.
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
    * Adds a viewer by taking payment with a stable coin.
    * Allocates amounts to recipients based on allocation percentages.
    *
    * @param viewer {address}
    * @param _id {uint} tokenId
    */
    function addViewerWithStable(address viewer, uint _id, address stable) external {
        require(_exists(_id), "_id does not exist");
        IERC20Metadata stableContract = IERC20Metadata(stable);
        uint8 decimals = stableContract.decimals();
        uint adjustedAmountToView = _amountToView[_id] * 10**(decimals - 2);
        stableContract.transferFrom(msg.sender, address(this), adjustedAmountToView);

        // allocate to recipients based on percentages
        for (uint8 i = 0; i < royaltyRecipientsByToken[_id].length; i++) {
            address recipient = royaltyRecipientsByToken[_id][i];
            _redeemableRoyalty[_id][recipient] = _redeemableRoyalty[_id][recipient].add(_calculateStableRoyaltyToRecipient(_id, adjustedAmountToView, recipient));
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
    * @param _amount {uint16} in cents of $USD dollars
    */
    function setAmountToView(uint _id, uint16 _amount) public {
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
    function setRoyaltyRecipients(uint _id, address[] memory _recipients, uint16[] memory _allocationPercentages) public {
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
     * @param _amount {uint64} amount required to view in USD pennies
     * @param _recipients {address[]} addresses which can redeem royalties
     * @param _allocationPercentages {uint16[]} allocations in hundredths of a percent (aggregate should be 100000)
    */
    function mintWithCustomParams(string memory _tokenURI, uint _duration, uint64 _amount, address[] memory _recipients, uint16[] memory _allocationPercentages) public returns(uint) {
        tokenCount = tokenCount.add(1);
        _mint(msg.sender, tokenCount);
        _setViewDuration(tokenCount, _duration);
        _setAmountToView(tokenCount, _amount);
        _concealedTokenURI[tokenCount] = _tokenURI;
        setRoyaltyRecipients(tokenCount, _recipients, _allocationPercentages);
        return tokenCount;
    }

    /**
     * Mint a token using the default view duration and amount values.
     *
     * @param _tokenURI {string} token URI
     * @param _recipients {address[]} addresses which can redeem royalties
     * @param _allocationPercentages {uint16[]} allocations in hundredths of a percent (aggregate should be 100000)
    */
    function mintWithDefaultParams(string memory _tokenURI, address[] memory _recipients, uint16[] memory _allocationPercentages) public returns(uint) {
        return mintWithCustomParams(_tokenURI, _defaultViewDuration, _defaultAmountToViewUSD, _recipients, _allocationPercentages);
    }

    /** EXTERNAL FUNCTIONS */

    /**
     * Mint a token by setting the sender as the sole recipient of royalties
     * using default token view price and duration params.
     *
     * @param _tokenURI {string} token URI
     */
    function mint(string memory _tokenURI) external returns(uint) {
        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        uint16[] memory allocations = new uint16[](1);
        allocations[0] = 10000;
        return mintWithDefaultParams(_tokenURI, recipients, allocations);
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

    function _setAmountToView(uint _id, uint64 _amount) private {
        require(_amount >= 100, "amount must be greater than 100 USD pennies");
        _amountToView[_id] = _amount;
    }

    function _requireAmountIsEnoughToView(uint _id) private view {
        if (msg.value > 0) {
            // TODO: use price feed
            require(msg.value >= convertDollarsToNanoAvax(_amountToView[_id]), "insufficient value");
        }
    }

    function _canView(address viewer, uint _id) private view returns(bool) {
        uint currentViewExpiration = viewExpiration[viewer][_id];
        return _isApprovedOrOwner(viewer, _id) || currentViewExpiration > block.timestamp;
    }

    function _calculateStableRoyaltyToRecipient(uint _id, uint adjustedAmount, address recipient) private view returns (uint) {
        // amountToView adjusted to stable decimals * recipient allocation / aggregate_allocation
        return adjustedAmount.mul(allocationOfRoyalties[_id][recipient]).div(AGGREGATE_ALLOCATION);
    }

    function _calculateRoyaltyToRecipient(uint _id, uint amount, address recipient) private view returns(uint) {
        // given aggregate is 10000
        // if allocation is 1000 * factor=10 / 10000
        // if allocation is 100 * factor=100 / 10000
        // if allocation is 10 (0.1%) * factor=1000 / 10000 then divide by 1000
        uint8 factor = 10;
        uint portion = allocationOfRoyalties[_id][recipient].mul(factor).div(AGGREGATE_ALLOCATION);
        return amount.div(factor).mul(portion);
    }

    function _redeemableAmountForRecipientByToken(uint _id, address recipient) private view returns(uint) {
        return _redeemableRoyalty[_id][recipient];
    }

    // TODO: remove
    function getTokenURI(uint _id) external view returns(string memory) {
        return _concealedTokenURI[_id];
    }
}
