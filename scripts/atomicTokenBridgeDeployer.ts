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
  ProxyAdmin__factory,
  L1TokenBridgeRetryableSender__factory,
  L1OrbitERC20Gateway__factory,
  L1OrbitCustomGateway__factory,
  L1OrbitGatewayRouter__factory,
  IInbox__factory,
  IERC20Bridge__factory,
  IERC20__factory,
  ArbMulticall2__factory,
  IRollupCore__factory,
  IBridge__factory,
  Multicall2__factory,
  IInboxProxyAdmin__factory,
} from '../build/types'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  L1ToL2MessageGasEstimator,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
} from '@arbitrum/sdk'
import { exit } from 'process'
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import { ContractVerifier } from './contractVerifier'

/**
 * Dummy non-zero address which is provided to logic contracts initializers
 */
const ADDRESS_DEAD = '0x000000000000000000000000000000000000dEaD'

/**
 * Use already deployed L1TokenBridgeCreator to create and init token bridge contracts.
 * Function first gets estimates for 2 retryable tickets - one for deploying L2 factory and
 * one for deploying L2 side of token bridge. Then it creates retryables, waits for
 * until they're executed, and finally it picks up addresses of new contracts.
 *
 * @param l1Signer
 * @param l2Provider
 * @param l1TokenBridgeCreator
 * @param rollupAddress
 * @returns
 */
export const createTokenBridge = async (
  l1Signer: Signer,
  l2Provider: ethers.providers.Provider,
  l1TokenBridgeCreator: L1AtomicTokenBridgeCreator,
  rollupAddress: string,
  rollupOwnerAddress: string
) => {
  const gasPrice = await l2Provider.getGasPrice()

  //// run retryable estimate for deploying L2 factory
  const deployFactoryGasParams = await getEstimateForDeployingFactory(
    l1Signer,
    l2Provider
  )

  const maxGasForFactory =
    await l1TokenBridgeCreator.gasLimitForL2FactoryDeployment()
  const maxSubmissionCostForFactory = deployFactoryGasParams.maxSubmissionCost

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
    upgradeExecutor: UpgradeExecutorBytecode,
    multicall: ArbMulticall2__factory.bytecode,
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
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address
    )
  const maxGasForContracts = gasEstimateToDeployContracts.mul(2)
  const maxSubmissionCostForContracts =
    deployFactoryGasParams.maxSubmissionCost.mul(2)

  let retryableFee = maxSubmissionCostForFactory
    .add(maxSubmissionCostForContracts)
    .add(maxGasForFactory.mul(gasPrice))
    .add(maxGasForContracts.mul(gasPrice))

  // get inbox from rollup contract
  const inbox = await RollupAdminLogic__factory.connect(
    rollupAddress,
    l1Signer.provider!
  ).inbox()

  // if fee token is used approve the fee
  const feeToken = await _getFeeToken(inbox, l1Signer.provider!)
  if (feeToken != ethers.constants.AddressZero) {
    await (
      await IERC20__factory.connect(feeToken, l1Signer).approve(
        l1TokenBridgeCreator.address,
        retryableFee
      )
    ).wait()
    retryableFee = BigNumber.from(0)
  }

  /// do it - create token bridge
  const receipt = await (
    await l1TokenBridgeCreator.createTokenBridge(
      inbox,
      rollupOwnerAddress,
      maxGasForContracts,
      gasPrice,
      { value: retryableFee }
    )
  ).wait()

  console.log('Deployment TX:', receipt.transactionHash)

  /// wait for execution of both tickets
  const l1TxReceipt = new L1TransactionReceipt(receipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(l2Provider)
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
      l2Provider
    )
  console.log('L2AtomicTokenBridgeFactory', l2AtomicTokenBridgeFactory.address)

  /// fetch deployment addresses from registry
  const l1Deployment = await l1TokenBridgeCreator.inboxToL1Deployment(inbox)
  const l2Deployment = await l1TokenBridgeCreator.inboxToL2Deployment(inbox)

  /// fetch l1 multicall and l1 proxy admin from creator
  const l1MultiCall = await l1TokenBridgeCreator.l1Multicall()
  const l1ProxyAdmin = await IInboxProxyAdmin__factory.connect(
    inbox,
    l1Signer.provider!
  ).getProxyAdmin()

  return { l1Deployment, l2Deployment, l1MultiCall, l1ProxyAdmin }
}

