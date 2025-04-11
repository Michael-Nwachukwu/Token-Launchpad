# Diamond Launchpad

**Diamond Launchpad** is a decentralized fundraising platform built on Ethereum, designed to allow users to create token-based fundraising campaigns with a focus on equitable token distribution using Bancor’s bonding curve. The platform leverages the EIP-2535 Diamond Standard for upgradability and integrates with Uniswap V2 for liquidity provision post-funding.

## Project Goals

The primary goal of Diamond Launchpad is to create a fundraising token launchpad where users can raise funds in USDC, with the following specifications:

-   **Fundraising Mechanism:** Users specify a funding goal in USDC, and tokens are sold to contributors following Bancor’s bonding curve, incentivizing early buyers with lower token prices.
-   **Token Supply and Distribution:**
    -   **Initial Supply:** 1 billion tokens (though only 500 million are sold during fundraising).
    -   **Funding Target:** Achieved after selling 500 million tokens.
    -   **Creator Rewards:** After funding is complete, the campaign creator receives 200 million tokens and half of the raised USDC.
    -   **Liquidity Provision:** The remaining half of the USDC and 250 million tokens are deployed to a Uniswap V2 pool for liquidity.
    -   **Platform Fee:** The platform retains 50 million tokens as a fee.
-   **Upgradability:** The launchpad contract uses the UUPS (Universal Upgradeable Proxy Standard) pattern via the EIP-2535 Diamond Standard for future enhancements.

## Approach and Implementation

### Steps Taken

1.  **Diamond Standard Setup:**
    -   Adopted EIP-2535 (Diamond Standard) for modularity and upgradability.
    -   Deployed a `Diamond` contract as the proxy, with facets (`DiamondCutFacet`, `DiamondLoupeFacet`, `OwnershipFacet`, `LaunchpadFacet`) handling specific functionalities.
    -   Used `DiamondUtils.sol` to generate function selectors for facet registration.
2.  **Token and USDC Integration:**
    -   Integrated a custom `TokenFacet` (ERC20 implementation) for USDC and campaign tokens, with adjustable decimals (6 for USDC, 18 for tokens).
    -   Hardcoded Sepolia USDC (`0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`) for deployment.
3.  **Bancor’s Bonding Curve:**
    -   Implemented in `LaunchpadFacet` via `_calculatePurchaseReturn`.
    -   Adjusted to scale initial purchases to meet the 500 million token target with desired USDC funding.
4.  **Fundraising Logic:**
    -   Added `createCampaign` and `buyIn` functions in `LaunchpadFacet`.
    -   Defined constants: `TOKENS_FOR_SALE` (500M), `CREATOR_ALLOCATION` (200M), `LIQUIDITY_ALLOCATION` (250M), `PLATFORM_FEE_TOKENS` (50M).
5.  **Payout and Liquidity:**
    -   Implemented `_payOut` to distribute tokens and USDC, calling `_addLiquidity` for Uniswap integration.
    -   Used a mock Uniswap V2 Router for local testing, with plans for real deployment on Sepolia.
6.  **Testing:**
    -   Wrote comprehensive tests in `LaunchpadFacetTest.sol` using Foundry’s `forge-std`.
    -   Simulated campaign creation, funding, and payout scenarios.
7.  **Deployment:**
    -   Created `DiamondDeployer.sol` script for deploying the Diamond and facets on Sepolia.

### Bancor’s Bonding Curve

#### What It Is

Bancor’s bonding curve is a mathematical formula used to price tokens dynamically based on supply and demand. It ensures that early buyers pay less per token than later buyers, incentivizing early participation. The formula used is:

`Return = Supply × ((1 + Deposit Amount / Reserve Balance)^(Reserve Ratio / Max Reserve Ratio) - 1)`

-   **Supply:** Current token supply.
-   **Deposit Amount:** USDC contributed.
-   **Reserve Balance:** Accumulated USDC in the campaign.
-   **Reserve Ratio:** A parameter controlling price sensitivity (e.g., 10,000 out of 1,000,000).

For the initial purchase (`Reserve Balance = 0`), a special case applies to set a starting price.

#### How

-   **Implementation:** In `_calculatePurchaseReturn`:

    ```solidity
    function _calculatePurchaseReturn(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveRatio,
        uint256 _depositAmount
    ) internal view returns (uint256) {
    }
    ```

-   **Incentive:** Early buyers get more tokens per USDC, with prices increasing as `tokensSold` approaches `TOKENS_FOR_SALE`.

### Contract Structure

-   **Diamond.sol:**
    -   The proxy contract, storing `usdcToken` and `uniswapRouter` addresses.
    -   Delegates calls to facets via fallback.
