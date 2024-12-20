import { BigNumber, Contract, ContractTransaction, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import {
  ERC20__factory,
  IBridge__factory,
  IERC20__factory,
  IERC20Bridge__factory,
  IFiatToken__factory,
  IFiatTokenProxy__factory,
  IInboxBase__factory,
  L1GatewayRouter__factory,
  L1OrbitGatewayRouter__factory,
  L1OrbitUSDCGateway,
  L1OrbitUSDCGateway__factory,
  L1USDCGateway,
  L1USDCGateway__factory,
  L2GatewayRouter__factory,
  L2USDCGateway,
  L2USDCGateway__factory,
  ProxyAdmin,
  ProxyAdmin__factory,
  TransparentUpgradeableProxy__factory,
  UpgradeExecutor__factory,
} from '../../build/types'
import { JsonRpcProvider, Provider } from '@ethersproject/providers'
import dotenv from 'dotenv'
import {
  abi as SigCheckerAbi,
  bytecode as SigCheckerBytecode,
} from '@offchainlabs/stablecoin-evm/artifacts/hardhat/contracts/util/SignatureChecker.sol/SignatureChecker.json'
import {
  abi as UsdcAbi,
  bytecode as UsdcBytecode,
} from '@offchainlabs/stablecoin-evm/artifacts/hardhat/contracts/v2/FiatTokenV2_2.sol/FiatTokenV2_2.json'
import {
  abi as UsdcProxyAbi,
  bytecode as UsdcProxyBytecode,
} from '@offchainlabs/stablecoin-evm/artifacts/hardhat/contracts/v1/FiatTokenProxy.sol/FiatTokenProxy.json'
import {
  abi as MasterMinterAbi,
  bytecode as MasterMinterBytecode,
} from '@offchainlabs/stablecoin-evm/artifacts/hardhat/contracts/minting/MasterMinter.sol/MasterMinter.json'
import {
  addCustomNetwork,
  L1Network,
  L1ToL2MessageGasEstimator,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
} from '@arbitrum/sdk'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'
import fs from 'fs'

dotenv.config()

const REGISTRATION_TX_FILE = 'registerUsdcGatewayTx.json'

main().then(() => console.log('Done.'))

/**
 * USDC bridge deployment script. Script will do the following:
 * - load deployer wallets for L1 and L2
 * - register L1 and L2 networks in SDK
 * - deploy new L1 and L2 proxy admins
 * - deploy bridged (L2) USDC using the Circle's implementation
 * - init L2 USDC
 * - deploy L1 USDC gateway
 * - deploy L2 USDC gateway
 * - init both gateways
 * - if `ROLLUP_OWNER_KEY` is provided, register the gateway in the router through the UpgradeExecutor
 * - if `ROLLUP_OWNER_KEY` is not provided, prepare calldata and store it in `registerUsdcGatewayTx.json` file
 * - set minter role to L2 USDC gateway with max allowance
 */
async function main() {
  console.log('Starting USDC bridge deployment')

  _checkEnvVars()

  const { deployerL1, deployerL2 } = await _loadWallets()
  console.log('Loaded deployer wallets')

  const inbox = process.env['INBOX'] as string
  await _registerNetworks(deployerL1.provider, deployerL2.provider, inbox)
  console.log('Networks registered in SDK')

  const proxyAdminL1 = await _deployProxyAdmin(deployerL1)
  console.log('L1 ProxyAdmin deployed: ', proxyAdminL1.address)

  const proxyAdminL2 = await _deployProxyAdmin(deployerL2)
  console.log('L2 ProxyAdmin deployed: ', proxyAdminL2.address)

  const { l2Usdc, masterMinter } = await _deployBridgedUsdc(
    deployerL2,
    proxyAdminL2
  )
  console.log('Bridged (L2) USDC deployed: ', l2Usdc.address)

  const l1UsdcGateway = await _deployL1UsdcGateway(
    deployerL1,
    proxyAdminL1,
    inbox
  )
  console.log('L1 USDC gateway deployed: ', l1UsdcGateway.address)

  const l2UsdcGateway = await _deployL2UsdcGateway(deployerL2, proxyAdminL2)
  console.log('L2 USDC gateway deployed: ', l2UsdcGateway.address)

  await _initializeGateways(
    l1UsdcGateway,
    l2UsdcGateway,
    inbox,
    l2Usdc.address,
    deployerL1,
    deployerL2
  )
  console.log('Usdc gateways initialized')

  await _registerGateway(
    deployerL1.provider,
    deployerL2.provider,
    inbox,
    l1UsdcGateway.address
  )
  if (!process.env['ROLLUP_OWNER_KEY']) {
    console.log(
      'Multisig transaction to register USDC gateway prepared and stored in',
      REGISTRATION_TX_FILE
    )
  } else {
    console.log('Usdc gateway registered')
  }

  await _addMinterRoleToL2Gateway(l2UsdcGateway, deployerL2, masterMinter)
  console.log('Minter role with max allowance added to L2 gateway')
}

async function _loadWallets(): Promise<{
  deployerL1: Wallet
  deployerL2: Wallet
}> {
  const parentRpc = process.env['PARENT_RPC'] as string
  const parentDeployerKey = process.env['PARENT_DEPLOYER_KEY'] as string
  const childRpc = process.env['CHILD_RPC'] as string
  const childDeployerKey = process.env['CHILD_DEPLOYER_KEY'] as string

  const parentProvider = new JsonRpcProvider(parentRpc)
  const deployerL1 = new ethers.Wallet(parentDeployerKey, parentProvider)

  const childProvider = new JsonRpcProvider(childRpc)
  const deployerL2 = new ethers.Wallet(childDeployerKey, childProvider)

  return { deployerL1, deployerL2 }
}

async function _deployProxyAdmin(deployer: Wallet): Promise<ProxyAdmin> {
  const proxyAdminFac = await new ProxyAdmin__factory(deployer).deploy()
  return await proxyAdminFac.deployed()
}

async function _deployBridgedUsdc(
  deployerL2Wallet: Wallet,
  proxyAdminL2: ProxyAdmin
) {
  /// create l2 usdc behind proxy
  const l2UsdcLogic = await _deployUsdcLogic(deployerL2Wallet)
  const l2UsdcProxyAddress = await _deployUsdcProxy(
    deployerL2Wallet,
    l2UsdcLogic.address,
    proxyAdminL2.address
  )

  /// deploy master minter
  const masterMinterL2Fac = new ethers.ContractFactory(
    MasterMinterAbi,
    MasterMinterBytecode,
    deployerL2Wallet
  )
  const masterMinter = await masterMinterL2Fac.deploy(l2UsdcProxyAddress)

  /// init usdc proxy
  const l2UsdcFiatToken = IFiatToken__factory.connect(
    l2UsdcProxyAddress,
    deployerL2Wallet
  )

  const pauserL2 = deployerL2Wallet
  const blacklisterL2 = deployerL2Wallet
  const lostAndFound = deployerL2Wallet
  await (
    await l2UsdcFiatToken.initialize(
      'USDC',
      'USDC.e',
      'USD',
      6,
      masterMinter.address,
      pauserL2.address,
      blacklisterL2.address,
      deployerL2Wallet.address
    )
  ).wait()
  await (await l2UsdcFiatToken.initializeV2('USDC')).wait()
  await (await l2UsdcFiatToken.initializeV2_1(lostAndFound.address)).wait()
  await (await l2UsdcFiatToken.initializeV2_2([], 'USDC.e')).wait()

  /// verify initialization
  if (
    (await l2UsdcFiatToken.name()) != 'USDC' ||
    (await l2UsdcFiatToken.symbol()) != 'USDC.e' ||
    (await l2UsdcFiatToken.currency()) != 'USD' ||
    (await l2UsdcFiatToken.decimals()) != 6 ||
    (await l2UsdcFiatToken.masterMinter()) != masterMinter.address ||
    (await l2UsdcFiatToken.pauser()) != pauserL2.address ||
    (await l2UsdcFiatToken.blacklister()) != blacklisterL2.address ||
    (await l2UsdcFiatToken.owner()) != deployerL2Wallet.address
  ) {
    throw new Error(
      'Bridged USDC initialization was not successful, might have been frontrun'
    )
  }

  /// init usdc logic to dummy values
  const l2UsdcLogicInit = IFiatToken__factory.connect(
    l2UsdcLogic.address,
    deployerL2Wallet
  )
  const DEAD = '0x000000000000000000000000000000000000dEaD'
  await (
    await l2UsdcLogicInit.initialize('', '', '', 0, DEAD, DEAD, DEAD, DEAD)
  ).wait()
  await (await l2UsdcLogicInit.initializeV2('')).wait()
  await (await l2UsdcLogicInit.initializeV2_1(DEAD)).wait()
  await (await l2UsdcLogicInit.initializeV2_2([], '')).wait()

  /// verify logic initialization
  if (
    (await l2UsdcLogicInit.name()) != '' ||
    (await l2UsdcLogicInit.symbol()) != '' ||
    (await l2UsdcLogicInit.currency()) != '' ||
    (await l2UsdcLogicInit.decimals()) != 0 ||
    (await l2UsdcLogicInit.masterMinter()) != DEAD ||
    (await l2UsdcLogicInit.pauser()) != DEAD ||
    (await l2UsdcLogicInit.blacklister()) != DEAD ||
    (await l2UsdcLogicInit.owner()) != DEAD
  ) {
    throw new Error('Bridged USDC logic initialization was not successful')
  }

  const l2Usdc = IERC20__factory.connect(
    l2UsdcFiatToken.address,
    deployerL2Wallet
  )

  return { l2Usdc, masterMinter }
}

async function _deployUsdcLogic(deployer: Wallet) {
  /// deploy sig checker library
  const sigCheckerFac = new ethers.ContractFactory(
    SigCheckerAbi,
    SigCheckerBytecode,
    deployer
  )
  const sigCheckerLib = await sigCheckerFac.deploy()

  // link library to usdc bytecode
  const bytecodeWithPlaceholder: string = UsdcBytecode
  const placeholder = '__$715109b5d747ea58b675c6ea3f0dba8c60$__'

  const libAddressStripped = sigCheckerLib.address.replace(/^0x/, '')
  const bridgedUsdcLogicBytecode = bytecodeWithPlaceholder
    .split(placeholder)
    .join(libAddressStripped)

  // deploy bridged usdc logic
  const bridgedUsdcLogicFactory = new ethers.ContractFactory(
    UsdcAbi,
    bridgedUsdcLogicBytecode,
    deployer
  )
  const bridgedUsdcLogic = await bridgedUsdcLogicFactory.deploy()

  return bridgedUsdcLogic
}

async function _deployUsdcProxy(
  deployer: Wallet,
  bridgedUsdcLogic: string,
  proxyAdmin: string
) {
  /// deploy circle's proxy used for usdc
  const usdcProxyFactory = new ethers.ContractFactory(
    UsdcProxyAbi,
    UsdcProxyBytecode,
    deployer
  )
  const usdcProxy = await usdcProxyFactory.deploy(bridgedUsdcLogic)

  /// set proxy admin
  await (
    await IFiatTokenProxy__factory.connect(
      usdcProxy.address,
      deployer
    ).changeAdmin(proxyAdmin)
  ).wait()

  return usdcProxy.address
}

async function _deployL1UsdcGateway(
  deployerL1: Wallet,
  proxyAdmin: ProxyAdmin,
  inboxAddress: string
): Promise<L1USDCGateway | L1OrbitUSDCGateway> {
  const isFeeToken =
    (await _getFeeToken(inboxAddress, deployerL1.provider)) !=
    ethers.constants.AddressZero

  const l1UsdcGatewayFactory = isFeeToken
    ? await new L1OrbitUSDCGateway__factory(deployerL1).deploy()
    : await new L1USDCGateway__factory(deployerL1).deploy()
  const l1UsdcGatewayLogic = await l1UsdcGatewayFactory.deployed()
  const tupFactory = await new TransparentUpgradeableProxy__factory(
    deployerL1
  ).deploy(l1UsdcGatewayLogic.address, proxyAdmin.address, '0x')
  const tup = await tupFactory.deployed()
  return isFeeToken
    ? L1OrbitUSDCGateway__factory.connect(tup.address, deployerL1)
    : L1USDCGateway__factory.connect(tup.address, deployerL1)
}

async function _deployL2UsdcGateway(
  deployerL2: Wallet,
  proxyAdmin: ProxyAdmin
): Promise<L2USDCGateway> {
  const l2USDCCustomGatewayFactory = await new L2USDCGateway__factory(
    deployerL2
  ).deploy()
  const l2USDCCustomGatewayLogic = await l2USDCCustomGatewayFactory.deployed()
  const tupFactory = await new TransparentUpgradeableProxy__factory(
    deployerL2
  ).deploy(l2USDCCustomGatewayLogic.address, proxyAdmin.address, '0x')
  const tup = await tupFactory.deployed()
  return L2USDCGateway__factory.connect(tup.address, deployerL2)
}

/**
 * Initialize gateways
 */
async function _initializeGateways(
  l1UsdcGateway: L1USDCGateway | L1OrbitUSDCGateway,
  l2UsdcGateway: L2USDCGateway,
  inbox: string,
  l2Usdc: string,
  deployerL1: Wallet,
  deployerL2: Wallet
) {
  const l1Router = process.env['L1_ROUTER'] as string
  const l2Router = process.env['L2_ROUTER'] as string
  const l1Usdc = process.env['L1_USDC'] as string

  /// initialize L1 gateway
  const _l2CounterPart = l2UsdcGateway.address
  const _owner = deployerL1.address

  await (
    await l1UsdcGateway
      .connect(deployerL1)
      .initialize(_l2CounterPart, l1Router, inbox, l1Usdc, l2Usdc, _owner)
  ).wait()

  /// initialize L2 gateway
  const _l1Counterpart = l1UsdcGateway.address
  const ownerL2 = deployerL2.address
  await (
    await l2UsdcGateway.initialize(
      _l1Counterpart,
      l2Router,
      l1Usdc,
      l2Usdc,
      ownerL2
    )
  ).wait()

  ///// verify initialization
  if (
    (await l1UsdcGateway.counterpartGateway()).toLowerCase() !=
    _l2CounterPart.toLowerCase()
  ) {
    console.log('_l2CounterPart')
  }
  if (
    (await l1UsdcGateway.router()).toLowerCase() != l1Router.toLowerCase() ||
    (await l1UsdcGateway.inbox()).toLowerCase() != inbox.toLowerCase() ||
    (await l1UsdcGateway.l1USDC()).toLowerCase() != l1Usdc.toLowerCase() ||
    (await l1UsdcGateway.l2USDC()).toLowerCase() != l2Usdc.toLowerCase() ||
    (await l1UsdcGateway.owner()).toLowerCase() != _owner.toLowerCase() ||
    (await l1UsdcGateway.counterpartGateway()).toLowerCase() !=
      _l2CounterPart.toLowerCase()
  ) {
    throw new Error('L1 USDC gateway initialization failed')
  }

  if (
    (await l2UsdcGateway.counterpartGateway()).toLowerCase() !=
      _l1Counterpart.toLowerCase() ||
    (await l2UsdcGateway.router()).toLowerCase() != l2Router.toLowerCase() ||
    (await l2UsdcGateway.l1USDC()).toLowerCase() != l1Usdc.toLowerCase() ||
    (await l2UsdcGateway.l2USDC()).toLowerCase() != l2Usdc.toLowerCase() ||
    (await l2UsdcGateway.owner()).toLowerCase() != ownerL2.toLowerCase()
  ) {
    throw new Error('L2 USDC gateway initialization failed')
  }
}

/**
 * Do the gateway registration if rollup owner key is provided.
 * Otherwise prepare the TX payload and store it in a file.
 */
async function _registerGateway(
  parentProvider: Provider,
  childProvider: Provider,
  inbox: string,
  l1UsdcGatewayAddress: string
) {
  const isFeeToken =
    (await _getFeeToken(inbox, parentProvider)) != ethers.constants.AddressZero

  const l1RouterAddress = process.env['L1_ROUTER'] as string
  const l2RouterAddress = process.env['L2_ROUTER'] as string
  const l1UsdcAddress = process.env['L1_USDC'] as string

  const l1Router = isFeeToken
    ? L1OrbitGatewayRouter__factory.connect(l1RouterAddress, parentProvider)
    : L1GatewayRouter__factory.connect(l1RouterAddress, parentProvider)

  /// load upgrade executor
  const routerOwnerAddress = await l1Router.owner()
  if (!(await _isUpgradeExecutor(routerOwnerAddress, parentProvider))) {
    throw new Error('Router owner is expected to be an UpgradeExecutor')
  }
  const upgradeExecutor = UpgradeExecutor__factory.connect(
    routerOwnerAddress,
    parentProvider
  )

  /// prepare calldata for executor
  const routerRegistrationData =
    L2GatewayRouter__factory.createInterface().encodeFunctionData(
      'setGateway',
      [[l1UsdcAddress], [l1UsdcGatewayAddress]]
    )

  const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(childProvider)
  const retryableParams = await l1ToL2MessageGasEstimate.estimateAll(
    {
      from: l1RouterAddress,
      to: l2RouterAddress,
      l2CallValue: BigNumber.from(0),
      excessFeeRefundAddress: ethers.Wallet.createRandom().address,
      callValueRefundAddress: ethers.Wallet.createRandom().address,
      data: routerRegistrationData,
    },
    await getBaseFee(parentProvider),
    parentProvider
  )

  const maxGas = retryableParams.gasLimit
  const gasPriceBid = retryableParams.maxFeePerGas.mul(3)
  const maxSubmissionCost = retryableParams.maxSubmissionCost
  let totalFee = maxGas.mul(gasPriceBid).add(maxSubmissionCost)
  if (isFeeToken) {
    totalFee = await _getPrescaledAmount(
      await _getFeeToken(inbox, parentProvider),
      parentProvider,
      totalFee
    )
  }

  const registrationCalldata = isFeeToken
    ? L1OrbitGatewayRouter__factory.createInterface().encodeFunctionData(
        'setGateways(address[],address[],uint256,uint256,uint256,uint256)',
        [
          [l1UsdcAddress],
          [l1UsdcGatewayAddress],
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          totalFee,
        ]
      )
    : L1GatewayRouter__factory.createInterface().encodeFunctionData(
        'setGateways(address[],address[],uint256,uint256,uint256)',
        [
          [l1UsdcAddress],
          [l1UsdcGatewayAddress],
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
        ]
      )

  if (!process.env['ROLLUP_OWNER_KEY']) {
    // prepare multisig transaction(s)

    const txs = []
    if (isFeeToken) {
      // prepare TX to transfer fee amount to upgrade executor
      const feeTokenContract = IERC20__factory.connect(
        await _getFeeToken(inbox, parentProvider),
        parentProvider
      )
      const feeTransferData = feeTokenContract.interface.encodeFunctionData(
        'transfer',
        [upgradeExecutor.address, totalFee]
      )
      txs.push({
        to: feeTokenContract.address,
        value: BigNumber.from(0).toString(),
        data: feeTransferData,
      })

      // prepare TX to approve router to spend the fee token
      const approveData = feeTokenContract.interface.encodeFunctionData(
        'approve',
        [l1RouterAddress, totalFee]
      )
      txs.push({
        to: upgradeExecutor.address,
        value: BigNumber.from(0).toString(),
        data: approveData,
      })
    }

    const upgExecutorData = upgradeExecutor.interface.encodeFunctionData(
      'executeCall',
      [l1Router.address, registrationCalldata]
    )
    const to = upgradeExecutor.address

    // store the multisig transaction to file
    txs.push({
      to,
      value: isFeeToken ? BigNumber.from(0).toString() : totalFee.toString(),
      data: upgExecutorData,
    })
    fs.writeFileSync(REGISTRATION_TX_FILE, JSON.stringify(txs))
  } else {
    // load rollup owner (account with executor rights on the upgrade executor)
    const rollupOwnerKey = process.env['ROLLUP_OWNER_KEY'] as string
    const rollupOwner = new ethers.Wallet(rollupOwnerKey, parentProvider)

    if (isFeeToken) {
      // transfer the fee amount to upgrade executor
      const feeToken = await _getFeeToken(inbox, parentProvider)
      const feeTokenContract = IERC20__factory.connect(feeToken, rollupOwner)
      await (
        await feeTokenContract
          .connect(rollupOwner)
          .transfer(upgradeExecutor.address, totalFee)
      ).wait()

      // approve router to spend the fee token
      await (
        await upgradeExecutor
          .connect(rollupOwner)
          .executeCall(
            feeToken,
            feeTokenContract.interface.encodeFunctionData('approve', [
              l1RouterAddress,
              totalFee,
            ])
          )
      ).wait()
    }

    // execute the registration
    const gwRegistrationTx = await upgradeExecutor
      .connect(rollupOwner)
      .executeCall(l1Router.address, registrationCalldata, {
        value: isFeeToken ? BigNumber.from(0) : totalFee,
      })
    await _waitOnL2Msg(gwRegistrationTx, childProvider)
  }
}

/**
 * Master minter (this script set it to deployer) adds minter role to L2 gateway
 * with max allowance.
 */
async function _addMinterRoleToL2Gateway(
  l2UsdcGateway: L2USDCGateway,
  masterMinterOwner: Wallet,
  masterMinter: Contract
) {
  await (
    await masterMinter['configureController(address,address)'](
      masterMinterOwner.address,
      l2UsdcGateway.address
    )
  ).wait()

  await (
    await masterMinter['configureMinter(uint256)'](ethers.constants.MaxUint256)
  ).wait()
}

/**
 * Check if owner is UpgardeExecutor by polling ADMIN_ROLE() and EXECUTOR_ROLE()
 */
async function _isUpgradeExecutor(
  routerOwnerAddress: string,
  provider: Provider
): Promise<boolean> {
  const upgExecutor = UpgradeExecutor__factory.connect(
    routerOwnerAddress,
    provider
  )
  try {
    await upgExecutor.ADMIN_ROLE()
    await upgExecutor.EXECUTOR_ROLE()
  } catch {
    return false
  }

  return true
}

/**
 * Wait for L1->L2 message to be redeemed
 */
async function _waitOnL2Msg(tx: ContractTransaction, childProvider: Provider) {
  const retryableReceipt = await tx.wait()
  const l1TxReceipt = new L1TransactionReceipt(retryableReceipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(childProvider)

  // 1 msg expected
  const messageResult = await messages[0].waitForStatus()
  const status = messageResult.status

  if (status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error('L1->L2 message not redeemed')
  }
}

/**
 * Register L1 and L2 networks in the SDK
 * @param l1Provider
 * @param l2Provider
 * @param inboxAddress
 * @returns
 */
async function _registerNetworks(
  l1Provider: Provider,
  l2Provider: Provider,
  inboxAddress: string
): Promise<{
  l1Network: L1Network
  l2Network: Omit<L2Network, 'tokenBridge'>
}> {
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

  const rollupAddress = await IBridge__factory.connect(
    await IInboxBase__factory.connect(inboxAddress, l1Provider).bridge(),
    l1Provider
  ).rollup()
  const rollup = RollupAdminLogic__factory.connect(rollupAddress, l1Provider)
  const l2Network: L2Network = {
    blockTime: 10,
    partnerChainIDs: [],
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

/**
 * Fetch fee token if it exists or return zero address
 */
async function _getFeeToken(
  inbox: string,
  provider: Provider
): Promise<string> {
  const bridge = await IInboxBase__factory.connect(inbox, provider).bridge()

  let feeToken = ethers.constants.AddressZero

  try {
    feeToken = await IERC20Bridge__factory.connect(
      bridge,
      provider
    ).nativeToken()
  } catch {
    // ignore
  }

  return feeToken
}

/**
 * Check if all required env vars are set
 */
function _checkEnvVars() {
  const requiredEnvVars = [
    'PARENT_RPC',
    'PARENT_DEPLOYER_KEY',
    'CHILD_RPC',
    'CHILD_DEPLOYER_KEY',
    'L1_ROUTER',
    'L2_ROUTER',
    'INBOX',
    'L1_USDC',
  ]

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`Missing env var ${envVar}`)
    }
  }
}

async function _getPrescaledAmount(
  nativeTokenAddress: string,
  provider: Provider,
  amount: BigNumber
): Promise<BigNumber> {
  const nativeToken = ERC20__factory.connect(nativeTokenAddress, provider)
  const decimals = BigNumber.from(await nativeToken.decimals())
  if (decimals.lt(BigNumber.from(18))) {
    const scalingFactor = BigNumber.from(10).pow(
      BigNumber.from(18).sub(decimals)
    )
    let prescaledAmount = amount.div(scalingFactor)
    // round up if needed
    if (prescaledAmount.mul(scalingFactor).lt(amount)) {
      prescaledAmount = prescaledAmount.add(BigNumber.from(1))
    }
    return prescaledAmount
  } else if (decimals.gt(BigNumber.from(18))) {
    return amount.mul(BigNumber.from(10).pow(decimals.sub(BigNumber.from(18))))
  }

  return amount
}