/**
 * Deploy token bridge creator contract to base chain and set all the templates
 * @param l1Deployer
 * @param l2Provider
 * @param l1WethAddress
 * @returns
 */
export const deployL1TokenBridgeCreator = async (
  l1Deployer: Signer,
  l1WethAddress: string,
  gasLimitForL2FactoryDeployment: BigNumber,
  verifyContracts: boolean = false
) => {
  /// deploy creator behind proxy
  const l2MulticallAddressOnL1Fac = await new ArbMulticall2__factory(
    l1Deployer
  ).deploy()
  const l2MulticallAddressOnL1 = await l2MulticallAddressOnL1Fac.deployed()

  const l1TokenBridgeCreatorProxyAdmin = await new ProxyAdmin__factory(
    l1Deployer
  ).deploy()
  await l1TokenBridgeCreatorProxyAdmin.deployed()

  const l1TokenBridgeCreatorLogic =
    await new L1AtomicTokenBridgeCreator__factory(l1Deployer).deploy()
  await l1TokenBridgeCreatorLogic.deployed()

  const l1TokenBridgeCreatorProxy =
    await new TransparentUpgradeableProxy__factory(l1Deployer).deploy(
      l1TokenBridgeCreatorLogic.address,
      l1TokenBridgeCreatorProxyAdmin.address,
      '0x'
    )
  await l1TokenBridgeCreatorProxy.deployed()

  const l1TokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    l1TokenBridgeCreatorProxy.address,
    l1Deployer
  )

  /// deploy retryable sender behind proxy
  const retryableSenderLogic = await new L1TokenBridgeRetryableSender__factory(
    l1Deployer
  ).deploy()
  await retryableSenderLogic.deployed()

  const retryableSenderProxy = await new TransparentUpgradeableProxy__factory(
    l1Deployer
  ).deploy(
    retryableSenderLogic.address,
    l1TokenBridgeCreatorProxyAdmin.address,
    '0x'
  )
  await retryableSenderProxy.deployed()

  const retryableSender = L1TokenBridgeRetryableSender__factory.connect(
    retryableSenderProxy.address,
    l1Deployer
  )

  // initialize retryable sender logic contract
  await (await retryableSenderLogic.initialize()).wait()

  /// init creator
  await (await l1TokenBridgeCreator.initialize(retryableSender.address)).wait()

  /// deploy L1 logic contracts. Initialize them with dummy data
  const routerTemplate = await new L1GatewayRouter__factory(l1Deployer).deploy()
  await routerTemplate.deployed()
  await (
    await routerTemplate.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD
    )
  ).wait()

  const standardGatewayTemplate = await new L1ERC20Gateway__factory(
    l1Deployer
  ).deploy()
  await standardGatewayTemplate.deployed()
  await (
    await standardGatewayTemplate.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ethers.utils.hexZeroPad('0x01', 32),
      ADDRESS_DEAD
    )
  ).wait()

  const customGatewayTemplate = await new L1CustomGateway__factory(
    l1Deployer
  ).deploy()
  await customGatewayTemplate.deployed()
  await (
    await customGatewayTemplate.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD
    )
  ).wait()

  const wethGatewayTemplate = await new L1WethGateway__factory(
    l1Deployer
  ).deploy()
  await wethGatewayTemplate.deployed()
  await (
    await wethGatewayTemplate.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD
    )
  ).wait()

  const feeTokenBasedRouterTemplate = await new L1OrbitGatewayRouter__factory(
    l1Deployer
  ).deploy()
  await feeTokenBasedRouterTemplate.deployed()
  await (
    await feeTokenBasedRouterTemplate.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD
    )
  ).wait()

  const feeTokenBasedStandardGatewayTemplate =
    await new L1OrbitERC20Gateway__factory(l1Deployer).deploy()
  await feeTokenBasedStandardGatewayTemplate.deployed()
  await (
    await feeTokenBasedStandardGatewayTemplate.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ethers.utils.hexZeroPad('0x01', 32),
      ADDRESS_DEAD
    )
  ).wait()

  const feeTokenBasedCustomGatewayTemplate =
    await new L1OrbitCustomGateway__factory(l1Deployer).deploy()
  await feeTokenBasedCustomGatewayTemplate.deployed()
  await (
    await feeTokenBasedCustomGatewayTemplate.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD
    )
  ).wait()

  const upgradeExecutorFactory = new ethers.ContractFactory(
    UpgradeExecutorABI,
    UpgradeExecutorBytecode,
    l1Deployer
  )
  const upgradeExecutor = await upgradeExecutorFactory.deploy()

  const l1Templates = {
    routerTemplate: routerTemplate.address,
    standardGatewayTemplate: standardGatewayTemplate.address,
    customGatewayTemplate: customGatewayTemplate.address,
    wethGatewayTemplate: wethGatewayTemplate.address,
    feeTokenBasedRouterTemplate: feeTokenBasedRouterTemplate.address,
    feeTokenBasedStandardGatewayTemplate:
      feeTokenBasedStandardGatewayTemplate.address,
    feeTokenBasedCustomGatewayTemplate:
      feeTokenBasedCustomGatewayTemplate.address,
    upgradeExecutor: upgradeExecutor.address,
  }

  /// deploy L2 contracts as placeholders on L1. Initialize them with dummy data
  const l2TokenBridgeFactoryOnL1 =
    await new L2AtomicTokenBridgeFactory__factory(l1Deployer).deploy()
  await l2TokenBridgeFactoryOnL1.deployed()

  const l2GatewayRouterOnL1 = await new L2GatewayRouter__factory(
    l1Deployer
  ).deploy()
  await l2GatewayRouterOnL1.deployed()
  await (
    await l2GatewayRouterOnL1.initialize(ADDRESS_DEAD, ADDRESS_DEAD)
  ).wait()

  const l2StandardGatewayAddressOnL1 = await new L2ERC20Gateway__factory(
    l1Deployer
  ).deploy()
  await l2StandardGatewayAddressOnL1.deployed()
  await (
    await l2StandardGatewayAddressOnL1.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD
    )
  ).wait()

  const l2CustomGatewayAddressOnL1 = await new L2CustomGateway__factory(
    l1Deployer
  ).deploy()
  await l2CustomGatewayAddressOnL1.deployed()
  await (
    await l2CustomGatewayAddressOnL1.initialize(ADDRESS_DEAD, ADDRESS_DEAD)
  ).wait()

  const l2WethGatewayAddressOnL1 = await new L2WethGateway__factory(
    l1Deployer
  ).deploy()
  await l2WethGatewayAddressOnL1.deployed()
  await (
    await l2WethGatewayAddressOnL1.initialize(
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD
    )
  ).wait()

  const l2WethAddressOnL1 = await new AeWETH__factory(l1Deployer).deploy()
  await l2WethAddressOnL1.deployed()

  const l1Multicall = await new Multicall2__factory(l1Deployer).deploy()
  await l1Multicall.deployed()

  await (
    await l1TokenBridgeCreator.setTemplates(
      l1Templates,
      l2TokenBridgeFactoryOnL1.address,
      l2GatewayRouterOnL1.address,
      l2StandardGatewayAddressOnL1.address,
      l2CustomGatewayAddressOnL1.address,
      l2WethGatewayAddressOnL1.address,
      l2WethAddressOnL1.address,
      l2MulticallAddressOnL1.address,
      l1WethAddress,
      l1Multicall.address,
      gasLimitForL2FactoryDeployment
    )
  ).wait()

  ///// verify contracts
  if (verifyContracts) {
    console.log('\n\n Start contract verification \n\n')
    const l1Verifier = new ContractVerifier(
      (await l1Deployer.provider!.getNetwork()).chainId,
      process.env.ARBISCAN_API_KEY!
    )
    const abi = ethers.utils.defaultAbiCoder

    await l1Verifier.verifyWithAddress(
      'l1TokenBridgeCreatorProxyAdmin',
      l1TokenBridgeCreatorProxyAdmin.address
    )
    await l1Verifier.verifyWithAddress(
      'l1TokenBridgeCreatorLogic',
      l1TokenBridgeCreatorLogic.address,
      abi.encode(['address'], [l2MulticallAddressOnL1.address])
    )
    await l1Verifier.verifyWithAddress(
      'l1TokenBridgeCreatorProxy',
      l1TokenBridgeCreatorProxy.address,
      abi.encode(
        ['address', 'address', 'bytes'],
        [
          l1TokenBridgeCreatorLogic.address,
          l1TokenBridgeCreatorProxyAdmin.address,
          '0x',
        ]
      )
    )
    await l1Verifier.verifyWithAddress(
      'retryableSenderLogic',
      retryableSenderLogic.address
    )
    await l1Verifier.verifyWithAddress(
      'retryableSenderProxy',
      retryableSenderProxy.address,
      abi.encode(
        ['address', 'address', 'bytes'],
        [
          retryableSenderLogic.address,
          l1TokenBridgeCreatorProxyAdmin.address,
          '0x',
        ]
      )
    )
    await l1Verifier.verifyWithAddress('routerTemplate', routerTemplate.address)
    await l1Verifier.verifyWithAddress(
      'standardGatewayTemplate',
      standardGatewayTemplate.address
    )
    await l1Verifier.verifyWithAddress(
      'customGatewayTemplate',
      customGatewayTemplate.address
    )
    await l1Verifier.verifyWithAddress(
      'wethGatewayTemplate',
      wethGatewayTemplate.address
    )
    await l1Verifier.verifyWithAddress(
      'feeTokenBasedRouterTemplate',
      feeTokenBasedRouterTemplate.address
    )
    await l1Verifier.verifyWithAddress(
      'feeTokenBasedStandardGatewayTemplate',
      feeTokenBasedStandardGatewayTemplate.address
    )
    await l1Verifier.verifyWithAddress(
      'feeTokenBasedCustomGatewayTemplate',
      feeTokenBasedCustomGatewayTemplate.address
    )
    await l1Verifier.verifyWithAddress(
      'upgradeExecutor',
      upgradeExecutor.address,
      '',
      20000
    )
    await l1Verifier.verifyWithAddress(
      'l2TokenBridgeFactoryOnL1',
      l2TokenBridgeFactoryOnL1.address
    )
    await l1Verifier.verifyWithAddress(
      'l2GatewayRouterOnL1',
      l2GatewayRouterOnL1.address
    )
    await l1Verifier.verifyWithAddress(
      'l2StandardGatewayAddressOnL1',
      l2StandardGatewayAddressOnL1.address
    )
    await l1Verifier.verifyWithAddress(
      'l2CustomGatewayAddressOnL1',
      l2CustomGatewayAddressOnL1.address
    )
    await l1Verifier.verifyWithAddress(
      'l2WethGatewayAddressOnL1',
      l2WethGatewayAddressOnL1.address
    )
    await l1Verifier.verifyWithAddress(
      'l2WethAddressOnL1',
      l2WethAddressOnL1.address
    )
    await l1Verifier.verifyWithAddress(
      'l2MulticallAddressOnL1',
      l2MulticallAddressOnL1.address
    )

    await l1Verifier.verifyWithAddress('l1Multicall', l1Multicall.address)

    await new Promise(resolve => setTimeout(resolve, 2000))
    console.log('\n\n Contract verification done \n\n')
  }

  return { l1TokenBridgeCreator, retryableSender }
}

