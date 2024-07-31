# How to deploy Usdc bridge?

## Background
Circle’s Bridged USDC Standard is a specification and process for deploying a bridged form of USDC on EVM blockchains with optionality for Circle to seamlessly upgrade to native issuance in the future. 
This doc describes how to deploy USDC bridge compatible with both Arbitrum's token bridge and Circle’s Bridged USDC Standard.

## Assumptions
It is assumed there is already USDC token deployed and used on the parent chain. If not, follow the instructions in the Circle's `stablecoin-evm` repo to deploy one.  

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

Now new USDC gateways can be used to deposit/withdraw USDC. And everything is in place to support transtition to native USDC issuance, in case Circle and Orbit chain owner agree to it.