// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../src/interfaces/IDiamondCut.sol";
import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/OwnershipFacet.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/Diamond.sol";
import "./helpers/DiamondUtils.sol";

import "../src/facets/ERC20Facet.sol";

import "../src/facets/LaunchpadFacet.sol";

import "../src/libraries/LibDiamond.sol";

import "../src/libraries/EventsAndErrors.sol";

import "../src/interfaces/IUniswapV2Router.sol";
import "../src/facets/MockUniswapRouter.sol";

import {console} from "forge-std/console.sol";

contract LaunchpadFacetTest is Test, IDiamondCut, DiamondUtils {
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    TokenFacet erc20Facet;
    LaunchpadFacet launchpadFacet;
    MockUniswapV2Router mockRouter;

    TokenFacet usdc;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    // address ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address ROUTER_ADDRESS;

    // function makeAddr(string memory name) internal pure returns (address) {
    //     return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    // }

    function setUp() public {
        // Deploy usdc token for test
        usdc = new TokenFacet("USDC Token", "USDC", address(this));
        mockRouter = new MockUniswapV2Router();
        ROUTER_ADDRESS = address(mockRouter);

        // Deploy Diamond with actual token addresses
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(
            address(this),
            address(dCutFacet),
            address(usdc),
            address(ROUTER_ADDRESS)
        );

        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        launchpadFacet = new LaunchpadFacet();
        mockRouter = new MockUniswapV2Router();

        // Diamond facets setup
        FacetCut[] memory cut = new FacetCut[](4);
        cut[0] = FacetCut({
            facetAddress: address(dLoupe),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondLoupeFacet")
        });
        cut[1] = FacetCut({
            facetAddress: address(ownerF),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("OwnershipFacet")
        });
        cut[2] = FacetCut({
            facetAddress: address(launchpadFacet),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("LaunchpadFacet")
        });
        cut[3] = FacetCut({
            facetAddress: address(mockRouter),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("MockUniswapV2Router")
        });
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        // Mint initial tokens
        TokenFacet(address(usdc)).mint(address(this), 1000000e18);
    }

    //  ------------------------------------------- CAMPAIGN FUNCTIONS TESTS ------------------------------------

    function testDiamondDeployment() public {
        address[] memory facets = DiamondLoupeFacet(address(diamond))
            .facetAddresses();
        assertEq(facets.length, 5);
    }

    function testTokenInitialization() public {
        assertEq(TokenFacet(address(usdc)).name(), "USDC Token");
    
        assertEq(
            TokenFacet(address(usdc)).balanceOf(address(this)),
            1000000e18
        );
    }

    function testCreateCampaign() public {
        // Transfer SAFU to user1
        TokenFacet(address(usdc)).transfer(user1, 1000e18);

        // Approve diamond from user1
        vm.prank(user1);
        TokenFacet(address(usdc)).approve(address(diamond), 1000e18);

        // Deposit to pool from user1
        vm.prank(user1);
        assertEq(
            TokenFacet(address(usdc)).balanceOf(user1),
            1000e18
        );

        // Create a campaign
        vm.prank(user1);
        LaunchpadFacet(payable(address(diamond))).createCampaign(
            "VALHALLA",
            "VLH",
            5000e6,
            10000
        );

        // Get campaign details
        (
            address creator,
            uint256 targetFunding,
            uint256 currentFunding,
            uint256 tokensSold,
            address tokenAddress,
            bool active,
            bool fundingComplete,
            string memory name,
            uint32 reserveRatio
        ) = LaunchpadFacet(payable(address(diamond))).getCampaignDetails(1);

        // Assertions based on the returned details
        assertEq(creator, user1); // Check if the creator is user1
        assertEq(targetFunding, 5000e6); // Check target funding
        assertEq(currentFunding, 0); // Check current funding (should be 0 initially)
        assertEq(tokensSold, 0); // Check tokens sold (should be 0 initially)
        // assertEq(tokenAddress, ); // Check the token address used
        assertTrue(tokenAddress != address(0));
        assertTrue(active); // Check if the campaign is active
        assertFalse(fundingComplete); // Check if funding is not complete
        assertEq(name, "VALHALLA"); // Check the campaign name
        assertEq(reserveRatio, 10000); // Check the reserve ratio

        TokenFacet campaignToken = TokenFacet(tokenAddress);
        assertEq(campaignToken.name(), "VALHALLA");
        assertEq(campaignToken.symbol(), "VLH");
    }

    function testBuyInToLaunchpadCampaign() public {
        // Transfer USDC to user2
        TokenFacet(address(usdc)).transfer(user2, 1000e6);

        // Approve diamond from user2
        vm.prank(user2);
        TokenFacet(address(usdc)).approve(address(diamond), 1000e6);

        vm.prank(user2);
        assertEq(TokenFacet(address(usdc)).balanceOf(user2), 1000e6);

        // Create a campaign
        vm.prank(user1);
        LaunchpadFacet(payable(address(diamond))).createCampaign(
            "VALHALLA",
            "VLH",
            5000e6,
            10000
        );

        // Calculate tokens to mint (before buyIn)
        uint256 tokensToMint = LaunchpadFacet(payable(address(diamond))).getTokensToMint(
            500_000_000 * 10**18, // TOKENS_FOR_SALE
            0,                    // Initial reserveBalance
            10000,                // reserveRatio
            100e6                 // Match buyIn
        );

        // Buy in to the campaign
        vm.prank(user2);
        LaunchpadFacet(payable(address(diamond))).buyIn(1, 100e6);

        // Get campaign details
        (
            ,
            ,
            uint256 amountRaised,
            uint256 tokensSold,
            address tokenAddress,
            ,
            ,
            ,
        ) = LaunchpadFacet(payable(address(diamond))).getCampaignDetails(1);

        // Assertions
        assertEq(amountRaised, 100e6);      // 100 USDC
        assertEq(tokensSold, tokensToMint); // Should be 100e18
        assertEq(TokenFacet(address(tokenAddress)).balanceOf(user2), tokensToMint);
    }

    function testPayOutCampaign() public {
        // Transfer USDC to user2
        TokenFacet(address(usdc)).transfer(user2, 10000e6);

        // Approve diamond from user2
        vm.prank(user2);
        TokenFacet(address(usdc)).approve(address(diamond), 10000e6);

        vm.prank(user2);
        assertEq(TokenFacet(address(usdc)).balanceOf(user2), 10000e6);

        // Create a campaign
        vm.prank(user1);
        LaunchpadFacet(payable(address(diamond))).createCampaign(
            "VALHALLA",
            "VLH",
            5000e6,
            10000
        );

        // Buy in to the campaign
        vm.prank(user2);
        LaunchpadFacet(payable(address(diamond))).buyIn(1, 5000e6);

        // Get campaign details
        (
            address creator,
            uint256 targetAmount,
            uint256 amountRaised,
            uint256 tokensSold,
            address tokenAddress,
            bool isActive,
            bool isFundingComplete,
            ,
        ) = LaunchpadFacet(payable(address(diamond))).getCampaignDetails(1);

        // Assertions
        assertEq(amountRaised, 5000e6);
        assertEq(tokensSold, 500_000_000 * 10**18);
        assertEq(isActive, false);
        assertEq(isFundingComplete, true);
        assertEq(TokenFacet(address(tokenAddress)).balanceOf(creator), 200_000_000 * 10**18);
        assertEq(TokenFacet(address(usdc)).balanceOf(creator), targetAmount / 2);
        assertEq(TokenFacet(address(tokenAddress)).balanceOf(address(diamond)), 50_000_000 * 10**18);


    }

    


    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}
}
