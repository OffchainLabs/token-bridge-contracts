# Bridged USDC standard implementation for Orbit chains

## Background

Circle’s Bridged USDC Standard is a specification and process for deploying a bridged form of USDC on EVM blockchains with optionality for Circle to seamlessly upgrade to native issuance in the future.

We provide custom USDC gateway implementation (for parent and child chain) that follows Bridged USDC Standard. These contracts can be used by new Orbit chains. This solution will NOT be used in existing Arbitrum chains. On parent chain contract `L1USDCGateway` is used in case child chain uses ETH as native currency, or `L1OrbitUSDCGateway` in case child chain uses custom fee token. On child chain `L2USDCGateway` is used. For the USDC token contracts, Circle's referent implementation is used.

This doc describes how to deploy USDC bridge compatible with both Arbitrum's token bridge and Circle’s Bridged USDC Standard.Also steps for transition to native USDC issuance are provided.

## Assumptions

It is assumed there is already USDC token deployed and used on the parent chain.

Also, it is assumed the standard Orbit chain ownership system is used, ie. UpgradeExecutor is the owner of the ownable contracts and there is an EOA or multisig which has executor role on the UpgradeExecutor.

Note: throughout the docs and code, terms `L1` and `L2` are used interchangeably with `parent chain` and `child chain`. They have the same meaning, ie. if an Orbit chain is deployed on top of ArbitrumOne then ArbitrumOne is `L1`/`parent chain`, while Orbit is `L2`/`child chain`

## Deployment steps

Checkout target code, install dependencies and build

```
cd token-bridge-contracts
yarn install
yarn build
```

Populate .env based on `env.example` in this directory

```
PARENT_RPC=
PARENT_DEPLOYER_KEY=
CHILD_RPC=
CHILD_DEPLOYER_KEY=
L1_ROUTER=
L2_ROUTER=
INBOX=
L1_USDC=
## OPTIONAL arg. If set, script will register the gateway, otherwise it will store TX payload in a file
ROLLUP_OWNER_KEY=
```

Run the script

```
yarn deploy:usdc-token-bridge
```

Script will do the following:

- load deployer wallets for L1 and L2
- register L1 and L2 networks in SDK
- deploy new L1 and L2 proxy admins
- deploy bridged (L2) USDC using the Circle's implementation
- init L2 USDC
- deploy L1 USDC gateway
- deploy L2 USDC gateway
- init both gateways
- if `ROLLUP_OWNER_KEY` is provided, register the gateway in the router through the UpgradeExecutor
- if `ROLLUP_OWNER_KEY` is not provided, prepare calldata and store it in `registerUsdcGatewayTx.json` file
- set minter role to L2 USDC gateway with max allowance

Now new USDC gateways can be used to deposit/withdraw USDC. And everything is in place to support transition to native USDC issuance, in case Circle and Orbit chain owner agree to it.

## Transition to native USDC

Once transition to native USDC is agreed on, following steps are required:

- L1 gateway owner pauses deposits on parent chain by calling `pauseDeposits()`
- L2 gateway owner pauses withdrawals on child chain by calling `pauseWithdrawals()`
- master minter removes the minter role from the child chain gateway
  - NOTE: there should be no in-flight deposits when minter role is revoked. If there are any, they should be finalized first. That can be done by anyone by claiming the claimable failed retryable tickets which do the USDC depositing
- L1 gateway owner sets Circle's account as burner on the parent chain gateway using `setBurner(address)`
- L1 gateway owner reads the total supply of USDC on the child chain, and then invokes `setBurnAmount(uint256)` on the parent child gateway where the amount matches the total supply
- USDC masterMinter gives minter role with 0 allowance to L1 gateway, so the burn can be executed
- on the child chain, L2 gateway owner calls the `setUsdcOwnershipTransferrer(address)` to set the account (provided and controlled by Circle) which will be able to transfer the bridged USDC ownership and proxy admin
- if not already owned by gateway, L2 USDC owner transfers ownership to gateway, and proxy admin transfers admin rights to gateway
- Circle uses `usdcOwnershipTransferrer` account to trigger `transferUSDCRoles(address)` which will set caller as USDC proxy admin and will transfer USDC ownership to the provided address
- Circle calls `burnLockedUSDC()` on the L1 gateway using `burner` account to burn the `burnAmount` of USDC
  - remaining USDC will be cleared off when remaining in-flight USDC withdrawals are executed, if any
  - L1 gateway owner is trusted to not frontrun this TX to modify the burning amount
