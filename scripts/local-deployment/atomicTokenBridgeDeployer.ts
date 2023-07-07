import { BigNumber, Signer, Wallet, ethers } from 'ethers'
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
  L2WethGateway__factory,
  AeWETH__factory,
  L1WethGateway__factory,
  TransparentUpgradeableProxy__factory,
} from '../../build/types'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  L1Network,
  L1ToL2MessageGasEstimator,
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
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'

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
  const config = {
    arbUrl: 'http://localhost:8547',
    ethUrl: 'http://localhost:8545',
  }
  const l1Deployer = new ethers.Wallet(
    ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_l1user')),
    new ethers.providers.JsonRpcProvider(config.ethUrl)
  )
  const l2Deployer = new ethers.Wallet(
    ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_l1user')),
    new ethers.providers.JsonRpcProvider(config.arbUrl)
  )

  const { l1Network, l2Network: coreL2Network } = await getLocalNetworks(
    config.ethUrl,
    config.arbUrl
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
  const l1TokenBridgeCreatorOwner = new ethers.Wallet(
    ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_l1user_b'))
  )
  const l1TokenBridgeCreator = await deployL1TokenBridgeCreator(
    l1Deployer,
    l1TokenBridgeCreatorOwner.address
  )
  console.log('L1TokenBridgeCreator', l1TokenBridgeCreator.address)

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

/**
 * Use already deployed L1TokenBridgeCreator to create and init token bridge contracts.
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
  const deployerAddress = await l1Signer.getAddress()
  const gasPrice = await l2Signer.provider!.getGasPrice()

  //// run retryable estimate for deploying L2 factory
  const l1ToL2MsgGasEstimate = new L1ToL2MessageGasEstimator(l2Signer.provider!)
  const deployFactoryGasParams = await l1ToL2MsgGasEstimate.estimateAll(
    {
      from: l1TokenBridgeCreator.address,
      to: ethers.constants.AddressZero,
      l2CallValue: BigNumber.from(0),
      excessFeeRefundAddress: deployerAddress,
      callValueRefundAddress: deployerAddress,
      data: L2AtomicTokenBridgeFactory__factory.bytecode,
    },
    await getBaseFee(l1Signer.provider!),
    l1Signer.provider!
  )

  //// run retryable estimate for deploying L2 contracts
  //// we do this estimate using L2 factory template on L1 because on L2 factory does not yet exist
  const l2FactoryTemplate = L2AtomicTokenBridgeFactory__factory.connect(
    await l1TokenBridgeCreator.l2TokenBridgeFactoryTemplate(),
    l1Signer
  )
  const l2Code = {
    router: L2GatewayRouter__factory.bytecode,
    standardGateway: L2ERC20Gateway__factory.bytecode,
    customGateway: L2CustomGateway__factory.bytecode,
    wethGateway: L2WethGateway__factory.bytecode,
    aeWeth: AeWETH__factory.bytecode,
  }
  const gasEstimateToDeployContracts =
    await l2FactoryTemplate.estimateGas.deployL2Contracts(
      l2Code,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address
    )
  const maxGasForContracts = gasEstimateToDeployContracts.mul(2)
  const maxSubmissionCostForContracts =
    deployFactoryGasParams.maxSubmissionCost.mul(5)

  let retryableValue = deployFactoryGasParams.maxSubmissionCost.add(
    deployFactoryGasParams.gasLimit.mul(gasPrice)
  )
  retryableValue = retryableValue.add(
    maxSubmissionCostForContracts.add(maxGasForContracts.mul(gasPrice))
  )

  /// do it - create token bridge
  const receipt = await (
    await l1TokenBridgeCreator.createTokenBridge(
      inboxAddress,
      deployFactoryGasParams.gasLimit,
      maxGasForContracts,
      gasPrice,
      { value: retryableValue }
    )
  ).wait()

  /// wait for execution of both tickets
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
    wethGateway: l1WethGateway,
    proxyAdmin: l1ProxyAdmin,
  } = getParsedLogs(
    receipt.logs,
    l1TokenBridgeCreator.interface,
    'OrbitTokenBridgeCreated'
  )[0].args

  /// pick up L2 contracts
  const l2Router = await l1TokenBridgeCreator.getCanonicalL2RouterAddress()
  const l2StandardGateway = L2ERC20Gateway__factory.connect(
    await l1TokenBridgeCreator.getCanonicalL2StandardGatewayAddress(),
    l2Signer
  )
  const beaconProxyFactory = await l2StandardGateway.beaconProxyFactory()
  const l2CustomGateway =
    await l1TokenBridgeCreator.getCanonicalL2CustomGatewayAddress()
  const l2WethGateway = L2WethGateway__factory.connect(
    await l1TokenBridgeCreator.getCanonicalL2WethGatewayAddress(),
    l2Signer
  )
  const l1Weth = await l2WethGateway.l1Weth()
  const l2Weth = await l2WethGateway.l2Weth()
  const l2ProxyAdmin = await l1TokenBridgeCreator.canonicalL2ProxyAdminAddress()

  return {
    l1Router,
    l1StandardGateway,
    l1CustomGateway,
    l1WethGateway,
    l1ProxyAdmin,
    l2Router,
    l2StandardGateway: l2StandardGateway.address,
    l2CustomGateway,
    l2WethGateway: l2WethGateway.address,
    l1Weth,
    l2Weth,
    beaconProxyFactory,
    l2ProxyAdmin,
  }
}

const deployL1TokenBridgeCreator = async (
  l1Signer: Signer,
  l1CreatorOwner: string
) => {
  /// deploy creator behind proxy
  const l1TokenBridgeCreatorLogic =
    await new L1AtomicTokenBridgeCreator__factory(l1Signer).deploy()
  await l1TokenBridgeCreatorLogic.deployed()

  const l1TokenBridgeCreatorProxy =
    await new TransparentUpgradeableProxy__factory(l1Signer).deploy(
      l1TokenBridgeCreatorLogic.address,
      l1CreatorOwner,
      '0x'
    )
  await l1TokenBridgeCreatorProxy.deployed()

  const l1TokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    l1TokenBridgeCreatorProxy.address,
    l1Signer
  )
  await (await l1TokenBridgeCreator.initialize()).wait()

  /// deploy L1 logic contracts
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

  const wethGatewayTemplate = await new L1WethGateway__factory(
    l1Signer
  ).deploy()
  await wethGatewayTemplate.deployed()

  /// deploy L2 contracts as placeholders on L1

  const l2TokenBridgeFactoryOnL1 =
    await new L2AtomicTokenBridgeFactory__factory(l1Signer).deploy()
  await l2TokenBridgeFactoryOnL1.deployed()

  const l2GatewayRouterOnL1 = await new L2GatewayRouter__factory(
    l1Signer
  ).deploy()
  await l2GatewayRouterOnL1.deployed()

  const l2StandardGatewayAddressOnL1 = await new L2ERC20Gateway__factory(
    l1Signer
  ).deploy()
  await l2StandardGatewayAddressOnL1.deployed()

  const l2CustomGatewayAddressOnL1 = await new L2CustomGateway__factory(
    l1Signer
  ).deploy()
  await l2CustomGatewayAddressOnL1.deployed()

  const l2WethGatewayAddressOnL1 = await new L2WethGateway__factory(
    l1Signer
  ).deploy()
  await l2WethGatewayAddressOnL1.deployed()

  const l2WethAddressOnL1 = await new AeWETH__factory(l1Signer).deploy()
  await l2WethAddressOnL1.deployed()

  const weth = ethers.Wallet.createRandom().address

  await (
    await l1TokenBridgeCreator.setTemplates(
      routerTemplate.address,
      standardGatewayTemplate.address,
      customGatewayTemplate.address,
      wethGatewayTemplate.address,
      l2TokenBridgeFactoryOnL1.address,
      l2GatewayRouterOnL1.address,
      l2StandardGatewayAddressOnL1.address,
      l2CustomGatewayAddressOnL1.address,
      l2WethGatewayAddressOnL1.address,
      l2WethAddressOnL1.address,
      weth
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

export function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function main() {
  const { l1Network, l2Network } = await setupTokenBridgeInLocalEnv()

  const NETWORK_FILE = 'network.json'
  fs.writeFileSync(
    NETWORK_FILE,
    JSON.stringify({ l1Network, l2Network }, null, 2)
  )
  console.log(NETWORK_FILE + ' updated')
}

main().then(() => console.log('Done.'))
