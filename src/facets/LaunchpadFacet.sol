// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/ReentrancyGuard.sol";
import "../libraries/CustomLib.sol";
import "../libraries/EventsAndErrors.sol";
import "../libraries/Ownable.sol";
import "../libraries/SafeErc20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/PowerLib.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IUniswapV2Router.sol";
import "./ERC20Facet.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/**
 * @title Launchpad
 * @dev A fundraising platform implementing the Bancor bonding curve
 * This contract allows project creators to raise funds with a bonding curve model
 * where early investors are incentivized over later investors
*/
contract LaunchpadFacet is ReentrancyGuard, Power {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens
    uint256 public constant TOKENS_FOR_SALE = 500_000_000 * 10**18; // 500 million tokens
    uint256 public constant CREATOR_ALLOCATION = 200_000_000 * 10**18; // 200 million tokens
    uint256 public constant LIQUIDITY_ALLOCATION = 250_000_000 * 10**18; // 250 million tokens
    uint256 public constant PLATFORM_FEE_TOKENS = 50_000_000 * 10**18; // 50 million tokens
    uint32 private constant MAX_RESERVE_RATIO = 1000000;

    
    /**
     * @dev Create a new fundraising campaign
     * @param _name Name of the token
     * @param _symbol Symbol of the token
     * @param _targetFunding Total funding goal in USDC (with 6 decimals)
     * @param _reserveRatio Bancor reserve ratio (between 0-1000000 representing 0-100%)
     */
    function createCampaign(
        string memory _name,
        string memory _symbol,
        uint256 _targetFunding,
        uint32 _reserveRatio
    ) external {

        LibDiamond.DiamondStorage storage diamond = LibDiamond.diamondStorage();

        if (msg.sender == address(0)) revert LibEventsAndErrors.AddressZeroDetected();
        if (_targetFunding == 0) revert LibEventsAndErrors.ZeroValueNotAllowed();
        if (_reserveRatio < 0 && _reserveRatio > MAX_RESERVE_RATIO) revert LibEventsAndErrors.ReserveRatioOutOfBounds();
        
        // Create new token for the campaign
        TokenFacet campaignToken = new TokenFacet(_name, _symbol, address(this));
        
        // Store campaign info
        uint256 campaignCount = diamond.campaignCount;
        uint256 campaignId = campaignCount + 1;

        diamond.campaigns[campaignId] = LibDiamond.Campaign({
            creator: msg.sender,
            targetAmount: _targetFunding,
            amountRaised: 0,
            tokensSold: 0,
            feeBank: 0,
            token: campaignToken,
            isActive: true,
            isFundingComplete: false,
            name: _name,
            reserveRatio: _reserveRatio
        });
        
        diamond.campaignCount++;
        
        emit LibEventsAndErrors.CampaignCreated(campaignId, msg.sender, _name, _targetFunding);
    }
    
    /**
     * @dev Purchase tokens using the bonding curve formula
     * @param _campaignId ID of the campaign
     * @param _usdcAmount Amount of USDC to spend
     */
    function buyIn(uint256 _campaignId, uint256 _usdcAmount) external nonReentrant {

        LibDiamond.DiamondStorage storage diamond = LibDiamond.diamondStorage();
        
        LibDiamond.Campaign storage campaign = diamond.campaigns[_campaignId];

        if (msg.sender == address(0)) revert LibEventsAndErrors.AddressZeroDetected();
        if (_usdcAmount == 0) revert LibEventsAndErrors.ZeroValueNotAllowed();
        if (!campaign.isActive) revert LibEventsAndErrors.CampaignInactive();
        if (campaign.isFundingComplete) revert LibEventsAndErrors.FundingAlreadyCompleted();
        if (diamond.usdcToken.balanceOf(msg.sender) < _usdcAmount) revert LibEventsAndErrors.InsufficientFunds();
        
        // Calculate tokens based on Bancor's bonding curve
        uint256 tokensToMint = _calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            campaign.amountRaised,
            campaign.reserveRatio,
            _usdcAmount
        );

        // Check if this purchase would exceed the tokens for sale
        if (campaign.tokensSold + tokensToMint > TOKENS_FOR_SALE) {

            uint256 remainingTokens = TOKENS_FOR_SALE - campaign.tokensSold;

            // Quadratic curve: F(x) = (targetUSDC * 10^6 * x^2) / (TOKENS_FOR_SALE^2)
            uint256 currentUsdc = (campaign.targetAmount * 10**6 * (campaign.tokensSold ** 2)) / (TOKENS_FOR_SALE ** 2);
            uint256 targetUsdc = campaign.targetAmount * 10**6;

            uint256 usdcNeeded = targetUsdc - currentUsdc;

            // Adjust tokens and USDC
            tokensToMint = remainingTokens;
            _usdcAmount = usdcNeeded;

        }
        
        // Update campaign state
        campaign.amountRaised = campaign.amountRaised.add(_usdcAmount);
        campaign.tokensSold = campaign.tokensSold.add(tokensToMint);
        
        IERC20(diamond.usdcToken).safeTransferFrom(msg.sender, address(this), _usdcAmount); // pay

        TokenFacet(address(campaign.token)).mint(msg.sender, tokensToMint); // mint token to buyer
        
        emit LibEventsAndErrors.TokensPurchased(_campaignId, msg.sender, _usdcAmount, tokensToMint);
        
        // Check if funding is complete
        if (campaign.tokensSold >= TOKENS_FOR_SALE) {
            _payOut(_campaignId);
        }
    }
    
    /**
     * @dev Calculate purchase return using Bancor formula
     * Formula: Return = _supply * ((1 + _depositAmount / _reserveBalance) ^ (_reserveRatio / MAX_RESERVE_RATIO) - 1)
     * @param _supply Continuous token total supply (in our case, TOKENS_FOR_SALE)
     * @param _reserveBalance Current reserve token balance
     * @param _reserveRatio Reserve ratio, represented in ppm, 1-1000000
     * @param _depositAmount Deposit amount in reserve token
     * @return purchase return amount
     */
    function _calculatePurchaseReturn(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveRatio,
        uint256 _depositAmount
    ) internal view returns (uint256) {
        // Validate input
        require(_supply > 0 && _reserveRatio > 0 && _reserveRatio <= MAX_RESERVE_RATIO, "Invalid parameters");
        
        if (_depositAmount == 0) {
            return 0;
        }
        
        // ------------------------------------------------------------------------ Prod

        // If reserve balance is 0 = first buy
        // if (_reserveBalance == 0) {
        //     // For the very first purchase, use linear pricing
        //     return _depositAmount * 10**12;
        // }
        
        // ------------------------------------------------------------------------ Prod


        // ------------------------------------------------------------------------ only for testing purposes


        // ------------------------------------------------------------------------ only for testing purposes

        if (_reserveBalance == 0) {
            return _depositAmount.mul(10**17); // 5000e6 USDC = 500_000_000 * 10**18 tokens
        }
        // ------------------------------------------------------------------------ only for testing purposes

        
        // Special case if the ratio = 100%
        if (_reserveRatio == MAX_RESERVE_RATIO) {
            return _supply.mul(_depositAmount).div(_reserveBalance);
        }
        
        // Calculate using the power function
        uint256 result;
        uint8 precision;
        uint256 baseN = _depositAmount + _reserveBalance;
        (result, precision) = Power.power(baseN, _reserveBalance, _reserveRatio, MAX_RESERVE_RATIO);
        uint256 newTokenSupply = _supply.mul(result).div(1 << precision);
        return newTokenSupply - _supply;
    }

    function getTokensToMint(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveRatio,
        uint256 _depositAmount
    ) external view returns (uint256) {
        return _calculatePurchaseReturn(
        _supply,
        _reserveBalance,
        _reserveRatio,
        _depositAmount);
    }
    
    /**
     * @dev Complete the funding process, distribute tokens and USDC
     * @param _campaignId ID of the campaign
     */
    function _payOut(uint256 _campaignId) internal {

        LibDiamond.DiamondStorage storage diamond = LibDiamond.diamondStorage();
        LibDiamond.Campaign storage campaign = diamond.campaigns[_campaignId];

        if (!campaign.isActive) revert LibEventsAndErrors.CampaignInactive();
        if (campaign.isFundingComplete) revert LibEventsAndErrors.FundingAlreadyCompleted();
        
        // Mark campaign as complete
        campaign.isActive = false;
        campaign.isFundingComplete = true;
        campaign.feeBank = PLATFORM_FEE_TOKENS;
        
        // Calculate distribution amounts
        uint256 creatorFunding = campaign.amountRaised.div(2); // 50% of funds
        uint256 liquidityFunding = campaign.amountRaised.sub(creatorFunding); // Remaining 50%
        
        // Mint tokens for creator
        TokenFacet(address(campaign.token)).mint(campaign.creator, CREATOR_ALLOCATION);

        // Mint platform fee tokens
        TokenFacet(address(campaign.token)).mint(address(this), PLATFORM_FEE_TOKENS);
        
        // Transfer USDC to creator
        IERC20(diamond.usdcToken).safeTransfer(campaign.creator, creatorFunding);
        
        // Add liquidity to Uniswap
        _addLiquidity(_campaignId, liquidityFunding);
        
        emit LibEventsAndErrors.FundingCompleted(_campaignId, campaign.amountRaised);
    }
    
    /**
     * @dev Add liquidity to Uniswap
     * @param campaignId ID of the campaign
     * @param usdcAmount Amount of USDC for liquidity
     */
    function _addLiquidity(uint256 campaignId, uint256 usdcAmount) internal {
        LibDiamond.DiamondStorage storage diamond = LibDiamond.diamondStorage();

        LibDiamond.Campaign storage campaign = diamond.campaigns[campaignId];
        
        // Mint tokens for liquidity
        TokenFacet(address(campaign.token)).mint(address(this), LIQUIDITY_ALLOCATION);
        
        // Approve tokens for Uniswap router
        require(IERC20(diamond.usdcToken).approve(address(diamond.uniswapRouter), usdcAmount), "approve failed.");
        require(IERC20(address(campaign.token)).approve(address(diamond.uniswapRouter), LIQUIDITY_ALLOCATION), "approve failed.");
        
        // Add liquidity
        diamond.uniswapRouter.addLiquidity(
            address(diamond.usdcToken),
            address(campaign.token),
            usdcAmount,
            LIQUIDITY_ALLOCATION,
            0, // min USDC
            0, // min tokens
            campaign.creator, // LP tokens recipient
            block.timestamp + 1800 // deadline
        );
        
        emit LibEventsAndErrors.LiquidityAdded(campaignId, usdcAmount, LIQUIDITY_ALLOCATION);
    }
    
    /**
     * @dev Get campaign details
     * @param campaignId ID of the campaign
     * @return creator Address of the campaign creator
     * @return targetAmount Total funding goal in USDC
     * @return amountRaised Current funding amount in USDC
     * @return tokensSold Total tokens sold
     * @return tokenAddress Address of the token for the campaign
     * @return isActive Whether the campaign is active
     * @return isFundingComplete Whether the funding is complete
     * @return name Name of the token
     * @return reserveRatio Bancor reserve ratio
     */
    function getCampaignDetails(uint256 campaignId) external view returns (
        address creator,
        uint256 targetAmount,
        uint256 amountRaised,
        uint256 tokensSold,
        address tokenAddress,
        bool isActive,
        bool isFundingComplete,
        string memory name,
        uint32 reserveRatio
    ) {
        LibDiamond.DiamondStorage storage diamond = LibDiamond.diamondStorage();
        LibDiamond.Campaign storage campaign = diamond.campaigns[campaignId];

        return (
            campaign.creator,
            campaign.targetAmount,
            campaign.amountRaised,
            campaign.tokensSold,
            address(campaign.token),
            campaign.isActive,
            campaign.isFundingComplete,
            campaign.name,
            campaign.reserveRatio
        );
    }
    
    /**
     * @dev Owner can withdraw platform fees
     * @param _token Address of the token to withdraw
     */
    function withdrawPlatformFees(address _token) external {
        LibDiamond.enforceIsContractOwner();
        if (_token == address(0)) {
            // Withdraw ETH (if any)
            (bool success, ) = msg.sender.call{value: address(this).balance}("");
            require(success, "ETH transfer failed");
        } else {
            // IERC20 tokenContract = IERC20(token);
            IERC20 tokenContract = IERC20(_token);
            uint256 balance = tokenContract.balanceOf(address(this));

            IERC20(tokenContract).safeTransfer(msg.sender, balance);
        }
    }
    
    receive() external payable {}
}