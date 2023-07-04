import { Signer, Wallet, ethers } from 'ethers'
import {
  L1CustomGateway__factory,
  L1ERC20Gateway__factory,
  L1GatewayRouter__factory,
  L1AtomicTokenBridgeCreator__factory,
  L2AtomicTokenBridgeFactory__factory,
  L2GatewayRouter__factory,
  L2ERC20Gateway__factory,
  L2CustomGateway__factory,
  L1AtomicTokenBridgeCreator,
} from '../../build/types'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  L1Network,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
  addCustomNetwork,
} from '@arbitrum/sdk'
import { Bridge__factory } from '@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import * as fs from 'fs'
import { exit } from 'process'
import { execSync } from 'child_process'

export const setupTokenBridge = async (
  l1Deployer: Signer,
  l2Deployer: Signer,
  l1Url: string,
  l2Url: string
) => {
  const { l1Network, l2Network: coreL2Network } = await getLocalNetworks(
    l1Url,
    l2Url
  )

  // register - needed for retryables
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

  // prerequisite - deploy L1 creator and set templates
  const l1TokenBridgeCreator = await deployL1TokenBridgeCreator(l1Deployer)

  // create token bridge
  const deployedContracts = await createTokenBridge(
    l1Deployer,
    l2Deployer,
    l1TokenBridgeCreator,
    coreL2Network.ethBridge.inbox
  )

  const l2Network: L2Network = {
    ...coreL2Network,
    tokenBridge: {
      l1CustomGateway: deployedContracts.l1CustomGateway,
      l1ERC20Gateway: deployedContracts.l1StandardGateway,
      l1GatewayRouter: deployedContracts.l1Router,
      l1MultiCall: '',
      l1ProxyAdmin: deployedContracts.l1ProxyAdmin,
      l1Weth: '',
      l1WethGateway: '',

      l2CustomGateway: deployedContracts.l2CustomGateway,
      l2ERC20Gateway: deployedContracts.l2StandardGateway,
      l2GatewayRouter: deployedContracts.l2Router,
      l2Multicall: '',
      l2ProxyAdmin: deployedContracts.l2ProxyAdmin,
      l2Weth: '',
      l2WethGateway: '',
    },
  }

  // can't re-add
  // addCustomNetwork({
  //   customL1Network: l1Network,
  //   customL2Network: l2Network,
  // })

  return {
    l1Network,
    l2Network,
  }
}

/**
 * Use already deployed L1TokenBridgeCreator to create and token bridge contracts.
 *
 * @param l1Signer
 * @param l2Signer
 * @param inboxAddress
 * @returns
 */
