// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibEventsAndErrors {
    error ZeroValueNotAllowed();
    error ReserveRatioOutOfBounds();
    error CampaignInactive();
    error FundingAlreadyCompleted();
    error FundingNotMet();
    error InvalidParameters();
    error NotCampaignOwner();
    error NotEnoughTokens();
    error InsufficientFunds();
    error AddressZeroDetected();

    event CampaignCreated(uint256 indexed campaignId, address indexed creator, string name, uint256 targetFunding);
    event TokensPurchased(
        uint256 indexed campaignId, address indexed buyer, uint256 usdcAmount, uint256 tokensReceived
    );
    event FundingCompleted(uint256 indexed campaignId, uint256 totalFunding);
    event LiquidityAdded(uint256 indexed campaignId, uint256 usdcAmount, uint256 tokensAmount);
}
