# How to deploy RollupCreator and TokenBridgeCreator?

## Deploy RollupCreator
RollupCreator is in nitro-contracts repo
```
cd nitro-contracts
```

Checkout target code, ie.
```
git checkout v1.1.0
```

Install dependencies and build
```
yarn install
yarn build
```

Populate .env
```
DEVNET_PRIVKEY or MAINNET_PRIVKEY
ARBISCAN_API_KEY
```

Finally deploy it, using `--network` flag to specify network.

Ie. to deploy to Arbitrum Sepolia
```
yarn run deploy-factory --network arbSepolia
```

To deploy to Arbitrum One
```
yarn run deploy-factory --network arb1
```

Script output will contain all deployed addresses.


## Deploy TokenBridgeCreator
Checkout target code, install dependencies and build
```
cd token-bridge-contracts
yarn install
yarn build
```


Populate .env
```
BASECHAIN_RPC
BASECHAIN_DEPLOYER_KEY
BASECHAIN_WETH
GAS_LIMIT_FOR_L2_FACTORY_DEPLOYMENT
ARBISCAN_API_KEY
```

Note: Gas limit for deploying child chain factory via retryable needs to be provided to the TokenBridgeCreator when templates are set. This value can be obtained in 2 ways - 1st is to provide `ORBIT_RPC` and `ROLLUP_ADDRESS` env vars, and script will then use Arbitrum SDK to estimate gas needed for deploying L2 factory. Other way to do it is much simpler - provide hardcoded value by setting the `GAS_LIMIT_FOR_L2_FACTORY_DEPLOYMENT`. Previous deployments showed that gas needed is ~5140000. Adding a bit of buffer on top, we can set this value to `GAS_LIMIT_FOR_L2_FACTORY_DEPLOYMENT=6000000`.  


Finally, deploy token bridge creator. Target chain is defined by `BASECHAIN_RPC` env var (no need to provide `--network` flag).
```
yarn run deploy:token-bridge-creator
```

Script outputs `L1TokenBridgeCreator` and `L1TokenBridgeRetryableSender` addresses. All deployed addresses can be obtained through `L1TokenBridgeCreator` contract.


## Ownership
These contracts will be owned by deployer:
- RollupCreator (owner can set templates)
- L1AtomicTokenBridgeCreator (owner can set templates)
- ProxyAdmin of L1AtomicTokenBridgeCreator and L1TokenBridgeRetryableSender (owner can do upgrades)


## Verify token bridge deployment
There is a verification script which checks that token bridge contracts have been properly deployed and initialized. Here are steps for running it.

Checkout target code, install dependencies and build
```
cd token-bridge-contracts
yarn install
yarn build
```

Populate .env
```
ROLLUP_ADDRESS
L1_TOKEN_BRIDGE_CREATOR
L1_RETRYABLE_SENDER
BASECHAIN_DEPLOYER_KEY
BASECHAIN_RPC
ORBIT_RPC
```
(`L1_RETRYABLE_SENDER` address can be obtained by calling `retryableSender()` on the L1 token bridge creator)


Run the script
```
yarn run test:tokenbridge:deployment
```