export const createTokenBridge = async (
  l1Signer: Signer,
  l2Signer: Signer,
  l1TokenBridgeCreator: L1AtomicTokenBridgeCreator,
  inboxAddress: string
) => {
  // create token bridge
  const maxSubmissionCost = ethers.utils.parseEther('0.1')
  const maxGas = 10000000
  const gasPriceBid = ethers.utils.parseUnits('0.5', 'gwei')
  const value = gasPriceBid.mul(maxGas).add(maxSubmissionCost).mul(5)
  const owner = await l1Signer.getAddress()
  const receipt = await (
    await l1TokenBridgeCreator.createTokenBridge(
      inboxAddress,
      owner,
      maxSubmissionCost,
      maxGas,
      gasPriceBid,
      { value: value }
    )
  ).wait()

  /// wait for retryable execution
  const l1TxReceipt = new L1TransactionReceipt(receipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(l2Signer)
  const messageResults = await Promise.all(
    messages.map(message => message.waitForStatus())
  )

  // if both tickets are not redeemed log it and exit
  if (
    messageResults[0].status !== L1ToL2MessageStatus.REDEEMED ||
    messageResults[1].status !== L1ToL2MessageStatus.REDEEMED
  ) {
    console.log(
      `Retryable ticket (ID ${messages[0].retryableCreationId}) status: ${
        L1ToL2MessageStatus[messageResults[0].status]
      }`
    )
    console.log(
      `Retryable ticket (ID ${messages[1].retryableCreationId}) status: ${
        L1ToL2MessageStatus[messageResults[1].status]
      }`
    )
    exit()
  }

  /// pick up L2 factory address from 1st ticket
  const l2AtomicTokenBridgeFactory =
    L2AtomicTokenBridgeFactory__factory.connect(
      messageResults[0].l2TxReceipt.contractAddress,
      l2Signer
    )
  console.log('L2AtomicTokenBridgeFactory', l2AtomicTokenBridgeFactory.address)

  /// pick up L1 contracts from events
  const {
    router: l1Router,
    standardGateway: l1StandardGateway,
    customGateway: l1CustomGateway,
    proxyAdmin: l1ProxyAdmin,
  } = getParsedLogs(
    receipt.logs,
    l1TokenBridgeCreator.interface,
    'OrbitTokenBridgeCreated'
  )[0].args

  /// pick up L2 contracts from L1 factory contract
  const l2Router = await l2AtomicTokenBridgeFactory.router()
  const l2StandardGateway = L2ERC20Gateway__factory.connect(
    await l2AtomicTokenBridgeFactory.standardGateway(),
    l2Signer
  )
  const beaconProxyFactory = await l2StandardGateway.beaconProxyFactory()
  const l2CustomGateway = await l2AtomicTokenBridgeFactory.customGateway()
  const l2ProxyAdmin = await l2AtomicTokenBridgeFactory.proxyAdmin()

  return {
    l1Router,
    l1StandardGateway,
    l1CustomGateway,
    l1ProxyAdmin,
    l2Router,
    l2StandardGateway: l2StandardGateway.address,
    l2CustomGateway,
    beaconProxyFactory,
    l2ProxyAdmin,
  }
}

const getParsedLogs = (
  logs: ethers.providers.Log[],
  iface: ethers.utils.Interface,
  eventName: string
) => {
  const eventFragment = iface.getEvent(eventName)
  const parsedLogs = logs
    .filter(
      (curr: any) => curr.topics[0] === iface.getEventTopic(eventFragment)
    )
    .map((curr: any) => iface.parseLog(curr))
  return parsedLogs
}

const deployL1TokenBridgeCreator = async (l1Signer: Signer) => {
  /// deploy factory
  const l1TokenBridgeCreator = await new L1AtomicTokenBridgeCreator__factory(
    l1Signer
  ).deploy()
  await l1TokenBridgeCreator.deployed()
  console.log('L1TokenBridgeCreator', l1TokenBridgeCreator.address)

  /// deploy logic contracts
  const routerTemplate = await new L1GatewayRouter__factory(l1Signer).deploy()
  await routerTemplate.deployed()

  const standardGatewayTemplate = await new L1ERC20Gateway__factory(
    l1Signer
  ).deploy()
  await standardGatewayTemplate.deployed()

  const customGatewayTemplate = await new L1CustomGateway__factory(
    l1Signer
  ).deploy()
  await customGatewayTemplate.deployed()

  /// deploy L2 contracts as placeholders on L1

  const l2TokenBridgeFactoryOnL1 =
    await new L2AtomicTokenBridgeFactory__factory(l1Signer).deploy()
  await l2TokenBridgeFactoryOnL1.deployed()

  /// deploy router
  const l2GatewayRouterOnL1 = await new L2GatewayRouter__factory(
    l1Signer
  ).deploy()
  await l2GatewayRouterOnL1.deployed()

  /// deploy standard gateway
  const l2StandardGatewayAddressOnL1 = await new L2ERC20Gateway__factory(
    l1Signer
  ).deploy()
  await l2StandardGatewayAddressOnL1.deployed()

  /// deploy custom gateway
  const l2CustomGatewayAddressOnL1 = await new L2CustomGateway__factory(
    l1Signer
  ).deploy()
  await l2CustomGatewayAddressOnL1.deployed()

  await (
    await l1TokenBridgeCreator.setTemplates(
      routerTemplate.address,
      standardGatewayTemplate.address,
      customGatewayTemplate.address,
      l2TokenBridgeFactoryOnL1.address,
      l2GatewayRouterOnL1.address,
      l2StandardGatewayAddressOnL1.address,
      l2CustomGatewayAddressOnL1.address
    )
  ).wait()

  return l1TokenBridgeCreator
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
  try {
    deploymentData = execSync(
      'docker exec nitro_testnode_sequencer_1 cat /config/deployment.json'
    ).toString()
  } catch (e) {
    deploymentData = execSync(
      'docker exec nitro-testnode-sequencer-1 cat /config/deployment.json'
    ).toString()
  }
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

export const getSigner = (provider: JsonRpcProvider, key?: string) => {
  if (!key && !provider)
    throw new Error('Provide at least one of key or provider.')
  if (key) return new Wallet(key).connect(provider)
  else return provider.getSigner(0)
}

export function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function main() {
  const config = {
    arbUrl: 'http://localhost:8547',
    ethUrl: 'http://localhost:8545',
  }

  const l1Provider = new ethers.providers.JsonRpcProvider(config.ethUrl)
  const l2Provider = new ethers.providers.JsonRpcProvider(config.arbUrl)

  const l1DeployerWallet = new ethers.Wallet(
    ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_l1user')),
    l1Provider
  )
  const l2DeployerWallet = new ethers.Wallet(
    ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_l1user')),
    l2Provider
  )

  const { l1Network, l2Network } = await setupTokenBridge(
    l1DeployerWallet,
    l2DeployerWallet,
    config.ethUrl,
    config.arbUrl
  )

  const NETWORK_FILE = 'network.json'
  fs.writeFileSync(
    NETWORK_FILE,
    JSON.stringify({ l1Network, l2Network }, null, 2)
  )
  console.log(NETWORK_FILE + ' updated')
}

main().then(() => console.log('Done.'))
