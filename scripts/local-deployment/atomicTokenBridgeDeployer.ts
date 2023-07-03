import { Contract, Signer, Wallet, ethers } from 'ethers'
import {
  L1CustomGateway__factory,
  L1ERC20Gateway__factory,
  L1GatewayRouter__factory,
  L1AtomicTokenBridgeCreator__factory,
  L2AtomicTokenBridgeFactory__factory,
  L2GatewayRouter__factory,
  L2ERC20Gateway__factory,
  L2CustomGateway__factory,
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

  const deployedContracts = await deployTokenBridgeAndInit(
    l1Deployer,
    l2Deployer,
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
 * Deploy all the L1 and L2 contracts and do the initialization.
 *
 * @param l1Signer
 * @param l2Signer
 * @param inboxAddress
 * @returns
 */
export const deployTokenBridgeAndInit = async (
  l1Signer: Signer,
  l2Signer: Signer,
  inboxAddress: string
) => {
  // deploy L1 creator
  const l1TokenBridgeCreator = await deployTokenBridgeFactory(l1Signer)

  // deploy L2 contracts as templates on L1
  const {
    l2TokenBridgeFactoryOnL1,
    l2GatewayRouterOnL1,
    l2StandardGatewayAddressOnL1,
    l2CustomGatewayAddressOnL1,
  } = await deployL2TemplatesOnL1(l1Signer)

  // create token bridge
  const maxSubmissionCost = ethers.utils.parseEther('0.1')
  const maxGas = 10000000
  const gasPriceBid = ethers.utils.parseUnits('0.5', 'gwei')
  const value = gasPriceBid.mul(maxGas).add(maxSubmissionCost).mul(5)
  const receipt = await (
    await l1TokenBridgeCreator.createTokenBridge(
      l2TokenBridgeFactoryOnL1.address,
      l2GatewayRouterOnL1.address,
      l2StandardGatewayAddressOnL1.address,
      l2CustomGatewayAddressOnL1.address,
      inboxAddress,
      maxSubmissionCost,
      maxGas,
      gasPriceBid,
      { value: value }
    )
  ).wait()
  console.log('createTokenBridge done')

  /// wait for retryable execution
  const l1TxReceipt = new L1TransactionReceipt(receipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(l2Signer)

  // 1st msg - deploy factory
  const messageResult = await messages[0].waitForStatus()
  if (messageResult.status !== L1ToL2MessageStatus.REDEEMED) {
    console.error(
      `1 L2 retryable ticket is failed with status ${
        L1ToL2MessageStatus[messageResult.status]
      }`
    )
    exit()
  }

  const l2AtomicTokenBridgeFactory =
    L2AtomicTokenBridgeFactory__factory.connect(
      messageResult.l2TxReceipt.contractAddress,
      l2Signer
    )
  console.log('L2AtomicTokenBridgeFactory', l2AtomicTokenBridgeFactory.address)

  // 2nd msg - deploy router
  const messageRouterResult = await messages[1].waitForStatus()
  if (messageRouterResult.status !== L1ToL2MessageStatus.REDEEMED) {
    console.error(
      `2 L2 retryable ticket is failed with status ${
        L1ToL2MessageStatus[messageRouterResult.status]
      }`
    )
    exit()
  }

  // 3rd msg - deploy standard gw
  const messageStdGwResult = await messages[2].waitForStatus()
  if (messageRouterResult.status !== L1ToL2MessageStatus.REDEEMED) {
    console.error(
      `3 L2 retryable ticket is failed with status ${
        L1ToL2MessageStatus[messageStdGwResult.status]
      }`
    )
    exit()
  }

  // 4th msg - deploy custom gw
  const messageCustomGwResult = await messages[3].waitForStatus()
  if (messageCustomGwResult.status !== L1ToL2MessageStatus.REDEEMED) {
    console.error(
      `4 L2 retryable ticket is failed with status ${
        L1ToL2MessageStatus[messageCustomGwResult.status]
      }`
    )
    exit()
  }

  /// get L1 deployed contracts
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

  /// get L2 router
  const l2Router = await l2AtomicTokenBridgeFactory.router()

  /// get L2 standard gateway
  const l2StandardGateway = L2ERC20Gateway__factory.connect(
    await l2AtomicTokenBridgeFactory.standardGateway(),
    l2Signer
  )
  const beaconProxyFactory = await l2StandardGateway.beaconProxyFactory()

  /// get L2 standard gateway
  const l2CustomGateway = await l2AtomicTokenBridgeFactory.customGateway()
  console.log('l2CustomGateway', l2CustomGateway)

  /// get L2 proxy admin
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

const deployTokenBridgeFactory = async (l1Signer: Signer) => {
  /// deploy factory
  console.log('Deploy L1AtomicTokenBridgeCreator')

  const l1TokenBridgeCreator = await new L1AtomicTokenBridgeCreator__factory(
    l1Signer
  ).deploy()
  await l1TokenBridgeCreator.deployed()
  console.log('l1TokenBridgeCreator', l1TokenBridgeCreator.address)

  /// deploy logic contracts
  console.log('Create and set logic contracts')

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

  await (
    await l1TokenBridgeCreator.setTemplates(
      routerTemplate.address,
      standardGatewayTemplate.address,
      customGatewayTemplate.address
    )
  ).wait()

  return l1TokenBridgeCreator
}

const deployL2TemplatesOnL1 = async (l1Signer: Signer) => {
  /// deploy factory
  console.log('Deploy L2AtomicTokenBridgeFactory')
  const l2TokenBridgeFactoryOnL1 =
    await new L2AtomicTokenBridgeFactory__factory(l1Signer).deploy()
  await l2TokenBridgeFactoryOnL1.deployed()

  /// deploy router
  console.log('Deploy L2AtomicTokenBridgeFactory')
  const l2GatewayRouterOnL1 = await new L2GatewayRouter__factory(
    l1Signer
  ).deploy()
  await l2GatewayRouterOnL1.deployed()

  /// deploy standard gateway
  console.log('Deploy L2ERC20Gateway')
  const l2StandardGatewayAddressOnL1 = await new L2ERC20Gateway__factory(
    l1Signer
  ).deploy()
  await l2StandardGatewayAddressOnL1.deployed()

  /// deploy custom gateway
  console.log('Deploy L2CustomGateway')
  const l2CustomGatewayAddressOnL1 = await new L2CustomGateway__factory(
    l1Signer
  ).deploy()
  await l2CustomGatewayAddressOnL1.deployed()

  return {
    l2TokenBridgeFactoryOnL1,
    l2GatewayRouterOnL1,
    l2StandardGatewayAddressOnL1,
    l2CustomGatewayAddressOnL1,
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
