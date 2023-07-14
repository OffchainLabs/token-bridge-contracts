import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network, addCustomNetwork } from '@arbitrum/sdk'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import {
  deployL1TokenBridgeCreator,
  getSigner,
} from '../atomicTokenBridgeDeployer'
import dotenv from 'dotenv'

dotenv.config()

export const envVars = {
  baseChainRpc: process.env['ARB_GOERLI_RPC'] as string,
  baseChainDeployerKey: process.env['ARB_GOERLI_DEPLOYER_KEY'] as string,
  childChainRpc: process.env['ORBIT_RPC'] as string,
}

const ARB_GOERLI_WETH = '0xEe01c0CD76354C383B8c7B4e65EA88D00B06f36f'

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
export const deployTokenBridgeCreator = async (rollupAddress: string) => {
  if (envVars.baseChainRpc == undefined)
    throw new Error('Missing ARB_GOERLI_RPC in env vars')
  if (envVars.baseChainDeployerKey == undefined)
    throw new Error('Missing ARB_GOERLI_DEPLOYER_KEY in env vars')
  if (envVars.childChainRpc == undefined)
    throw new Error('Missing ORBIT_RPC in env vars')

  const l1Provider = new JsonRpcProvider(envVars.baseChainRpc)
  const l1Deployer = getSigner(l1Provider, envVars.baseChainDeployerKey)
  const l2Provider = new JsonRpcProvider(envVars.childChainRpc)

  await registerGoerliNetworks(l1Provider, l2Provider, rollupAddress)

  // deploy L1 creator and set templates
  const l1TokenBridgeCreator = await deployL1TokenBridgeCreator(
    l1Deployer,
    l2Provider,
    ARB_GOERLI_WETH
  )

  return l1TokenBridgeCreator
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
  // this is just random Orbit rollup that will be used to estimate gas needed to deploy L2 token bridge factory via retryable
  const rollupAddress = '0xDAB64b6E86035Aa9EB697341B663fb4B46930E60'
  const l1TokenBridgeCreator = await deployTokenBridgeCreator(rollupAddress)
  console.log('L1TokenBridgeCreator:', l1TokenBridgeCreator.address)
}

main().then(() => console.log('Done.'))
