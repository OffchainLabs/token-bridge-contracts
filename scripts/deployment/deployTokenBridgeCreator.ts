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
  baseChainRpc: process.env['BASECHAIN_RPC'] as string,
  baseChainDeployerKey: process.env['BASECHAIN_DEPLOYER_KEY'] as string,
  childChainRpc: process.env['ORBIT_RPC'] as string,
  baseChainWeth: process.env['BASECHAIN_WETH'] as string,
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
export const deployTokenBridgeCreator = async (rollupAddress: string) => {
  if (envVars.baseChainRpc == undefined || envVars.baseChainRpc == '')
    throw new Error('Missing BASECHAIN_RPC in env vars')
  if (envVars.baseChainDeployerKey == undefined || envVars.baseChainDeployerKey == '')
    throw new Error('Missing BASECHAIN_DEPLOYER_KEY in env vars')
  if (envVars.childChainRpc == undefined || envVars.childChainRpc == '')
    throw new Error('Missing ORBIT_RPC in env vars')
  if (envVars.baseChainWeth == undefined || envVars.baseChainWeth == '')
    throw new Error('Missing BASECHAIN_WETH in env vars')

  const l1Provider = new JsonRpcProvider(envVars.baseChainRpc)
  const l1Deployer = getSigner(l1Provider, envVars.baseChainDeployerKey)
  const l2Provider = new JsonRpcProvider(envVars.childChainRpc)

  await registerNetworks(l1Provider, l2Provider, rollupAddress)

  // deploy L1 creator and set templates
  const { l1TokenBridgeCreator, retryableSender } =
    await deployL1TokenBridgeCreator(l1Deployer, l2Provider, envVars.baseChainWeth, true)

  return { l1TokenBridgeCreator, retryableSender }
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
  // this is just random Orbit rollup that will be used to estimate gas needed to deploy L2 token bridge factory via retryable
  const rollupAddress = '0x8223bd899C6643483872ed2A7b105b2aC9C8aBEc'
  const { l1TokenBridgeCreator, retryableSender } =
    await deployTokenBridgeCreator(rollupAddress)

  console.log('Token bridge creator deployed!')
  console.log('L1TokenBridgeCreator:', l1TokenBridgeCreator.address)
  console.log('L1TokenBridgeRetryableSender:', retryableSender.address, '\n')
}

main().then(() => console.log('Done.'))
