import {
  Contract,
  ContractFactory,
  Signer,
  Wallet,
  constants,
  ethers,
} from 'ethers'
import {
  BeaconProxyFactory__factory,
  L1CustomGateway__factory,
  L1ERC20Gateway__factory,
  L1GatewayRouter__factory,
  L2CustomGateway__factory,
  L2ERC20Gateway__factory,
  L2GatewayRouter__factory,
  ProxyAdmin__factory,
  StandardArbERC20__factory,
  TransparentUpgradeableProxy__factory,
  UpgradeableBeacon__factory,
} from '../../build/types'
import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network, addCustomNetwork } from '@arbitrum/sdk'
import { execSync } from 'child_process'
import { Bridge__factory } from '@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import * as fs from 'fs'

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

  const { l1: l1Contracts, l2: l2Contracts } = await deployTokenBridgeAndInit(
    l1Deployer,
    l2Deployer,
    coreL2Network.ethBridge.inbox
  )
  const l2Network: L2Network = {
    ...coreL2Network,
    tokenBridge: {
      l1CustomGateway: l1Contracts.customGateway.address,
      l1ERC20Gateway: l1Contracts.standardGateway.address,
      l1GatewayRouter: l1Contracts.router.address,
      l1MultiCall: '',
      l1ProxyAdmin: l1Contracts.proxyAdmin.address,
      l1Weth: '',
      l1WethGateway: '',

      l2CustomGateway: l2Contracts.customGateway.address,
      l2ERC20Gateway: l2Contracts.standardGateway.address,
      l2GatewayRouter: l2Contracts.router.address,
      l2Multicall: '',
      l2ProxyAdmin: l2Contracts.proxyAdmin.address,
      l2Weth: '',
      l2WethGateway: '',
    },
  }

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
  console.log('deploying l1 side')
  const l1 = await deployTokenBridgeL1Side(l1Signer)

  // fund L2 deployer so contracts can be deployed
  await bridgeFundsToL2Deployer(l1Signer, inboxAddress)

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
    L1GatewayRouter__factory,
    proxyAdmin.address,
    L1GatewayRouter__factory.connect
  )
  console.log('router', router.address)

  const standardGateway = await deployContractBehindProxy(
    deployer,
    L1ERC20Gateway__factory,
    proxyAdmin.address,
    L1ERC20Gateway__factory.connect
  )
  console.log('standardGateway', standardGateway.address)

  const customGateway = await deployContractBehindProxy(
    deployer,
    L1CustomGateway__factory,
    proxyAdmin.address,
    L1CustomGateway__factory.connect
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
