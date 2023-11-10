# How to deploy RollupCreator and TokenBridgeCreator?

## RollupCreator
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


## TokenBridgeCreator
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