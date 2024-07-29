import { Wallet } from 'ethers'
import { ethers } from 'hardhat'
import {
  IERC20__factory,
  IFiatToken__factory,
  IFiatTokenProxy__factory,
  L1USDCGateway,
  L1USDCGateway__factory,
  L2USDCGateway,
  L2USDCGateway__factory,
  ProxyAdmin,
  ProxyAdmin__factory,
  TransparentUpgradeableProxy__factory,
} from '../../build/types'
import { JsonRpcProvider } from '@ethersproject/providers'
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

dotenv.config()

main().then(() => console.log('Done.'))

async function main() {
  const { deployerL1, deployerL2 } = await _loadWallets()

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
  const inbox = process.env['INBOX'] as string
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
}

async function _loadWallets(): Promise<{
  deployerL1: Wallet
  deployerL2: Wallet
}> {
  const parentRpc = process.env['PARENT_RPC'] as string
  const parentDeployerKey = process.env['PARENT_DEPLOYER_KEY'] as string
  const childRpc = process.env['CHILD_RPC'] as string
  const childDeployerKey = process.env['CHILD_DEPLOYER_KEY'] as string

  if (!parentRpc || !parentDeployerKey || !childRpc || !childDeployerKey) {
    throw new Error('Missing env vars')
  }

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
): Promise<string> {
  /// create l2 usdc behind proxy
  const l2UsdcLogic = await _deployUsdcLogic(deployerL2Wallet)
  const l2UsdcProxyAddress = await _deployUsdcProxy(
    deployerL2Wallet,
    l2UsdcLogic.address,
    proxyAdminL2.address
  )

  const l2UsdcFiatToken = IFiatToken__factory.connect(
    l2UsdcProxyAddress,
    deployerL2Wallet
  )
  const masterMinterL2 = deployerL2Wallet
  await (
    await l2UsdcFiatToken.initialize(
      'USDC token',
      'USDC.e',
      'USD',
      6,
      masterMinterL2.address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      deployerL2Wallet.address
    )
  ).wait()
  await (await l2UsdcFiatToken.initializeV2('USDC')).wait()
  await (
    await l2UsdcFiatToken.initializeV2_1(ethers.Wallet.createRandom().address)
  ).wait()
  await (await l2UsdcFiatToken.initializeV2_2([], 'USDC.e')).wait()
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
