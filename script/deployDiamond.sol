// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../src/interfaces/IDiamondCut.sol";
import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/OwnershipFacet.sol";
import "../src/Diamond.sol";
import "../test/helpers/DiamondUtils.sol";

import "../src/facets/LaunchpadFacet.sol";

contract DiamondDeployer is IDiamondCut, DiamondUtils {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    // Declare state variables for all deployed src
    address dCutFacet;
    address dLoupe;
    address ownerF;
    address diamond;
    //
    address launchpadFacet;

    function run() public {
        vm.startBroadcast(privateKey);

        // Deploy facets
        dCutFacet = address(new DiamondCutFacet());
        dLoupe = address(new DiamondLoupeFacet());
        ownerF = address(new OwnershipFacet());

        launchpadFacet = address(new LaunchpadFacet());
    
        // Deploy main diamond
        address usdcTokenAddress = address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        address routerAddress = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;
        address deployerAddress = vm.addr(privateKey);

        diamond = address(new Diamond(
            deployerAddress,
            dCutFacet,
            usdcTokenAddress,
            routerAddress
        ));

        // Create facet cuts
        FacetCut[] memory cut = new FacetCut[](3);

        cut[0] = FacetCut({
            facetAddress: dLoupe,
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondLoupeFacet")
        });

        cut[1] = FacetCut({
            facetAddress: ownerF,
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("OwnershipFacet")
        });

        cut[2] = FacetCut({
            facetAddress: launchpadFacet,
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("LaunchpadFacet")
        });

        // Upgrade diamond
        IDiamondCut(diamond).diamondCut(cut, address(0x0), "");

        // Verify deployment
        require(
            DiamondLoupeFacet(diamond).facetAddresses().length > 0,
            "Diamond deployment failed"
        );

        vm.stopBroadcast();
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}
}