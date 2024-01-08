import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network, addCustomNetwork } from '@arbitrum/sdk'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import { createTokenBridge, getSigner } from '../atomicTokenBridgeDeployer'
import dotenv from 'dotenv'
import { L1AtomicTokenBridgeCreator__factory } from '../../build/types'
import * as fs from 'fs'
import { env } from 'process'

dotenv.config()

export const envVars = {
  rollupAddress: process.env['ROLLUP_ADDRESS'] as string,
  rollupOwner: process.env['ROLLUP_OWNER'] as string,
  l1TokenBridgeCreator: process.env['L1_TOKEN_BRIDGE_CREATOR'] as string,
  baseChainRpc: process.env['BASECHAIN_RPC'] as string,
  baseChainDeployerKey: process.env['BASECHAIN_DEPLOYER_KEY'] as string,
  childChainRpc: process.env['ORBIT_RPC'] as string,
}

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
export const createTokenBridgeOnTargetChain = async () => {
  if (envVars.rollupAddress == undefined)
    throw new Error('Missing ROLLUP_ADDRESS in env vars')
  if (envVars.rollupOwner == undefined)
    throw new Error('Missing ROLLUP_OWNER in env vars')
  if (envVars.l1TokenBridgeCreator == undefined)
    throw new Error('Missing L1_TOKEN_BRIDGE_CREATOR in env vars')
  if (envVars.baseChainRpc == undefined)
    throw new Error('Missing BASECHAIN_RPC in env vars')
  if (envVars.baseChainDeployerKey == undefined)
    throw new Error('Missing BASECHAIN_DEPLOYER_KEY in env vars')
  if (envVars.childChainRpc == undefined)
    throw new Error('Missing ORBIT_RPC in env vars')

  console.log('Creating token bridge for rollup', envVars.rollupAddress)

  const l1Provider = new JsonRpcProvider(envVars.baseChainRpc)
  const l1Deployer = getSigner(l1Provider, envVars.baseChainDeployerKey)
  const l2Provider = new JsonRpcProvider(envVars.childChainRpc)

  const { l1Network, l2Network: corel2Network } = await registerNetworks(
    l1Provider,
    l2Provider,
    envVars.rollupAddress
  )

  const l1TokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    envVars.l1TokenBridgeCreator,
    l1Deployer
  )

  // create token bridge
  const { l1Deployment, l2Deployment, l1MultiCall, l1ProxyAdmin } =
    await createTokenBridge(
      l1Deployer,
      l2Provider,
      l1TokenBridgeCreator,
      envVars.rollupAddress,
      envVars.rollupOwner
    )

  const l2Network = {
    ...corel2Network,
    tokenBridge: {
      l1CustomGateway: l1Deployment.customGateway,
      l1ERC20Gateway: l1Deployment.standardGateway,
      l1GatewayRouter: l1Deployment.router,
      l1MultiCall: l1MultiCall,
      l1ProxyAdmin: l1ProxyAdmin,
      l1Weth: l1Deployment.weth,
      l1WethGateway: l1Deployment.wethGateway,

      l2CustomGateway: l2Deployment.customGateway,
      l2ERC20Gateway: l2Deployment.standardGateway,
      l2GatewayRouter: l2Deployment.router,
      l2Multicall: l2Deployment.multicall,
      l2ProxyAdmin: l2Deployment.proxyAdmin,
      l2Weth: l2Deployment.weth,
      l2WethGateway: l2Deployment.wethGateway,
    },
  }

  return {
    l1Network,
    l2Network,
  }
}

const registerNetworks = async (
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
  const { l1Network, l2Network } = await createTokenBridgeOnTargetChain()
  const NETWORK_FILE = 'network.json'
  fs.writeFileSync(
    NETWORK_FILE,
    JSON.stringify({ l1Network, l2Network }, null, 2)
  )
  console.log(NETWORK_FILE + ' updated')
}

main().then(() => console.log('Done.'))
