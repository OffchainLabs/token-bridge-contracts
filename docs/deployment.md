# How to deploy the TokenBridgeCreator factory contract and create a token bridge for a chain?

> [!IMPORTANT]
> The recommended way of creating new Arbitrum chains and deploy their token bridge is through the Arbitrum Orbit SDK. Instructions are available in our [documentation portal](https://docs.arbitrum.io/launch-arbitrum-chain/arbitrum-chain-sdk-introduction). These instructions are targetted to readers who are familiar with the Nitro stack and the creation of Arbitrum chains.

If you're looking for instructions to deploy the RollupCreator factory contract, or how to create a new rollup chain, see the instructions in the [nitro-contracts](https://github.com/OffchainLabs/nitro-contracts/blob/main/docs/deployment.md) repository.

## 1. Setup project

Clone this repository

```shell
git clone https://github.com/offchainlabs/token-bridge-contracts
cd token-bridge-contracts
```

Checkout the appropriate release (e.g. v1.2.5)

```shell
git checkout v1.2.5
```

Install dependencies and build

```shell
yarn install
yarn build
```

Make a copy of the .env-sample file

```shell
cp .env-sample .env
```

Choose the network that you're going to deploy the contracts to and set the environment variables needed.

```shell
# RPC of the parent chain of your chain
BASECHAIN_RPC=
# Private key of the deployer of the token bridge contracts in the parent chain of your chain
BASECHAIN_DEPLOYER_KEY=
```

_Note: the additional env variables needed for each step are specified in the appropriate section._

## 2. Deploy the TokenBridgeCreator factory

Set the following environment variables:

```shell
# Address of the WETH contract in the parent chain
BASECHAIN_WETH=
# API key to use for verification of contracts
# (use this variable regardless of the network where you're deploying the factory to)
ARBISCAN_API_KEY=
```

Additionally, set the following environment variables to calculate the gas limit needed for deploying the child chain factory via retryable tickets. This value needs to be provided to the TokenBridgeCreator on initialization and can be obtained in 2 ways:

- Provide a hardcoded value by setting the `GAS_LIMIT_FOR_L2_FACTORY_DEPLOYMENT` environment variable. This is the recommended and simpler method. Previous deployments have shown that the gas needed is ~5140000. Adding a bit of buffer on top, we can set this value to `GAS_LIMIT_FOR_L2_FACTORY_DEPLOYMENT=6000000`.
- Provide the `ORBIT_RPC` and `ROLLUP_ADDRESS` environment variables, and the script will use the Arbitrum SDK to estimate the gas needed for deploying the L2 factory.

Finally deploy the TokenBridgeCreator factory contract and the templates

```shell
yarn run deploy:token-bridge-creator
```

The script will output `L1TokenBridgeCreator` and `L1TokenBridgeRetryableSender` addresses. All deployed addresses can be obtained through the `L1TokenBridgeCreator` contract.

## 3. Create a token bridge for a rollup chain

Set the following environment variables:

```shell
# Address of the TokenBridgeCreator factory contract
L1_TOKEN_BRIDGE_CREATOR="0x"
# Address of the Rollup contract of your chain
ROLLUP_ADDRESS="0x"
# Address of the chain owner
ROLLUP_OWNER="0x"
# RPC of your Arbitrum(Orbit) chain
ORBIT_RPC=
```

Finally create the token bridge contracts by running the following command:

```shell
yarn run create:token-bridge
```

The script will output the addresses of all contracts created.

## Ownership

These contracts will be owned by deployer:
- L1AtomicTokenBridgeCreator (owner can set templates)
- ProxyAdmin of L1AtomicTokenBridgeCreator and L1TokenBridgeRetryableSender (owner can do upgrades)

## Test token bridge deployment

There is a verification script which checks that token bridge contracts have been properly deployed and initialized. Here are steps for running it.

Set the following environment variables

```shell
# RPC of the parent chain of your chain
BASECHAIN_RPC=
# Private key of the deployer of the token bridge contracts in the parent chain of your chain
BASECHAIN_DEPLOYER_KEY=
# Address of the TokenBridgeCreator factory contract
L1_TOKEN_BRIDGE_CREATOR="0x"
# Address of the Rollup contract of your chain
ROLLUP_ADDRESS="0x"
# Can be obtained by calling `retryableSender()` on the L1TokenBridgeCreator
L1_RETRYABLE_SENDER=
# RPC of your Arbitrum(Orbit) chain
ORBIT_RPC=
```

Run the script

```shell
yarn run test:tokenbridge:deployment
```

## Verify Orbit contracts' source code on the Blockscout

Script `scripts/orbitVerifyOnBlockscout.ts` does the source code verification of all the contracts deployed by the L1AtomicTokenBridgeCreator to the specific Orbit chain.

Script is applicable for the verifying source code on the Blockscout explorer. Steps are following:

1. Update `hardhat.config.ts`. Find `orbit` field under `networks` and `customChains` and replace values with correct RPC and blockscout endpoints.
2. `yarn install && yarn build`
3. Set up `.env` - provide `BASECHAIN_RPC`, `L1_TOKEN_BRIDGE_CREATOR` (address of token bridge creator on parent chain) and `INBOX_ADDRESS`. 
4. Optionally provide the `DEPLOYER_KEY`. That's the private key of any funded address on the Orbit chain. It is required if you want to get `UpgradeExecutor` and `aeWETH` verified. Due to specifics of cross-chain deployment used by token bridge creator, the only way to get `UpgradeExecutor` and `aeWETH` verified is to deploy dummy instances on the Orbit chain and verify them. That way the original instances will get automatically verified because of the deployed bytecode match. If `DEPLOYER_KEY` is not provided, this step will be skipped.
5. Run script as following: `yarn run blockscout:verify --network orbit`
