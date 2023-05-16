import { Contract, ContractFactory, Signer, constants } from 'ethers'
import {
  BeaconProxyFactory__factory,
  L1OrbitCustomGateway__factory,
  L1OrbitERC20Gateway__factory,
  L1OrbitGatewayRouter__factory,
  L2CustomGateway__factory,
  L2ERC20Gateway__factory,
  L2GatewayRouter__factory,
  ProxyAdmin__factory,
  StandardArbERC20__factory,
  TransparentUpgradeableProxy__factory,
  UpgradeableBeacon__factory,
} from '../../build/types'

async function deployContractBehindProxy<
  T extends ContractFactory,
  U extends Contract
>(
  deployer: Signer,
  logicFactory: new (deployer: Signer) => T,
  proxyAdmin: string,
  contractFactory: (address: string, signer: Signer) => U
): Promise<U> {
  const logicContract = await new logicFactory(deployer).deploy()
  await logicContract.deployed()

  const proxyContract = await new TransparentUpgradeableProxy__factory(
    deployer
  ).deploy(logicContract.address, proxyAdmin, '0x')
  await proxyContract.deployed()

  return contractFactory(proxyContract.address, deployer)
}

export const deployErc20L1 = async (deployer: Signer) => {
  const proxyAdmin = await new ProxyAdmin__factory(deployer).deploy()
  await proxyAdmin.deployed()
  console.log('proxyAdmin', proxyAdmin.address)

  const router = await deployContractBehindProxy(
    deployer,
    L1OrbitGatewayRouter__factory,
    proxyAdmin.address,
    L1OrbitGatewayRouter__factory.connect
  )

  const standardGateway = await deployContractBehindProxy(
    deployer,
    L1OrbitERC20Gateway__factory,
    proxyAdmin.address,
    L1OrbitERC20Gateway__factory.connect
  )

  const customGateway = await deployContractBehindProxy(
    deployer,
    L1OrbitCustomGateway__factory,
    proxyAdmin.address,
    L1OrbitCustomGateway__factory.connect
  )

  return {
    proxyAdmin,
    router,
    standardGateway,
    customGateway,
  }
}

export const deployErc20L2 = async (deployer: Signer) => {
  const proxyAdmin = await new ProxyAdmin__factory(deployer).deploy()
  await proxyAdmin.deployed()

  const router = await deployContractBehindProxy(
    deployer,
    L2GatewayRouter__factory,
    proxyAdmin.address,
    L2GatewayRouter__factory.connect
  )

  const standardGateway = await deployContractBehindProxy(
    deployer,
    L2ERC20Gateway__factory,
    proxyAdmin.address,
    L2ERC20Gateway__factory.connect
  )

  const customGateway = await deployContractBehindProxy(
    deployer,
    L2CustomGateway__factory,
    proxyAdmin.address,
    L2CustomGateway__factory.connect
  )

  const standardArbERC20 = await new StandardArbERC20__factory(
    deployer
  ).deploy()
  await standardArbERC20.deployed()

  const beacon = await new UpgradeableBeacon__factory(deployer).deploy(
    standardArbERC20.address
  )
  await beacon.deployed()

  const beaconProxyFactory = await new BeaconProxyFactory__factory(
    deployer
  ).deploy()
  await beaconProxyFactory.deployed()

  return {
    proxyAdmin,
    router,
    standardGateway,
    customGateway,
    standardArbERC20,
    beacon,
    beaconProxyFactory,
  }
}

export const deployErc20AndInit = async (
  l1Signer: Signer,
  l2Signer: Signer,
  inboxAddress: string
) => {
  console.log('deploying l1')
  const l1 = await deployErc20L1(l1Signer)

  console.log('deploying l2')
  const l2 = await deployErc20L2(l2Signer)

  console.log('initialising L2')
  await l2.router.initialize(l1.router.address, l2.standardGateway.address)
  await (
    await l2.standardGateway.initialize(
      l1.standardGateway.address,
      l2.router.address,
      l2.beaconProxyFactory.address
    )
  ).wait()
  await (
    await l2.customGateway.initialize(
      l1.customGateway.address,
      l2.router.address
    )
  ).wait()

  console.log('initialising L1')
  await (
    await l1.router.initialize(
      await l1Signer.getAddress(),
      l1.standardGateway.address,
      constants.AddressZero,
      l2.router.address,
      inboxAddress
    )
  ).wait()

  await (
    await l1.standardGateway.initialize(
      l2.standardGateway.address,
      l1.router.address,
      inboxAddress,
      await l2.beaconProxyFactory.cloneableProxyHash(),
      l2.beaconProxyFactory.address
    )
  ).wait()
  await (
    await l1.customGateway.initialize(
      l2.customGateway.address,
      l1.router.address,
      inboxAddress,
      await l1Signer.getAddress()
    )
  ).wait()

  return { l1, l2 }
}