export const getEstimateForDeployingFactory = async (
  l1Deployer: Signer,
  l2Provider: ethers.providers.Provider
) => {
  //// run retryable estimate for deploying L2 factory
  const l1DeployerAddress = await l1Deployer.getAddress()
  const l1ToL2MsgGasEstimate = new L1ToL2MessageGasEstimator(l2Provider)
  const deployFactoryGasParams = await l1ToL2MsgGasEstimate.estimateAll(
    {
      from: ethers.Wallet.createRandom().address,
      to: ethers.constants.AddressZero,
      l2CallValue: BigNumber.from(0),
      excessFeeRefundAddress: l1DeployerAddress,
      callValueRefundAddress: l1DeployerAddress,
      data: L2AtomicTokenBridgeFactory__factory.bytecode,
    },
    await getBaseFee(l1Deployer.provider!),
    l1Deployer.provider!
  )

  return deployFactoryGasParams
}

export const getSigner = (provider: JsonRpcProvider, key?: string) => {
  if (!key && !provider)
    throw new Error('Provide at least one of key or provider.')
  if (key) return new Wallet(key).connect(provider)
  else return provider.getSigner(0)
}

export const getParsedLogs = (
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

const _getFeeToken = async (
  inbox: string,
  l1Provider: ethers.providers.Provider
) => {
  const bridge = await IInbox__factory.connect(inbox, l1Provider).bridge()

  let feeToken = ethers.constants.AddressZero

  try {
    feeToken = await IERC20Bridge__factory.connect(
      bridge,
      l1Provider
    ).nativeToken()
  } catch {}

  return feeToken
}

export function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms))
}
