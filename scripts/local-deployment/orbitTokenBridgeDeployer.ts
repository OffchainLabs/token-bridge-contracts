import { Contract, ContractFactory, Signer, constants, ethers } from 'ethers'
import {
  BeaconProxyFactory__factory,
  ERC20__factory,
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
import { setupOrbitTokenBridge, sleep } from './testSetup'
import * as fs from 'fs'

/**
 * Deploy all the L1 and L2 contracts and do the initialization.
 *
 * @param l1Signer
 * @param l2Signer
 * @param inboxAddress
 * @param nativeTokenAddress
 * @returns
 */
export const deployOrbitTokenBridgeAndInit = async (
  l1Signer: Signer,
  l2Signer: Signer,
  inboxAddress: string,
  nativeTokenAddress: string
) => {
  console.log('deploying l1 side')
  const l1 = await deployTokenBridgeL1Side(l1Signer)

  // fund L2 deployer so contracts can be deployed
  await bridgeFundsToL2Deployer(l1Signer, inboxAddress, nativeTokenAddress)

  console.log('deploying l2 side')
  const l2 = await deployTokenBridgeL2Side(l2Signer)

  console.log('initialising L2')
  await l2.router.initialize(l1.router.address, l2.standardGateway.address)
  await l2.beaconProxyFactory.initialize(l2.beacon.address)
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

const deployTokenBridgeL1Side = async (deployer: Signer) => {
  const proxyAdmin = await new ProxyAdmin__factory(deployer).deploy()
  await proxyAdmin.deployed()
  console.log('proxyAdmin', proxyAdmin.address)

  const router = await deployContractBehindProxy(
    deployer,
    L1OrbitGatewayRouter__factory,
    proxyAdmin.address,
    L1OrbitGatewayRouter__factory.connect
  )
  console.log('router', router.address)

  const standardGateway = await deployContractBehindProxy(
    deployer,
    L1OrbitERC20Gateway__factory,
    proxyAdmin.address,
    L1OrbitERC20Gateway__factory.connect
  )
  console.log('standardGateway', standardGateway.address)

  const customGateway = await deployContractBehindProxy(
    deployer,
    L1OrbitCustomGateway__factory,
    proxyAdmin.address,
    L1OrbitCustomGateway__factory.connect
  )
  console.log('customGateway', standardGateway.address)

  return {
    proxyAdmin,
    router,
    standardGateway,
    customGateway,
  }
}

const deployTokenBridgeL2Side = async (deployer: Signer) => {
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

const bridgeFundsToL2Deployer = async (
  l1Signer: Signer,
  inboxAddress: string,
  nativeTokenAddress: string
) => {
  console.log('fund L2 deployer')

  const depositAmount = ethers.utils.parseUnits('1000', 'ether')

  // approve tokens to bridge
  await (
    await ERC20__factory.connect(nativeTokenAddress, l1Signer).approve(
      inboxAddress,
      depositAmount
    )
  ).wait()

  // bridge it
  const orbitInboxAbi = [
    'function depositERC20(uint256) public returns (uint256)',
  ]
  const orbitInbox = new Contract(inboxAddress, orbitInboxAbi, l1Signer)
  await (await orbitInbox.depositERC20(depositAmount)).wait()
  await sleep(30 * 1000)
}

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

  const { l1Network, l2Network } = await setupOrbitTokenBridge(
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
