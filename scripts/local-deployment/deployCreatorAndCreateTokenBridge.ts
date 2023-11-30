import { ethers } from 'ethers'
import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network, addCustomNetwork } from '@arbitrum/sdk'
import { Bridge__factory } from '@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import * as fs from 'fs'
import { execSync } from 'child_process'
import {
  createTokenBridge,
  deployL1TokenBridgeCreator,
  getEstimateForDeployingFactory,
} from '../atomicTokenBridgeDeployer'
import { l2Networks } from '@arbitrum/sdk/dist/lib/dataEntities/networks'

const LOCALHOST_L2_RPC = 'http://localhost:8547'
const LOCALHOST_L3_RPC = 'http://localhost:3347'
const LOCALHOST_L3_OWNER = '0x863c904166E801527125D8672442D736194A3362'

/**
 * Steps:
 * - read network info from local container and register networks
 * - deploy L1 bridge creator and set templates
 * - do single TX deployment of token bridge
 * - populate network objects with new addresses and return it
 *
 * @param parentDeployer
 * @param childDeployer
 * @param l1Url
 * @param l2Url
 * @returns
 */
export const setupTokenBridgeInLocalEnv = async () => {
  // set RPCs either from env vars or use defaults
  let parentRpc = process.env['PARENT_RPC'] as string
  let childRpc = process.env['CHILD_RPC'] as string
  if (parentRpc === undefined || childRpc === undefined) {
    parentRpc = LOCALHOST_L2_RPC
    childRpc = LOCALHOST_L3_RPC
  }

  // set deployer keys either from env vars or use defaults
  let parentDeployerKey = process.env['PARENT_KEY'] as string
  let childDeployerKey = process.env['CHILD_KEY'] as string
  if (parentDeployerKey === undefined || childDeployerKey === undefined) {
    parentDeployerKey = ethers.utils.sha256(
      ethers.utils.toUtf8Bytes('user_token_bridge_deployer')
    )
    childDeployerKey = ethers.utils.sha256(
      ethers.utils.toUtf8Bytes('user_token_bridge_deployer')
    )
  }

  // set rollup owner either from env vars or use defaults
  let rollupOwner = process.env['ROLLUP_OWNER'] as string
  if (rollupOwner === undefined) {
    rollupOwner = LOCALHOST_L3_OWNER
  }

  // if no ROLLUP_ADDRESS is defined, it will be pulled from local container
  const rollupAddress = process.env['ROLLUP_ADDRESS'] as string

  // create deployer wallets
  const parentDeployer = new ethers.Wallet(
    parentDeployerKey,
    new ethers.providers.JsonRpcProvider(parentRpc)
  )
  const childDeployer = new ethers.Wallet(
    childDeployerKey,
    new ethers.providers.JsonRpcProvider(childRpc)
  )

  const { l1Network, l2Network: coreL2Network } = await getLocalNetworks(
    parentRpc,
    childRpc,
    rollupAddress
  )

  // register - needed for retryables
  const existingL2Network = l2Networks[coreL2Network.chainID.toString()]
  if (!existingL2Network) {
    addCustomNetwork({
      customL1Network: l1Network,
      customL2Network: {
        ...coreL2Network,
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
      },
    })
  }

  // prerequisite - deploy L1 creator and set templates
  console.log('Deploying L1TokenBridgeCreator')
  // a random address for l1Weth
  const l1Weth = '0x05EcEffc7CBA4e43a410340E849052AD43815aCA'

  //// run retryable estimate for deploying L2 factory
  const deployFactoryGasParams = await getEstimateForDeployingFactory(
    parentDeployer,
    childDeployer.provider!
  )
  const gasLimitForL2FactoryDeployment = deployFactoryGasParams.gasLimit

  const { l1TokenBridgeCreator, retryableSender } =
    await deployL1TokenBridgeCreator(
      parentDeployer,
      l1Weth,
      gasLimitForL2FactoryDeployment
    )
  console.log('L1TokenBridgeCreator', l1TokenBridgeCreator.address)
  console.log('L1TokenBridgeRetryableSender', retryableSender.address)

  // create token bridge
  console.log(
    '\nCreating token bridge for rollup',
    coreL2Network.ethBridge.rollup
  )
  const { l1Deployment, l2Deployment, l1MultiCall, l1ProxyAdmin } =
    await createTokenBridge(
      parentDeployer,
      childDeployer.provider!,
      l1TokenBridgeCreator,
      coreL2Network.ethBridge.rollup,
      rollupOwner
    )

  const l2Network: L2Network = {
    ...coreL2Network,
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

  const l1TokenBridgeCreatorAddress = l1TokenBridgeCreator.address
  const retryableSenderAddress = retryableSender.address

  return {
    l1Network,
    l2Network,
    l1TokenBridgeCreatorAddress,
    retryableSenderAddress,
  }
}

export const getLocalNetworks = async (
  l1Url: string,
  l2Url: string,
  rollupAddress?: string
): Promise<{
  l1Network: L1Network
  l2Network: Omit<L2Network, 'tokenBridge'>
}> => {
  const l1Provider = new JsonRpcProvider(l1Url)
  const l2Provider = new JsonRpcProvider(l2Url)
  let deploymentData: string

  let data = {
    bridge: '',
    inbox: '',
    'sequencer-inbox': '',
    rollup: '',
  }

  if (rollupAddress === undefined) {
    let sequencerContainer = execSync(
      'docker ps --filter "name=l3node" --format "{{.Names}}"'
    )
      .toString()
      .trim()

    deploymentData = execSync(
      `docker exec ${sequencerContainer} cat /config/l3deployment.json`
    ).toString()

    data = JSON.parse(deploymentData) as {
      bridge: string
      inbox: string
      ['sequencer-inbox']: string
      rollup: string
    }
  } else {
    const rollup = RollupAdminLogic__factory.connect(rollupAddress!, l1Provider)
    data.bridge = await rollup.bridge()
    data.inbox = await rollup.inbox()
    data['sequencer-inbox'] = await rollup.sequencerInbox()
    data.rollup = rollupAddress!
  }

  const rollup = RollupAdminLogic__factory.connect(data.rollup, l1Provider)
  const confirmPeriodBlocks = await rollup.confirmPeriodBlocks()

  const bridge = Bridge__factory.connect(data.bridge, l1Provider)
  const outboxAddr = await bridge.allowedOutboxList(0)

  const l1NetworkInfo = await l1Provider.getNetwork()
  const l2NetworkInfo = await l2Provider.getNetwork()

  const l1Network: L1Network = {
    blockTime: 10,
    chainID: l1NetworkInfo.chainId,
    explorerUrl: '',
    isCustom: true,
    name: 'EthLocal',
    partnerChainIDs: [l2NetworkInfo.chainId],
    isArbitrum: false,
  }

  const l2Network: Omit<L2Network, 'tokenBridge'> = {
    chainID: l2NetworkInfo.chainId,
    confirmPeriodBlocks: confirmPeriodBlocks.toNumber(),
    ethBridge: {
      bridge: data.bridge,
      inbox: data.inbox,
      outbox: outboxAddr,
      rollup: data.rollup,
      sequencerInbox: data['sequencer-inbox'],
    },
    explorerUrl: '',
    isArbitrum: true,
    isCustom: true,
    name: 'ArbLocal',
    partnerChainID: l1NetworkInfo.chainId,
    retryableLifetimeSeconds: 7 * 24 * 60 * 60,
    nitroGenesisBlock: 0,
    nitroGenesisL1Block: 0,
    depositTimeout: 900000,
  }
  return {
    l1Network,
    l2Network,
  }
}

async function main() {
  const {
    l1Network,
    l2Network,
    l1TokenBridgeCreatorAddress: l1TokenBridgeCreator,
    retryableSenderAddress: retryableSender,
  } = await setupTokenBridgeInLocalEnv()

  const NETWORK_FILE = 'network.json'
  fs.writeFileSync(
    NETWORK_FILE,
    JSON.stringify(
      { l1Network, l2Network, l1TokenBridgeCreator, retryableSender },
      null,
      2
    )
  )
  console.log(NETWORK_FILE + ' updated')
}

main().then(() => console.log('Done.'))
