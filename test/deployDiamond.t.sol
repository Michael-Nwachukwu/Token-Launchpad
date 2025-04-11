// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/interfaces/IDiamondCut.sol";
import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/OwnershipFacet.sol";
import "../src/Diamond.sol";

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "./helpers/DiamondUtils.sol";
import {console} from "forge-std/console.sol";

contract DiamondDeployer is Test, DiamondUtils, IDiamondCut {
    // Contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;

    address usdc = makeAddr("usdc");
    address v2Router = makeAddr("uniswapv2");

    function testDeployDiamond() public {
        // Deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet), usdc, v2Router);
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();

        // Upgrade diamond with facets
        FacetCut[] memory cut = new FacetCut[](2);

        cut[0] = (
            FacetCut({
                facetAddress: address(dLoupe),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("DiamondLoupeFacet")
            })
        );

        cut[1] = (
            FacetCut({
                facetAddress: address(ownerF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("OwnershipFacet")
            })
        );

        // Upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        // Call a function
        DiamondLoupeFacet(address(diamond)).facetAddresses();
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}
}
