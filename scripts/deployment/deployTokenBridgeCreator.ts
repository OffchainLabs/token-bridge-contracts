import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network, addCustomNetwork } from '@arbitrum/sdk'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import {
  deployL1TokenBridgeCreator,
  getEstimateForDeployingFactory,
  getSigner,
} from '../atomicTokenBridgeDeployer'
import dotenv from 'dotenv'
import { BigNumber } from 'ethers'

dotenv.config()

export const envVars = {
  baseChainRpc: process.env['BASECHAIN_RPC'] as string,
  baseChainDeployerKey: process.env['BASECHAIN_DEPLOYER_KEY'] as string,
  childChainRpc: process.env['ORBIT_RPC'] as string,
  baseChainWeth: process.env['BASECHAIN_WETH'] as string,
  rollupAddress: process.env['ROLLUP_ADDRESS'] as string,
  gasLimitForL2FactoryDeployment:
    process.env['GAS_LIMIT_FOR_L2_FACTORY_DEPLOYMENT'],
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
export const deployTokenBridgeCreator = async () => {
  if (!envVars.baseChainRpc) {
    throw new Error('Missing BASECHAIN_RPC in env vars')
  }
  if (!envVars.baseChainDeployerKey) {
    throw new Error('Missing BASECHAIN_DEPLOYER_KEY in env vars')
  }
  if (!envVars.baseChainWeth) {
    throw new Error('Missing BASECHAIN_WETH in env vars')
  }
  if (
    !(envVars.rollupAddress && envVars.childChainRpc) &&
    !envVars.gasLimitForL2FactoryDeployment
  ) {
    throw new Error(
      'Either GAS_LIMIT_FOR_L2_FACTORY_DEPLOYMENT or (ROLLUP_ADDRESS and ORBIT_RPC) must be set in env vars'
    )
  }

  const l1Provider = new JsonRpcProvider(envVars.baseChainRpc)
  const l1Deployer = getSigner(l1Provider, envVars.baseChainDeployerKey)

  // get gas limit for L2 factory deployment from env var or do retryable estimate
  let gasLimitForL2FactoryDeployment: BigNumber
  if (envVars.gasLimitForL2FactoryDeployment) {
    gasLimitForL2FactoryDeployment = BigNumber.from(
      envVars.gasLimitForL2FactoryDeployment
    )
  } else {
    const l2Provider = new JsonRpcProvider(envVars.childChainRpc)
    await registerNetworks(l1Provider, l2Provider, envVars.rollupAddress)
    //// run retryable estimate for deploying L2 factory
    const deployFactoryGasParams = await getEstimateForDeployingFactory(
      l1Deployer,
      l2Provider
    )
    gasLimitForL2FactoryDeployment = deployFactoryGasParams.gasLimit
  }

  // deploy L1 creator and set templates
  const { l1TokenBridgeCreator, retryableSender } =
    await deployL1TokenBridgeCreator(
      l1Deployer,
      envVars.baseChainWeth,
      gasLimitForL2FactoryDeployment,
      true
    )

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
  console.log('Deploying token bridge creator...')
  const { l1TokenBridgeCreator, retryableSender } =
    await deployTokenBridgeCreator()

  console.log('Token bridge creator deployed!')
  console.log('L1TokenBridgeCreator:', l1TokenBridgeCreator.address)
  console.log('L1TokenBridgeRetryableSender:', retryableSender.address, '\n')
}

main().then(() => console.log('Done.'))