-   **DiamondCutFacet.sol:**
    -   Manages upgrades by adding, replacing, or removing facets.
-   **DiamondLoupeFacet.sol:**
    -   Provides introspection functions (e.g., `facetAddresses`) to verify the Diamond’s state.
-   **OwnershipFacet.sol:**
    -   Handles ownership transfers for the Diamond.
-   **LaunchpadFacet.sol:**
    -   Core logic for campaign creation, token purchases, and payout.
    -   Key functions:
        -   `createCampaign`: Initializes a campaign with name, symbol, target USDC, and reserve ratio.
        -   `buyIn`: Handles USDC deposits, mints tokens, and triggers `_payOut` when funding is complete.
        -   `_payOut`: Distributes tokens and USDC, calls `_addLiquidity`.
        -   `_addLiquidity`: Integrates with Uniswap V2 for liquidity provision.
-   **TokenFacet.sol:**
    -   ERC20 implementation for USDC and campaign tokens, with minting restricted to the Diamond.
-   **DiamondDeployer.sol:**
    -   Deployment script for the Diamond and facets on Sepolia.

## Rebuilding the Application

### Prerequisites

-   **Foundry:** Install via `curl -L https://foundry.paradigm.xyz | bash` and run `foundryup`.
-   **Node.js:** For managing dependencies (optional).
-   **Sepolia RPC:** An RPC URL (e.g., from Alchemy or Infura).
-   **Private Key:** A funded Sepolia account private key.

### Steps to Rebuild

1.  **Clone the Repository:**

    ```bash
    git clone <repository_url>
    cd diamond-launchpad
    ```

2.  **Install Dependencies:**

    Foundry manages dependencies via `forge`. Update `foundry.toml` if needed:

    ```toml
    [profile.default]
    src = 'contracts'
    out = 'out'
    libs = ['lib']
    ```

3.  **Set Environment Variables:**

    Create a `.env` file:

    ```bash
    PRIVATE_KEY=0x<your_private_key>
    RPC_URL=<your_sepolia_rpc_url>
    ```

    Update `foundry.toml`:

    ```toml
    [profile.default]
    env = { "PRIVATE_KEY" = "env(PRIVATE_KEY)", "RPC_URL" = "env(RPC_URL)" }
    ```

4.  **Build the Contracts:**

    ```bash
    forge build
    ```

5.  **Run Tests:**

    ```bash
    forge test -vvv
    ```

    Use `--match-test <test_name>` to run specific tests (e.g., `testPayOutCampaign`).

6.  **Deploy to Sepolia:**

    ```bash
    forge script scripts/deployDiamond.sol:DiamondDeployer --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
    ```

## Current Commands

-   **Build:**

    ```bash
    forge build
    ```

    Compiles all contracts in `contracts/`.

-   **Test:**

    ```bash
    forge test
    ```

    Runs all tests in `test/`. Add `-vvv` for verbose output.

-   **Format:**

    ```bash
    forge fmt
    ```

    Formats Solidity code according to Foundry’s style guide.

-   **Gas Snapshots:**

    ```bash
    forge snapshot
    ```

    Generates gas usage reports for tests.

-   **Deploy:**

    ```bash
    forge script scripts/deployDiamond.sol:DiamondDeployer --rpc-url <sepolia_rpc_url> --private-key <private_key> --broadcast
    ```

    Deploys the Diamond and facets to Sepolia.

-   **Local Node (Anvil):**

    ```bash
    anvil
    ```

    Starts a local Ethereum node for testing (use with `--fork-url` to fork Sepolia).

-   **Cast:**

    ```bash
    cast <subcommand>
    ```

    Interacts with deployed contracts (e.g., `cast call <diamond_address> "facetAddresses()(address[])"`).

-   **Help:**

    ```bash
    forge --help
    anvil --help
    cast --help
    ```

## Usage

-   **Create a Campaign:**

    Call `createCampaign(name, symbol, targetAmount, reserveRatio)` on `LaunchpadFacet`.

    Example: `"VALHALLA"`, `"VLH"`, `5000e6`, `10000`.

-   **Contribute:**

    Approve USDC to the Diamond, then call `buyIn(campaignId, usdcAmount)`.

-   **Payout:**

    Automatically triggered when `tokensSold >= TOKENS_FOR_SALE`.

    Creator receives tokens and USDC; liquidity is added to Uniswap.

## Notes

-   **Testing Environment:** Local tests use a mock Uniswap Router. For Sepolia, ensure the router address (`0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3`) is valid or replace it with a known Uniswap deployment.
-   **Upgradability:** Add new facets or replace existing ones via `DiamondCutFacet`’s `diamondCut` function.