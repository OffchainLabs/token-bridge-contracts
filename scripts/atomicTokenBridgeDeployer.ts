import { ethers } from 'hardhat'
import {
  BigNumber,
  Contract,
  ContractFactory,
  Overrides,
  Signer,
  Wallet,
} from 'ethers'
import { Interface, hexZeroPad, defaultAbiCoder } from 'ethers/lib/utils'
import { Provider, Log } from '@ethersproject/providers'
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
  Multicall2__factory,
  IInboxProxyAdmin__factory,
  UpgradeExecutor__factory,
  L1TokenBridgeRetryableSender,
} from '../build/types'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  ParentToChildMessageGasEstimator,
  ParentToChildMessageStatus,
  ParentTransactionReceipt,
  ParentContractCallTransactionReceipt,
} from '@arbitrum/sdk'
import { exit } from 'process'
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import { ContractVerifier } from './contractVerifier'
import { OmitTyped } from '@arbitrum/sdk/dist/lib/utils/types'
import { _getScaledAmount } from './local-deployment/localDeploymentLib'
import { ParentToChildMessageGasParams } from '@arbitrum/sdk/dist/lib/message/ParentToChildMessageCreator'
import {
  concat,
  getCreate2Address,
  hexDataLength,
  keccak256,
} from 'ethers/lib/utils'

/**
 * Dummy non-zero address which is provided to logic contracts initializers
 */
const ADDRESS_DEAD = '0x000000000000000000000000000000000000dEaD'

/**
 * Types
 */
export type DeployTokenBridgeCreatorResult = {
  parentTokenBridgeCreator: L1AtomicTokenBridgeCreator
  retryableSender: L1TokenBridgeRetryableSender
}

export type VerificationRequest = {
  signer: Signer
  contractName: string
  contractAddress: string
  constructorArguments: any[]
}

// Global verification queue
let verificationQueue: VerificationRequest[] = []

// Helper function to encode constructor arguments based on their types
function abiEncodeConstructorArguments(args: any[]): string {
  if (args.length === 0) return ''

  // Infer types from the arguments
  const types: string[] = args.map(arg => {
    if (typeof arg === 'string' && arg.match(/^0x[a-fA-F0-9]{40}$/)) {
      return 'address'
    } else if (typeof arg === 'string' && arg.match(/^0x[a-fA-F0-9]*$/)) {
      return 'bytes'
    } else if (typeof arg === 'string') {
      return 'string'
    } else if (typeof arg === 'number' || BigNumber.isBigNumber(arg)) {
      return 'uint256'
    } else if (typeof arg === 'boolean') {
      return 'bool'
    } else if (Array.isArray(arg)) {
      // For arrays, detect the inner type from first element
      if (arg.length > 0) {
        const innerType =
          typeof arg[0] === 'string' && arg[0].match(/^0x[a-fA-F0-9]{40}$/)
            ? 'address'
            : 'string'
        return `${innerType}[]`
      }
      return 'string[]' // fallback
    }
    return 'bytes32' // fallback for unknown types
  })

  const abi = defaultAbiCoder
  return abi.encode(types, args)
}

// Queues a contract for verification
export function queueContractForVerification(
  signer: Signer,
  contractName: string,
  contractAddress: string,
  constructorArguments: any[] = []
): void {
  verificationQueue.push({
    signer,
    contractName,
    contractAddress,
    constructorArguments,
  })
}

// Executes all queued contract verifications
export async function verifyAllQueuedContracts(): Promise<void> {
  if (verificationQueue.length === 0) {
    return
  }

  if (!process.env.ARBISCAN_API_KEY) {
    console.warn('ARBISCAN_API_KEY is not set. Skipping contract verification.')
    verificationQueue = [] // Clear queue
    return
  }

  console.log()
  console.log(`=== Verification of contracts ===`)

  for (let i = 0; i < verificationQueue.length; i++) {
    const request = verificationQueue[i]
    await verifyContract(
      request.signer,
      request.contractName,
      request.contractAddress,
      request.constructorArguments
    )

    // Add a small delay between verifications to avoid rate limiting
    if (i < verificationQueue.length - 1) {
      await new Promise(resolve => setTimeout(resolve, 1000))
    }
  }

  // Clear the queue after processing
  verificationQueue = []

  // Allow a few seconds for all pending verifications to complete
  await new Promise(resolve => setTimeout(resolve, 3000))
}

