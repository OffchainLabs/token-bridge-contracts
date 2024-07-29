import { BigNumber, ContractTransaction, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import {
  IBridge__factory,
  IERC20__factory,
  IFiatToken__factory,
  IFiatTokenProxy__factory,
  IInboxBase__factory,
  L1GatewayRouter__factory,
  L1USDCGateway,
  L1USDCGateway__factory,
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
  addCustomNetwork,
  L1Network,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
} from '@arbitrum/sdk'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'

dotenv.config()

main().then(() => console.log('Done.'))

async function main() {
  _checkEnvVars()
  const { deployerL1, deployerL2, rollupOwner } = await _loadWallets()
  console.log('Loaded deployer wallets')

  const inbox = process.env['INBOX'] as string
  await _registerNetworks(deployerL1.provider, deployerL2.provider, inbox)
  console.log('SDK registration prepared')

  const proxyAdminL1 = await _deployProxyAdmin(deployerL1)
  console.log('L1 ProxyAdmin address: ', proxyAdminL1.address)

  const proxyAdminL2 = await _deployProxyAdmin(deployerL2)
  console.log('L2 ProxyAdmin address: ', proxyAdminL2.address)

  const bridgedUsdc = await _deployBridgedUsdc(deployerL2, proxyAdminL2)
  console.log('Bridged USDC address: ', bridgedUsdc)

  const l1UsdcGateway = await _deployParentChainUsdcGateway(
    deployerL1,
    proxyAdminL1
  )
  console.log('L1 USDC gateway address: ', l1UsdcGateway.address)

  const l2UsdcGateway = await _deployChildChainUsdcGateway(
    deployerL2,
    proxyAdminL2
  )
  console.log('L2 USDC gateway address: ', l2UsdcGateway.address)

  const l1Router = process.env['L1_ROUTER'] as string
  const l2Router = process.env['L2_ROUTER'] as string
  const l1Usdc = process.env['L1_USDC'] as string
  await _initializeGateways(
    l1UsdcGateway,
    l2UsdcGateway,
    l1Router,
    l2Router,
    inbox,
    l1Usdc,
    bridgedUsdc,
    deployerL1,
    deployerL2
  )
  console.log('Usdc gateways initialized')

  await _registerGateway(
    rollupOwner,
    deployerL2.provider!,
    l1Router,
    l1Usdc,
    l1UsdcGateway.address
  )
  console.log('Usdc gateway registered')
}

async function _loadWallets(): Promise<{
  deployerL1: Wallet
  deployerL2: Wallet
  rollupOwner: Wallet
}> {
  const parentRpc = process.env['PARENT_RPC'] as string
  const parentDeployerKey = process.env['PARENT_DEPLOYER_KEY'] as string
  const childRpc = process.env['CHILD_RPC'] as string
  const childDeployerKey = process.env['CHILD_DEPLOYER_KEY'] as string

  const parentProvider = new JsonRpcProvider(parentRpc)
  const deployerL1 = new ethers.Wallet(parentDeployerKey, parentProvider)

  const childProvider = new JsonRpcProvider(childRpc)
  const deployerL2 = new ethers.Wallet(childDeployerKey, childProvider)

  const rollupOwnerKey = process.env['ROLLUP_OWNER_KEY'] as string
  const rollupOwner = new ethers.Wallet(rollupOwnerKey, parentProvider)

  return { deployerL1, deployerL2, rollupOwner }
}

async function _deployProxyAdmin(deployer: Wallet): Promise<ProxyAdmin> {
  const proxyAdminFac = await new ProxyAdmin__factory(deployer).deploy()
  return await proxyAdminFac.deployed()
}

async function _deployBridgedUsdc(
  deployerL2Wallet: Wallet,
  proxyAdminL2: ProxyAdmin
): Promise<string> {
  /// create l2 usdc behind proxy
  const l2UsdcLogic = await _deployUsdcLogic(deployerL2Wallet)
  const l2UsdcProxyAddress = await _deployUsdcProxy(
    deployerL2Wallet,
    l2UsdcLogic.address,
    proxyAdminL2.address
  )

  /// init usdc proxy
  const l2UsdcFiatToken = IFiatToken__factory.connect(
    l2UsdcProxyAddress,
    deployerL2Wallet
  )
  const masterMinterL2 = deployerL2Wallet
  const pauserL2 = deployerL2Wallet
  const blacklisterL2 = deployerL2Wallet
  await (
    await l2UsdcFiatToken.initialize(
      'USDC token',
      'USDC.e',
      'USD',
      6,
      masterMinterL2.address,
      pauserL2.address,
      blacklisterL2.address,
      deployerL2Wallet.address
    )
  ).wait()
  await (await l2UsdcFiatToken.initializeV2('USDC')).wait()
  await (
    await l2UsdcFiatToken.initializeV2_1(ethers.Wallet.createRandom().address)
  ).wait()
  await (await l2UsdcFiatToken.initializeV2_2([], 'USDC.e')).wait()

  /// init usdc logic to dummy values
  const l2UsdcLogicInit = IFiatToken__factory.connect(
    l2UsdcLogic.address,
    deployerL2Wallet
  )
  const DEAD = '0x000000000000000000000000000000000000dead'
  await (
    await l2UsdcLogicInit.initialize('', '', '', 0, DEAD, DEAD, DEAD, DEAD)
  ).wait()
  await (await l2UsdcLogicInit.initializeV2('')).wait()
  await (await l2UsdcLogicInit.initializeV2_1(DEAD)).wait()
  await (await l2UsdcLogicInit.initializeV2_2([], '')).wait()

  const l2Usdc = IERC20__factory.connect(
    l2UsdcFiatToken.address,
    deployerL2Wallet
  )
  return l2Usdc.address
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

async function _deployParentChainUsdcGateway(
  deployerL1: Wallet,
  proxyAdmin: ProxyAdmin
): Promise<L1USDCGateway> {
  const l1USDCCustomGatewayFactory = await new L1USDCGateway__factory(
    deployerL1
  ).deploy()
  const l1USDCCustomGatewayLogic = await l1USDCCustomGatewayFactory.deployed()
  const tupFactory = await new TransparentUpgradeableProxy__factory(
    deployerL1
  ).deploy(l1USDCCustomGatewayLogic.address, proxyAdmin.address, '0x')
  const tup = await tupFactory.deployed()
  return L1USDCGateway__factory.connect(tup.address, deployerL1)
}

async function _deployChildChainUsdcGateway(
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
  l1UsdcGateway: L1USDCGateway,
  l2UsdcGateway: L2USDCGateway,
  l1Router: string,
  l2Router: string,
  inbox: string,
  l1Usdc: string,
  l2Usdc: string,
  deployerL1: Wallet,
  deployerL2: Wallet
) {
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

  ///// init logic
}

/**
 * Set token to gateway mapping in the routers
 */
async function _registerGateway(
  rollupOwner: Wallet,
  childProvider: Provider,
  l1RouterAddress: string,
  l1UsdcAddress: string,
  l1UsdcGatewayAddress: string
) {
  const l1Router = L1GatewayRouter__factory.connect(
    l1RouterAddress,
    rollupOwner
  )

  /// load upgrade executor
  const routerOwnerAddress = await l1Router.owner()
  if (!(await _isUpgradeExecutor(routerOwnerAddress, rollupOwner))) {
    throw new Error('Router owner is expected to be an UpgradeExecutor')
  }
  const upgradeExecutor = UpgradeExecutor__factory.connect(
    routerOwnerAddress,
    rollupOwner
  )

  /// prepare calldata for executor
  const maxGas = BigNumber.from(500000)
  const gasPriceBid = BigNumber.from(200000000)
  let maxSubmissionCost = BigNumber.from(257600000000)
  const registrationCalldata = l1Router.interface.encodeFunctionData(
    'setGateways',
    [
      [l1UsdcAddress],
      [l1UsdcGatewayAddress],
      maxGas,
      gasPriceBid,
      maxSubmissionCost,
    ]
  )

  /// execute the registration
  const gwRegistrationTx = await upgradeExecutor.executeCall(
    l1Router.address,
    registrationCalldata,
    {
      value: maxGas.mul(gasPriceBid).add(maxSubmissionCost),
    }
  )
  await _waitOnL2Msg(gwRegistrationTx, childProvider)
}

/**
 * Check if owner is UpgardeExecutor by polling ADMIN_ROLE() and EXECUTOR_ROLE()
 */
async function _isUpgradeExecutor(
  routerOwnerAddress: string,
  rollupOwner: Wallet
): Promise<boolean> {
  const upgExecutor = UpgradeExecutor__factory.connect(
    routerOwnerAddress,
    rollupOwner
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
 * Check if all required env vars are set
 */
function _checkEnvVars() {
  const requiredEnvVars = [
    'PARENT_RPC',
    'PARENT_DEPLOYER_KEY',
    'CHILD_RPC',
    'CHILD_DEPLOYER_KEY',
    'ROLLUP_OWNER_KEY',
    'ROLLUP',
    'L1_ROUTER',
    'L2_ROUTER',
    'INBOX',
    'L1_USDC',
    'ROLLUP_OWNER_KEY',
    'ROLLUP',
  ]

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`Missing env var ${envVar}`)
    }
  }
}
