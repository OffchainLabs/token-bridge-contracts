import { Contract, Signer, Wallet, ethers } from 'ethers'
import {
  L1CustomGateway__factory,
  L1ERC20Gateway__factory,
  L1GatewayRouter__factory,
  L1AtomicTokenBridgeCreator__factory,
  L2AtomicTokenBridgeFactory__factory,
} from '../../build/types'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  L1Network,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
  addCustomNetwork,
} from '@arbitrum/sdk'
import { execSync } from 'child_process'
import { Bridge__factory } from '@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import * as fs from 'fs'
import { exit } from 'process'

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
  const l2TokenBridgeFactoryOnL1 = await deployL2TemplatesOnL1(l1Signer)

  // create token bridge
  const maxSubmissionCost = ethers.utils.parseEther('0.1')
  const maxGas = 10000000
  const gasPriceBid = ethers.utils.parseUnits('0.5', 'gwei')
  const value = gasPriceBid.mul(maxGas).add(maxSubmissionCost).mul(2)
  const receipt = await (
    await l1TokenBridgeCreator.createTokenBridge(
      l2TokenBridgeFactoryOnL1,
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
  const message = messages[0]
  console.log(
    'Waiting for the L2 execution of the transaction. This may take up to 10-15 minutes ⏰'
  )
  const messageResult = await message.waitForStatus()

  if (messageResult.status !== L1ToL2MessageStatus.REDEEMED) {
    console.error(
      `L2 retryable ticket is failed with status ${
        L1ToL2MessageStatus[messageResult.status]
      }`
    )
    exit()
  }

  const L2AtomicTokenBridgeFactory = messageResult.l2TxReceipt.contractAddress
  console.log('L2AtomicTokenBridgeFactory', L2AtomicTokenBridgeFactory)

  // get L1 deployed contracts
  const iface = l1TokenBridgeCreator.interface
  const eventFragment = iface.getEvent('OrbitTokenBridgeCreated')
  const parsedLog = receipt.logs
    .filter(
      (curr: any) => curr.topics[0] === iface.getEventTopic(eventFragment)
    )
    .map((curr: any) => iface.parseLog(curr))
  const {
    router: l1Router,
    standardGateway: l1StandardGateway,
    customGateway: l1CustomGateway,
    proxyAdmin: l1ProxyAdmin,
  } = parsedLog[0].args

  // deploy+init L2 side
  // const l2TokenBridgeFactory = await new L2TokenBridgeFactory__factory(
  //   l2Signer
  // ).deploy(l1Router, l1StandardGateway, l1CustomGateway)
  // await l2TokenBridgeFactory.deployed()
  // const l2Receipt = await l2Signer.provider!.getTransactionReceipt(
  //   l2TokenBridgeFactory.deployTransaction.hash
  // )

  // const l2Iface = l2TokenBridgeFactory.interface
  // const l2Event = l2Iface.getEvent('OrbitL2TokenBridgeCreated')
  // const parsedL2Log = l2Receipt.logs
  //   .filter((curr: any) => curr.topics[0] === l2Iface.getEventTopic(l2Event))
  //   .map((curr: any) => l2Iface.parseLog(curr))
  // const {
  //   router: l2Router,
  //   standardGateway: l2StandardGateway,
  //   customGateway: l2CustomGateway,
  //   beaconProxyFactory,
  //   proxyAdmin: l2ProxyAdmin,
  // } = parsedL2Log[0].args

  // init L1 side
  // const cloneableProxyHash = await BeaconProxyFactory__factory.connect(
  //   beaconProxyFactory,
  //   l2Signer
  // ).cloneableProxyHash()
  // await (
  //   await l1TokenBridgeCreator.initTokenBridge(
  //     l1Router,
  //     l1StandardGateway,
  //     l1CustomGateway,
  //     await l1Signer.getAddress(),
  //     inboxAddress,
  //     l2Router,
  //     l2StandardGateway,
  //     l2CustomGateway,
  //     cloneableProxyHash,
  //     beaconProxyFactory
  //   )
  // ).wait()

  const l2Router = ethers.constants.AddressZero
  const l2StandardGateway = ethers.constants.AddressZero
  const l2CustomGateway = ethers.constants.AddressZero
  const beaconProxyFactory = ethers.constants.AddressZero
  const l2ProxyAdmin = ethers.constants.AddressZero

  return {
    l1Router,
    l1StandardGateway,
    l1CustomGateway,
    l1ProxyAdmin,
    l2Router,
    l2StandardGateway,
    l2CustomGateway,
    beaconProxyFactory,
    l2ProxyAdmin,
  }
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
  console.log('l2TokenBridgeFactoryOnL1', l2TokenBridgeFactoryOnL1.address)

  return l2TokenBridgeFactoryOnL1.address
}

const bridgeFundsToL2Deployer = async (
  l1Signer: Signer,
  inboxAddress: string
) => {
  console.log('fund L2 deployer')

  const depositAmount = ethers.utils.parseUnits('3', 'ether')

  // bridge it
  const InboxAbi = ['function depositEth() public payable returns (uint256)']
  const Inbox = new Contract(inboxAddress, InboxAbi, l1Signer)
  await (await Inbox.depositEth({ value: depositAmount })).wait()
  await sleep(30 * 1000)
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
