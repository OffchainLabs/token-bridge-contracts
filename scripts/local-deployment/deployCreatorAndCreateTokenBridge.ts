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
export const setupTokenBridgeInLocalEnv = async () => {
  /// setup deployers, load local networks
  /// L1 URL = parent chain = L2
  /// L2 URL = child chain = L3
  const config = {
    l1Url: 'http://localhost:8547',
    l2Url: 'http://localhost:3347',
  }
  const l1Deployer = new ethers.Wallet(
    ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_token_bridge_deployer')),
    new ethers.providers.JsonRpcProvider(config.l1Url)
  )
  const l2Deployer = new ethers.Wallet(
    ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_token_bridge_deployer')),
    new ethers.providers.JsonRpcProvider(config.l2Url)
  )
  // docker-compose run scripts print-address --account l3owner | tail -n 1 | tr -d '\r\n'
  const orbitOwner = '0x863c904166E801527125D8672442D736194A3362'

  const { l1Network, l2Network: coreL2Network } = await getLocalNetworks(
    config.l1Url,
    config.l2Url
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
    l1Deployer,
    l2Deployer.provider!
  )
  const gasLimitForL2FactoryDeployment = deployFactoryGasParams.gasLimit

  const { l1TokenBridgeCreator, retryableSender } =
    await deployL1TokenBridgeCreator(
      l1Deployer,
      l1Weth,
      gasLimitForL2FactoryDeployment
    )
  console.log('L1TokenBridgeCreator', l1TokenBridgeCreator.address)
  console.log('L1TokenBridgeRetryableSender', retryableSender.address)

  // create token bridge
  console.log('Creating token bridge')
  const deployedContracts = await createTokenBridge(
    l1Deployer,
    l2Deployer.provider!,
    l1TokenBridgeCreator,
    coreL2Network.ethBridge.rollup,
    orbitOwner
  )

  const l2Network: L2Network = {
    ...coreL2Network,
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
  l2Url: string
): Promise<{
  l1Network: L1Network
  l2Network: Omit<L2Network, 'tokenBridge'>
}> => {
  const l1Provider = new JsonRpcProvider(l1Url)
  const l2Provider = new JsonRpcProvider(l2Url)
  let deploymentData: string

  let sequencerContainer = execSync(
    'docker ps --filter "name=l3node" --format "{{.Names}}"'
  )
    .toString()
    .trim()

  deploymentData = execSync(
    `docker exec ${sequencerContainer} cat /config/l3deployment.json`
  ).toString()

  const parsedDeploymentData = JSON.parse(deploymentData) as {
    bridge: string
    inbox: string
    ['sequencer-inbox']: string
    rollup: string
  }

  const rollup = RollupAdminLogic__factory.connect(
    parsedDeploymentData.rollup,
    l1Provider
  )
  const confirmPeriodBlocks = await rollup.confirmPeriodBlocks()

  const bridge = Bridge__factory.connect(
    parsedDeploymentData.bridge,
    l1Provider
  )
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
      bridge: parsedDeploymentData.bridge,
      inbox: parsedDeploymentData.inbox,
      outbox: outboxAddr,
      rollup: parsedDeploymentData.rollup,
      sequencerInbox: parsedDeploymentData['sequencer-inbox'],
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