// Verifies a contract using the `ContractVerifier`
async function verifyContract(
  signer: Signer,
  contractName: string,
  contractAddress: string,
  constructorArguments: any[] = []
): Promise<void> {
  const contractVerifier = new ContractVerifier(
    (await signer.provider!.getNetwork()).chainId,
    process.env.ARBISCAN_API_KEY!
  )

  // Encode constructor arguments if provided
  const encodedConstructorArgs =
    abiEncodeConstructorArguments(constructorArguments)

  await contractVerifier.verifyWithAddress(
    contractName,
    contractAddress,
    encodedConstructorArgs
  )
}

/**
 * @notice Deploys a contract using the provided factory class and signer.
 * @dev Supports optional contract verification and deployment via CREATE2.
 * @param FactoryClass - The contract factory class to use for deployment.
 * @param signer - The signer to deploy the contract.
 * @param constructorArgs - Arguments for the contract constructor.
 * @param verify - Whether to verify the contract after deployment.
 * @param useCreate2 - Whether to use CREATE2 for deployment.
 * @param overrides - Optional transaction overrides.
 * @return The deployed contract instance.
 */
export async function deployContract(
  FactoryClass: new (signer: Signer) => ContractFactory,
  signer: Signer,
  constructorArgs: any[] = [],
  verify = true,
  useCreate2 = false,
  overrides?: Overrides
): Promise<Contract> {
  const factory = new FactoryClass(signer)

  const deploymentArgs = [...constructorArgs]
  if (overrides) {
    deploymentArgs.push(overrides)
  }

  let contract: Contract
  if (useCreate2) {
    contract = await create2(
      factory,
      constructorArgs,
      ethers.constants.HashZero,
      overrides
    )
  } else {
    contract = await factory.deploy(...deploymentArgs)
    await contract.deployTransaction.wait()
  }

  const contractName = FactoryClass.name.replace('__factory', '')

  console.log(
    `* ${contractName} created at address: ${
      contract.address
    } ${constructorArgs.join(' ')}`
  )

  if (verify) {
    queueContractForVerification(
      signer,
      contractName,
      contract.address,
      constructorArgs
    )
  }

  return contract
}

/**
 * @notice Initializes a contract by calling its `initialize` function with the provided arguments.
 * @dev If the contract is already initialized, logs a message and does not throw.
 * @param contract The contract instance to initialize.
 * @param initializationArgs Arguments to pass to the contract's `initialize` function.
 * @throws If initialization fails for reasons other than the contract being already initialized.
 */
