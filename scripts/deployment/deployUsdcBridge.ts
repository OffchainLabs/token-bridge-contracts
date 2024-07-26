import { BigNumber, ethers, Wallet } from 'ethers'
import {
  IOwnable__factory,
  L1GatewayRouter__factory,
  L1USDCGateway,
  L1USDCGateway__factory,
  L2GatewayRouter__factory,
  L2USDCGateway,
  L2USDCGateway__factory,
  ProxyAdmin__factory,
  TransparentUpgradeableProxy__factory,
  UpgradeExecutor__factory,
} from '../../build/types'
import { JsonRpcProvider } from '@ethersproject/providers'
import dotenv from 'dotenv'
import { L1ToL2MessageGasEstimator } from '@arbitrum/sdk'
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'

dotenv.config()

main().then(() => console.log('Done.'))

async function main() {
  const { deployerL1, deployerL2 } = await _loadWallets()

  /// create L2 USDC from Circle's repo, set the address in .env and load it here
  const l2Usdc = process.env['BRIDGED_USDC_ADDRESS'] as string

  const { l1USDCCustomGateway, l2USDCCustomGateway } = await _deployGateways(
    deployerL1,
    deployerL2
  )

  await _initializeGateways(
    l1USDCCustomGateway,
    l2USDCCustomGateway,
    l2Usdc,
    deployerL1,
    deployerL2
  )
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

async function _deployGateways(
  deployerL1: Wallet,
  deployerL2: Wallet
): Promise<{
  l1USDCCustomGateway: L1USDCGateway
  l2USDCCustomGateway: L2USDCGateway
}> {
  /// create new L1 usdc gateway behind proxy
  const proxyAdminFac = await new ProxyAdmin__factory(deployerL1).deploy()
  const proxyAdmin = await proxyAdminFac.deployed()
  const l1USDCCustomGatewayFactory = await new L1USDCGateway__factory(
    deployerL1
  ).deploy()
  const l1USDCCustomGatewayLogic = await l1USDCCustomGatewayFactory.deployed()
  const tupFactory = await new TransparentUpgradeableProxy__factory(
    deployerL1
  ).deploy(l1USDCCustomGatewayLogic.address, proxyAdmin.address, '0x')
  const tup = await tupFactory.deployed()
  const l1USDCCustomGateway = L1USDCGateway__factory.connect(
    tup.address,
    deployerL1
  )
  console.log('L1 ProxyAdmin address: ', proxyAdmin.address)
  console.log('L1USDCGateway address: ', l1USDCCustomGateway.address)

  /// create new L2 usdc gateway behind proxy
  const proxyAdminL2Fac = await new ProxyAdmin__factory(deployerL2).deploy()
  const proxyAdminL2 = await proxyAdminL2Fac.deployed()
  const l2USDCCustomGatewayFactory = await new L2USDCGateway__factory(
    deployerL2
  ).deploy()
  const l2USDCCustomGatewayLogic = await l2USDCCustomGatewayFactory.deployed()
  const tupL2Factory = await new TransparentUpgradeableProxy__factory(
    deployerL2
  ).deploy(l2USDCCustomGatewayLogic.address, proxyAdminL2.address, '0x')
  const tupL2 = await tupL2Factory.deployed()
  const l2USDCCustomGateway = L2USDCGateway__factory.connect(
    tupL2.address,
    deployerL2
  )
  console.log('L2 ProxyAdmin address: ', proxyAdminL2.address)
  console.log('L2USDCGateway address: ', l2USDCCustomGateway.address)

  return { l1USDCCustomGateway, l2USDCCustomGateway }
}

async function _initializeGateways(
  l1USDCCustomGateway: L1USDCGateway,
  l2USDCCustomGateway: L2USDCGateway,
  l2Usdc: string,
  deployerL1: Wallet,
  deployerL2: Wallet
) {
  /// initialize L1 gateway
  const _l2CounterPart = l2USDCCustomGateway.address
  const _l1Router = '0xcE18836b233C83325Cc8848CA4487e94C6288264'
  const _inbox = '0xaAe29B0366299461418F5324a79Afc425BE5ae21'
  const _l1USDC = '0xf4FEa76b87D9bCedE79EB29bBD5EDAefcA0E7dcA'
  const _l2USDC = l2Usdc
  const _owner = deployerL1.address
  await (
    await l1USDCCustomGateway.initialize(
      _l2CounterPart,
      _l1Router,
      _inbox,
      _l1USDC,
      _l2USDC,
      _owner
    )
  ).wait()
  console.log('L1 USDC custom gateway initialized')

  /// initialize L2 gateway
  const _l1Counterpart = l1USDCCustomGateway.address
  const _l2Router = '0x9fDD1C4E4AA24EEc1d913FABea925594a20d43C7'
  const _ownerL2 = deployerL2.address
  await (
    await l2USDCCustomGateway.initialize(
      _l1Counterpart,
      _l2Router,
      _l1USDC,
      _l2USDC,
      _ownerL2
    )
  ).wait()
  console.log('L2 USDC custom gateway initialized')
}

async function _print(deployerL1Wallet: Wallet, deployerL2Wallet: Wallet) {
  /// register USDC custom gateway
  const router = L1GatewayRouter__factory.connect(
    '0xcE18836b233C83325Cc8848CA4487e94C6288264',
    deployerL1Wallet
  )
  const l2Router = L2GatewayRouter__factory.connect(
    '0x9fDD1C4E4AA24EEc1d913FABea925594a20d43C7',
    deployerL2Wallet
  )

  const l1Usdc = '0xf4FEa76b87D9bCedE79EB29bBD5EDAefcA0E7dcA'
  const l1USDCCustomGateway = '0xE6C04c453BE367AAEF8E8bab26E5Ce6366Be3Fe6'
  const l2USDCCustomGateway = '0xCC083dDee542023FC7CE8Cf52C8666519B981ec2'

  const l1ToL2MsgGasEstimate = new L1ToL2MessageGasEstimator(
    deployerL2Wallet.provider
  )

  //   const payload = abi.encodeWithSelector(
  //     L2GatewayRouter.setGateway.selector,
  //     _token,
  //     _gateway
  // );
  const iface = new ethers.utils.Interface([
    'function setGateway(address _token, address _gateway)',
  ])
  const payload = iface.encodeFunctionData('setGateway', [
    l1Usdc,
    l1USDCCustomGateway,
  ])

  const gasParams = await l1ToL2MsgGasEstimate.estimateAll(
    {
      from: l1USDCCustomGateway,
      to: l2USDCCustomGateway,
      l2CallValue: BigNumber.from(0),
      excessFeeRefundAddress: deployerL1Wallet.address,
      callValueRefundAddress: deployerL1Wallet.address,
      data: payload,
    },
    await getBaseFee(deployerL1Wallet.provider!),
    deployerL1Wallet.provider!
  )
  console.log('Gas params: ', gasParams)

  // const maxGas = BigNumber.from(1)
  // const gasPriceBid = BigNumber.from(1)
  // let maxSubmissionCost = BigNumber.from(257600000000)
  // const registrationCalldata = router.interface.encodeFunctionData(
  //   'setGateways',
  //   [[l1Usdc], [l1USDCCustomGateway], maxGas, gasPriceBid, maxSubmissionCost]
  // )

  // const upExec = UpgradeExecutor__factory.connect(
  //   '0x5FEe78FE9AD96c1d8557C6D6BB22Eb5A61eeD315',
  //   deployerL1Wallet
  // )
  // const gwRegistrationTx = await upExec.executeCall(
  //   router.address,
  //   registrationCalldata,
  //   {
  //     value: maxGas.mul(gasPriceBid).add(maxSubmissionCost),
  //   }
  // )
  // await waitOnL2Msg(gwRegistrationTx)
  // console.log('USDC custom gateway registered')
}
