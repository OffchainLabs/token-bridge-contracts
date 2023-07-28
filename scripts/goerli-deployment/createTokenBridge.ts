import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network, addCustomNetwork } from '@arbitrum/sdk'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import { createTokenBridge, getSigner } from '../atomicTokenBridgeDeployer'
import dotenv from 'dotenv'
import { L1AtomicTokenBridgeCreator__factory } from '../../build/types'
import * as fs from 'fs'

dotenv.config()

export const envVars = {
  baseChainRpc: process.env['ARB_GOERLI_RPC'] as string,
  baseChainDeployerKey: process.env['ARB_GOERLI_DEPLOYER_KEY'] as string,
  childChainRpc: process.env['ORBIT_RPC'] as string,
}

const L1_TOKEN_BRIDGE_CREATOR = '0x4Ba3aC2a2fEf26eAA6d05D71B79fde08Cb3078a9'

/**
 * Steps:
 * - read network info from local container and register networks
 * - deploy L1 bridge creator and set templates
 * - do single TX deployment of token bridge
 * - populate network objects with new addresses and return it
 *
 * @param l1Deployer
 * @param l2Deployer
 * @param l1Url
 * @param l2Url
 * @returns
 */
export const createTokenBridgeOnGoerli = async (rollupAddress: string) => {
  if (envVars.baseChainRpc == undefined)
    throw new Error('Missing ARB_GOERLI_RPC in env vars')
  if (envVars.baseChainDeployerKey == undefined)
    throw new Error('Missing ARB_GOERLI_DEPLOYER_KEY in env vars')
  if (envVars.childChainRpc == undefined)
    throw new Error('Missing ORBIT_RPC in env vars')

  const l1Provider = new JsonRpcProvider(envVars.baseChainRpc)
  const l1Deployer = getSigner(l1Provider, envVars.baseChainDeployerKey)
  const l2Provider = new JsonRpcProvider(envVars.childChainRpc)

  const { l1Network, l2Network: corel2Network } = await registerGoerliNetworks(
    l1Provider,
    l2Provider,
    rollupAddress
  )

  const l1TokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    L1_TOKEN_BRIDGE_CREATOR,
    l1Deployer
  )

  // create token bridge
  const deployedContracts = await createTokenBridge(
    l1Deployer,
    l2Provider,
    l1TokenBridgeCreator,
    rollupAddress
  )

  const l2Network = {
    ...corel2Network,
    tokenBridge: {
      l1CustomGateway: deployedContracts.l1CustomGateway,
      l1ERC20Gateway: deployedContracts.l1StandardGateway,
      l1GatewayRouter: deployedContracts.l1Router,
      l1MultiCall: '',
      l1ProxyAdmin: deployedContracts.l1ProxyAdmin,
      l1Weth: deployedContracts.l1Weth,
      l1WethGateway: deployedContracts.l1WethGateway,

      l2CustomGateway: deployedContracts.l2CustomGateway,
      l2ERC20Gateway: deployedContracts.l2StandardGateway,
      l2GatewayRouter: deployedContracts.l2Router,
      l2Multicall: '',
      l2ProxyAdmin: deployedContracts.l2ProxyAdmin,
      l2Weth: deployedContracts.l2Weth,
      l2WethGateway: deployedContracts.l2WethGateway,
    },
  }

  return {
    l1Network,
    l2Network,
  }
}

const registerGoerliNetworks = async (
  l1Provider: JsonRpcProvider,
  l2Provider: JsonRpcProvider,
  rollupAddress: string
): Promise<{
  l1Network: L1Network
  l2Network: Omit<L2Network, 'tokenBridge'>
}> => {
  const l1NetworkInfo = await l1Provider.getNetwork()
  const l2NetworkInfo = await l2Provider.getNetwork()

  const l1Network: L1Network = {
    blockTime: 10,
    chainID: l1NetworkInfo.chainId,
    explorerUrl: '',
    isCustom: true,
    name: l1NetworkInfo.name,
    partnerChainIDs: [l2NetworkInfo.chainId],
    isArbitrum: false,
  }

  const rollup = RollupAdminLogic__factory.connect(rollupAddress, l1Provider)
  const l2Network: L2Network = {
    chainID: l2NetworkInfo.chainId,
    confirmPeriodBlocks: (await rollup.confirmPeriodBlocks()).toNumber(),
    ethBridge: {
      bridge: await rollup.bridge(),
      inbox: await rollup.inbox(),
      outbox: await rollup.outbox(),
      rollup: rollup.address,
      sequencerInbox: await rollup.sequencerInbox(),
    },
    explorerUrl: '',
    isArbitrum: true,
    isCustom: true,
    name: 'OrbitChain',
    partnerChainID: l1NetworkInfo.chainId,
    retryableLifetimeSeconds: 7 * 24 * 60 * 60,
    nitroGenesisBlock: 0,
    nitroGenesisL1Block: 0,
    depositTimeout: 900000,
    tokenBridge: {
      l1CustomGateway: '',
      l1ERC20Gateway: '',
      l1GatewayRouter: '',
      l1MultiCall: '',
      l1ProxyAdmin: '',
      l1Weth: '',
      l1WethGateway: '',
      l2CustomGateway: '',
      l2ERC20Gateway: '',
      l2GatewayRouter: '',
      l2Multicall: '',
      l2ProxyAdmin: '',
      l2Weth: '',
      l2WethGateway: '',
    },
  }

  // register - needed for retryables
  addCustomNetwork({
    customL1Network: l1Network,
    customL2Network: l2Network,
  })

  return {
    l1Network,
    l2Network,
  }
}

async function main() {
  const args = process.argv.slice(2)
  if (args.length != 1) {
    console.log(
      "Please provide exactly 1 argument - rollup address.\nIe. `yarn run create:goerli:token-bridge -- '0xDAB64b6E86035Aa9EB697341B663fb4B46930E60'`"
    )
    return
  }

  const rollupAddress = args[0]
  console.log('Creating token bridge for rollup', rollupAddress)

  const { l1Network, l2Network } = await createTokenBridgeOnGoerli(
    rollupAddress
  )
  const NETWORK_FILE = 'network.json'
  fs.writeFileSync(
    NETWORK_FILE,
    JSON.stringify({ l1Network, l2Network }, null, 2)
  )
  console.log(NETWORK_FILE + ' updated')
}

main().then(() => console.log('Done.'))