export async function initializeContract(
  contractName: string,
  contract: Contract,
  initializationArgs: any[] = []
): Promise<void> {
  try {
    await (await contract.initialize(...initializationArgs)).wait()
    console.log(
      ` => ${contractName} at ${contract.address} initialized successfully`
    )
  } catch (error: any) {
    // Revert reason will be in `error.error.reason`
    if (
      error.error &&
      error.error.reason &&
      [
        'execution reverted: ALREADY_INIT',
        'execution reverted: Initializable: contract is already initialized',
      ].includes(error.error.reason)
    ) {
      console.log(
        ` => ${contractName} at ${contract.address} already initialized`
      )
    } else {
      throw error
    }
  }
}

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
  l2Provider: Provider,
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
      Wallet.createRandom().address,
      Wallet.createRandom().address,
      Wallet.createRandom().address,
      Wallet.createRandom().address,
      Wallet.createRandom().address,
      Wallet.createRandom().address,
      Wallet.createRandom().address,
      Wallet.createRandom().address
    )
  const maxGasForContracts = gasEstimateToDeployContracts.mul(2)
  const maxSubmissionCostForContracts =
    deployFactoryGasParams.maxSubmissionCost.mul(2)

  const retryableFeeForFactory = maxSubmissionCostForFactory.add(
    maxGasForFactory.mul(gasPrice)
  )
  const retryableFeeForContracts = maxSubmissionCostForContracts.add(
    maxGasForContracts.mul(gasPrice)
  )

  // get inbox from rollup contract
  const inbox = await RollupAdminLogic__factory.connect(
    rollupAddress,
    l1Signer.provider!
  ).inbox()

  // if fee token is used approve the fee
  const feeToken = await _getFeeToken(inbox, l1Signer.provider!)
  if (feeToken != ethers.constants.AddressZero) {
    // scale the retryable fees to the fee token decimals denomination
    const scaledRetryableFeeForFactory = await _getScaledAmount(
      feeToken,
      retryableFeeForFactory,
      l1Signer.provider!
    )
    const scaledRetryableFeeForContracts = await _getScaledAmount(
      feeToken,
      retryableFeeForContracts,
      l1Signer.provider!
    )

    await (
      await IERC20__factory.connect(feeToken, l1Signer).approve(
        l1TokenBridgeCreator.address,
        scaledRetryableFeeForFactory.add(scaledRetryableFeeForContracts)
      )
    ).wait()
  }

  /// do it - create token bridge
  const receipt = await (
    await l1TokenBridgeCreator.createTokenBridge(
      inbox,
      rollupOwnerAddress,
      maxGasForContracts,
      gasPrice,
      {
        value:
          feeToken == ethers.constants.AddressZero
            ? retryableFeeForFactory.add(retryableFeeForContracts)
            : BigNumber.from(0),
      }
    )
  ).wait()

  console.log('Deployment TX:', receipt.transactionHash)

  /// wait for execution of both tickets
  const l1TxReceipt = new ParentTransactionReceipt(receipt)
  const messages = await l1TxReceipt.getParentToChildMessages(l2Provider)
  const messageResults = await Promise.all(
    messages.map(message => message.waitForStatus())
  )

  // if both tickets are not redeemed log it and exit
  if (
    messageResults[0].status !== ParentToChildMessageStatus.REDEEMED ||
    messageResults[1].status !== ParentToChildMessageStatus.REDEEMED
  ) {
    console.log(
      `Retryable ticket (ID ${messages[0].retryableCreationId}) status: ${
        ParentToChildMessageStatus[messageResults[0].status]
      }`
    )
    console.log(
      `Retryable ticket (ID ${messages[1].retryableCreationId}) status: ${
        ParentToChildMessageStatus[messageResults[1].status]
      }`
    )
    exit()
  }

  /// pick up L2 factory address from 1st ticket
  const l2AtomicTokenBridgeFactory =
    L2AtomicTokenBridgeFactory__factory.connect(
      messageResults[0].childTxReceipt.contractAddress,
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
 * @notice Deploys the TokenBridgeCreator and all required template contracts on the parent chain.
 *
 * This function deploys and initializes all necessary contracts for the TokenBridgeCreator on the parent chain.
 * It also configures the TokenBridgeCreator with the deployed templates.
 *
 * @param parentChainDeployer - The signer used to deploy contracts on the parent chain.
 * @param parentWethAddress - The address of the WETH token on the parent chain.
 * @param gasLimitForFactoryDeploymentOnChildChain - The gas limit to use for deploying the factory on the child chain.
 * @param verifyContracts - Optional. If true, contract verification will be performed after deployment. Defaults to false.
 * @param useCreate2 - Optional. If true, contracts will be deployed using CREATE2 for deterministic addresses. Defaults to false.
 *
 * @returns An object containing the deployed parentTokenBridgeCreator and retryableSender contract instances.
 */
export const deployTokenBridgeCreatorOnParentChain = async (
  parentChainDeployer: Signer,
  parentWethAddress: string,
  gasLimitForFactoryDeploymentOnChildChain: BigNumber,
  verifyContracts = false,
  useCreate2 = false
): Promise<DeployTokenBridgeCreatorResult> => {
  //
  // Parent chain helper contracts
  //
  // Multicall2
  const parentMulticall2 = await deployContract(
    Multicall2__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )

  //
  // Parent chain TokenBridge contracts
  // (for Arbitrum and ETH-based chains)
  //
  // Gateway router (initialized with dummy data)
  const parentGatewayRouterTemplate = await deployContract(
    L1GatewayRouter__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L1GatewayRouter', parentGatewayRouterTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  // ERC-20 Gateway (initialized with dummy data)
  const parentErc20GatewayTemplate = await deployContract(
    L1ERC20Gateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L1ERC20Gateway', parentErc20GatewayTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    hexZeroPad('0x01', 32),
    ADDRESS_DEAD,
  ])

  // Generic-custom Gateway (initialized with dummy data)
  const parentCustomGatewayTemplate = await deployContract(
    L1CustomGateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L1CustomGateway', parentCustomGatewayTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  // WETH Gateway (initialized with dummy data)
  const parentWethGatewayTemplate = await deployContract(
    L1WethGateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L1WethGateway', parentWethGatewayTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  //
  // Parent chain TokenBridge contracts
  // (for Custom Gas Token chains)
  //
  // Gateway router (initialized with dummy data)
  const parentGatewayRouterOrbitTemplate = await deployContract(
    L1OrbitGatewayRouter__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract(
    'L1OrbitGatewayRouter',
    parentGatewayRouterOrbitTemplate,
    [ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD]
  )

  // ERC-20 Gateway (initialized with dummy data)
  const parentErc20GatewayOrbitTemplate = await deployContract(
    L1OrbitERC20Gateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract(
    'L1OrbitERC20Gateway',
    parentErc20GatewayOrbitTemplate,
    [
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      ADDRESS_DEAD,
      hexZeroPad('0x01', 32),
      ADDRESS_DEAD,
    ]
  )

  // Generic-custom Gateway (initialized with dummy data)
  const parentCustomGatewayOrbitTemplate = await deployContract(
    L1OrbitCustomGateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract(
    'L1OrbitCustomGateway',
    parentCustomGatewayOrbitTemplate,
    [ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD]
  )

  //
  // Upgrade Executor
  // (Deployed using ABI and bytecode from @offchainlabs/upgrade-executor)
  //
  const upgradeExecutorTemplate = await deployContract(
    UpgradeExecutor__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('UpgradeExecutor', upgradeExecutorTemplate, [
    ADDRESS_DEAD,
    [ADDRESS_DEAD],
  ])

  //
  // ProxyAdmin
  //
  const parentTokenBridgeCreatorProxyAdmin = await deployContract(
    ProxyAdmin__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )

  //
  // Retryable sender
  //
  // RetryableSender logic contract
  // Note: this contract is initialized when the TokenBridgeCreator logic contract is initialized
  const retryableSenderLogic = await deployContract(
    L1TokenBridgeRetryableSender__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )

  // RetryableSender proxy
  // Note: this proxy is initialized when the TokenBridgeCreator is initialized
  const retryableSenderProxy = await deployContract(
    TransparentUpgradeableProxy__factory,
    parentChainDeployer,
    [
      retryableSenderLogic.address,
      parentTokenBridgeCreatorProxyAdmin.address,
      '0x',
    ],
    verifyContracts,
    useCreate2
  )

  // RetryableSender contract instance
  const retryableSender = L1TokenBridgeRetryableSender__factory.connect(
    retryableSenderProxy.address,
    parentChainDeployer
  )

  //
  // Parent chain TokenBridgeCreator
  //
  // TokenBridgeCreator logic contract
  const parentTokenBridgeCreatorLogic = await deployContract(
    L1AtomicTokenBridgeCreator__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract(
    'L1AtomicTokenBridgeCreator',
    parentTokenBridgeCreatorLogic,
    [retryableSenderLogic.address]
  )

  // TokenBridgeCreator proxy
  const parentTokenBridgeCreatorProxy = await deployContract(
    TransparentUpgradeableProxy__factory,
    parentChainDeployer,
    [
      parentTokenBridgeCreatorLogic.address,
      parentTokenBridgeCreatorProxyAdmin.address,
      '0x',
    ],
    verifyContracts,
    useCreate2
  )

  // TokenBridgeCreator contract instance
  const parentTokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    parentTokenBridgeCreatorProxy.address,
    parentChainDeployer
  )
  await initializeContract(
    'L1AtomicTokenBridgeCreator',
    parentTokenBridgeCreator,
    [retryableSender.address]
  )

  //
  // Child chain helper contracts
  //
  // ArbMulticall
  const childArbMulticall = await deployContract(
    ArbMulticall2__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )

  //
  // Child chain TokenBridge contracts
  // (deployed on the parent chain as templates)
  //
  // Gateway router (initialized with dummy data)
  const childGatewayRouterTemplate = await deployContract(
    L2GatewayRouter__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L2GatewayRouter', childGatewayRouterTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  // ERC-20 Gateway (initialized with dummy data)
  const childErc20GatewayTemplate = await deployContract(
    L2ERC20Gateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L2ERC20Gateway', childErc20GatewayTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  // Generic-custom Gateway (initialized with dummy data)
  const childCustomGatewayTemplate = await deployContract(
    L2CustomGateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L2CustomGateway', childCustomGatewayTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  // WETH Gateway (initialized with dummy data)
  const childWethGatewayTemplate = await deployContract(
    L2WethGateway__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('L2WethGateway', childWethGatewayTemplate, [
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  // WETH token contract
  const childWeth = await deployContract(
    AeWETH__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )
  await initializeContract('AeWETH', childWeth, [
    'WethTemplate',
    'WETHT',
    18,
    ADDRESS_DEAD,
    ADDRESS_DEAD,
  ])

  // TokenBridge factory
  const childTokenBridgeFactory = await deployContract(
    L2AtomicTokenBridgeFactory__factory,
    parentChainDeployer,
    [],
    verifyContracts,
    useCreate2
  )

  //
  // Set templates on TokenBridgeCreator
  //
  const parentChainTemplates = {
    routerTemplate: parentGatewayRouterTemplate.address,
    standardGatewayTemplate: parentErc20GatewayTemplate.address,
    customGatewayTemplate: parentCustomGatewayTemplate.address,
    wethGatewayTemplate: parentWethGatewayTemplate.address,
    feeTokenBasedRouterTemplate: parentGatewayRouterOrbitTemplate.address,
    feeTokenBasedStandardGatewayTemplate:
      parentErc20GatewayOrbitTemplate.address,
    feeTokenBasedCustomGatewayTemplate:
      parentCustomGatewayOrbitTemplate.address,
    upgradeExecutor: upgradeExecutorTemplate.address,
  }

  await (
    await parentTokenBridgeCreator.setTemplates(
      parentChainTemplates,
      childTokenBridgeFactory.address,
      childGatewayRouterTemplate.address,
      childErc20GatewayTemplate.address,
      childCustomGatewayTemplate.address,
      childWethGatewayTemplate.address,
      childWeth.address,
      childArbMulticall.address,
      parentWethAddress,
      parentMulticall2.address,
      gasLimitForFactoryDeploymentOnChildChain
    )
  ).wait()

  // Verify contracts
  if (verifyContracts) {
    await verifyAllQueuedContracts()
  }

  return { parentTokenBridgeCreator, retryableSender }
}

export const registerGateway = async (
  l1Executor: Signer,
  l2Provider: Provider,
  upgradeExecutor: string,
  gatewayRouter: string,
  tokens: string[],
  gateways: string[]
) => {
  const l2GatewayRouter = await L1GatewayRouter__factory.connect(
    gatewayRouter,
    l1Executor
  ).counterpartGateway()
  if ((await l2Provider.getCode(l2GatewayRouter)) === '0x') {
    throw new Error('L2GatewayRouter not yet deployed')
  }
  const l1GatewayRouter = await L2GatewayRouter__factory.connect(
    l2GatewayRouter,
    l2Provider
  ).counterpartGateway()
  if (l1GatewayRouter != gatewayRouter) {
    throw new Error('L2GatewayRouter not properly initialized')
  }

  const executorAddress = await l1Executor.getAddress()

  const buildCall = (
    params: OmitTyped<ParentToChildMessageGasParams, 'deposit'>
  ) => {
    const routerCalldata =
      L1GatewayRouter__factory.createInterface().encodeFunctionData(
        'setGateways',
        [
          tokens,
          gateways,
          params.gasLimit,
          params.maxFeePerGas,
          params.maxSubmissionCost,
        ]
      )
    return {
      data: UpgradeExecutor__factory.createInterface().encodeFunctionData(
        'executeCall',
        [gatewayRouter, routerCalldata]
      ),
      from: executorAddress,
      value: params.gasLimit
        .mul(params.maxFeePerGas)
        .add(params.maxSubmissionCost),
      to: upgradeExecutor,
    }
  }

  const estimator = new ParentToChildMessageGasEstimator(l2Provider)
  const txRequest = await estimator.populateFunctionParams(
    buildCall,
    l1Executor.provider!
  )

  const receipt = new ParentContractCallTransactionReceipt(
    await (
      await l1Executor.sendTransaction({
        to: txRequest.to,
        data: txRequest.data,
        value: txRequest.value,
      })
    ).wait()
  )

  // wait for execution of ticket
  const message = (await receipt.getParentToChildMessages(l2Provider))[0]
  const messageResult = await message.waitForStatus()
  if (messageResult.status !== ParentToChildMessageStatus.REDEEMED) {
    console.log(
      `Retryable ticket (ID ${message.retryableCreationId}) status: ${
        ParentToChildMessageStatus[messageResult.status]
      }`
    )
    exit()
  }
}

export const getEstimateForDeployingFactory = async (
  l1Deployer: Signer,
  l2Provider: Provider
) => {
  //// run retryable estimate for deploying L2 factory
  const l1DeployerAddress = await l1Deployer.getAddress()
  const l1ToL2MsgGasEstimate = new ParentToChildMessageGasEstimator(l2Provider)
  const deployFactoryGasParams = await l1ToL2MsgGasEstimate.estimateAll(
    {
      from: Wallet.createRandom().address,
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
  logs: Log[],
  iface: Interface,
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

const _getFeeToken = async (inbox: string, l1Provider: Provider) => {
  const bridge = await IInbox__factory.connect(inbox, l1Provider).bridge()

  let feeToken = ethers.constants.AddressZero

  try {
    feeToken = await IERC20Bridge__factory.connect(
      bridge,
      l1Provider
    ).nativeToken()
  } catch {
    // ignore
  }

  return feeToken
}

export function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

/**
 * @notice Deploys a contract using the CREATE2 opcode for deterministic address generation.
 * @dev The Create2 factory address can be overridden by the CREATE2_FACTORY environment variable.
 *      Default factory: https://github.com/Arachnid/deterministic-deployment-proxy/
 *
 * @param fac The contract factory used to generate the deployment bytecode.
 * @param deploymentArgs The arguments to pass to the contract constructor.
 * @param salt The 32-byte salt used for CREATE2 address calculation. Defaults to HashZero.
 * @param overrides Optional transaction overrides.
 * @return The deployed contract instance at the deterministic address.
 */
export async function create2(
  fac: ContractFactory,
  deploymentArgs: Array<any>,
  salt = ethers.constants.HashZero,
  overrides?: Overrides
): Promise<Contract> {
  if (hexDataLength(salt) !== 32) {
    throw new Error('Salt must be a 32-byte hex string')
  }

  const DEFAULT_FACTORY = '0x4e59b44847b379578588920cA78FbF26c0B4956C'
  const FACTORY = process.env.CREATE2_FACTORY ?? DEFAULT_FACTORY
  if ((await fac.signer.provider!.getCode(FACTORY)).length <= 2) {
    throw new Error(
      `Factory contract not deployed at address: ${FACTORY}${
        FACTORY.toLowerCase() === DEFAULT_FACTORY.toLowerCase()
          ? '\n(For deployment instructions, see https://github.com/Arachnid/deterministic-deployment-proxy/ )'
          : ''
      }`
    )
  }
  const data = fac.getDeployTransaction(...deploymentArgs).data
  if (!data) {
    throw new Error('No deploy data found for contract factory')
  }

  const address = getCreate2Address(FACTORY, salt, keccak256(data))
  if ((await fac.signer.provider!.getCode(address)).length > 2) {
    return fac.attach(address)
  }

  const tx = await fac.signer.sendTransaction({
    to: FACTORY,
    data: concat([salt, data]),
    ...overrides,
  })
  await tx.wait()

  return fac.attach(address)
}
