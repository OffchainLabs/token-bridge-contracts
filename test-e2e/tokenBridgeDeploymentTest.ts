import { JsonRpcProvider, Provider, Filter } from '@ethersproject/providers'
import {
  AeWETH__factory,
  ArbMulticall2,
  ArbMulticall2__factory,
  BeaconProxyFactory__factory,
  IERC20Bridge__factory,
  IInboxProxyAdmin__factory,
  IInbox__factory,
  IOwnable__factory,
  L1AtomicTokenBridgeCreator,
  L1AtomicTokenBridgeCreator__factory,
  L1CustomGateway,
  L1CustomGateway__factory,
  L1ERC20Gateway,
  L1ERC20Gateway__factory,
  L1GatewayRouter,
  L1GatewayRouter__factory,
  L1WethGateway,
  L1WethGateway__factory,
  L2CustomGateway,
  L2CustomGateway__factory,
  L2ERC20Gateway,
  L2ERC20Gateway__factory,
  L2GatewayRouter,
  L2GatewayRouter__factory,
  L2WethGateway,
  L2WethGateway__factory,
} from '../build/types'
import { abi as UpgradeExecutorABI } from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'
import { RollupCore__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupCore__factory'
import { applyAlias } from '../test/testhelper'
import path from 'path'
import fs from 'fs'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import { Contract } from 'ethers'

const config = {
  l1Url: process.env.BASECHAIN_RPC || 'http://localhost:8547',
  l2Url: process.env.ORBIT_RPC || 'http://localhost:3347',
}

let l1Provider: JsonRpcProvider
let l2Provider: JsonRpcProvider

describe('tokenBridge', () => {
  it('should have deployed and initialized token bridge contracts', async function () {
    l1Provider = new JsonRpcProvider(config.l1Url)
    l2Provider = new JsonRpcProvider(config.l2Url)

    /// get rollup, L1 creator and retryable sender as entrypoint, either from env vars or from network.json
    let rollupAddress: string
    let l1TokenBridgeCreator: string
    let l1RetryableSender: string
    if (process.env.ROLLUP_ADDRESS && process.env.L1_TOKEN_BRIDGE_CREATOR) {
      rollupAddress = process.env.ROLLUP_ADDRESS as string
      l1TokenBridgeCreator = process.env.L1_TOKEN_BRIDGE_CREATOR as string
      l1RetryableSender = process.env.L1_RETRYABLE_SENDER as string
    } else {
      const localNetworkFile = path.join(__dirname, '..', 'network.json')
      if (fs.existsSync(localNetworkFile)) {
        const data = JSON.parse(fs.readFileSync(localNetworkFile).toString())
        rollupAddress = data['l2Network']['ethBridge']['rollup']
        l1TokenBridgeCreator = data['l1TokenBridgeCreator']
        l1RetryableSender = data['retryableSender']
      } else {
        throw new Error(
          "Can't find rollup address info. Either set ROLLUP_ADDRESS, L1_TOKEN_BRIDGE_CREATOR AND L1_RETRYABLE_SENDER env varS or provide network.json file"
        )
      }
    }

    console.log(
      `Testing token bridge deployment for rollup ${rollupAddress} deployed by creator ${l1TokenBridgeCreator}`
    )

    /// get core contract and token bridge addresses
    const { rollupAddresses, deploymentAddresses } = await _getAddresses(
      rollupAddress,
      l1TokenBridgeCreator
    )

    //// L1 checks

    // check that setting of retryable sender was not frontrun
    const actualRetryableSender =
      await L1AtomicTokenBridgeCreator__factory.connect(
        l1TokenBridgeCreator,
        l1Provider
      ).retryableSender()
    expect(actualRetryableSender.toLowerCase()).to.be.eq(
      l1RetryableSender.toLowerCase()
    )

    await checkL1RouterInitialization(
      L1GatewayRouter__factory.connect(
        deploymentAddresses.l1.router,
        l1Provider
      ),
      deploymentAddresses,
      rollupAddresses
    )

    await checkL1StandardGatewayInitialization(
      L1ERC20Gateway__factory.connect(
        deploymentAddresses.l1.standardGateway,
        l1Provider
      ),
      deploymentAddresses,
      rollupAddresses
    )

    await checkL1CustomGatewayInitialization(
      L1CustomGateway__factory.connect(
        deploymentAddresses.l1.customGateway,
        l1Provider
      ),
      deploymentAddresses,
      rollupAddresses
    )

    const usingFeeToken = await _isUsingFeeToken(
      rollupAddresses.inbox,
      l1Provider
    )
    if (!usingFeeToken)
      await checkL1WethGatewayInitialization(
        L1WethGateway__factory.connect(
          deploymentAddresses.l1.wethGateway,
          l1Provider
        ),
        deploymentAddresses,
        rollupAddresses
      )

    //// L2 checks

    await checkL2RouterInitialization(
      L2GatewayRouter__factory.connect(
        deploymentAddresses.l2Router,
        l2Provider
      ),
      deploymentAddresses
    )

    await checkL2StandardGatewayInitialization(
      L2ERC20Gateway__factory.connect(
        deploymentAddresses.l2StandardGateway,
        l2Provider
      ),
      deploymentAddresses
    )

    await checkL2CustomGatewayInitialization(
      L2CustomGateway__factory.connect(
        deploymentAddresses.l2CustomGateway,
        l2Provider
      ),
      deploymentAddresses
    )

    await checkL2MulticallInitialization(
      ArbMulticall2__factory.connect(
        deploymentAddresses.l2Multicall,
        l2Provider
      )
    )

    if (!usingFeeToken) {
      await checkL2WethGatewayInitialization(
        L2WethGateway__factory.connect(
          deploymentAddresses.l2WethGateway,
          l2Provider
        ),
        deploymentAddresses
      )
    }

    const upgExecutor = new ethers.Contract(
      deploymentAddresses.l2UpgradeExecutor,
      UpgradeExecutorABI,
      l2Provider
    )
    await checkL2UpgradeExecutorInitialization(upgExecutor, rollupAddresses)

    await checkL1Ownership(deploymentAddresses, rollupAddresses)
    await checkL2Ownership(deploymentAddresses)
    await checkLogicContracts(usingFeeToken, deploymentAddresses)
  })
})

//// L1 contracts

async function checkL1RouterInitialization(
  l1Router: L1GatewayRouter,
  deploymentAddresses: DeploymentAddresses,
  rollupAddresses: RollupAddresses
) {
  console.log('checkL1RouterInitialization')

  expect((await l1Router.defaultGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.standardGateway.toLowerCase()
  )
  expect((await l1Router.inbox()).toLowerCase()).to.be.eq(
    rollupAddresses.inbox.toLowerCase()
  )
  expect((await l1Router.router()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )
  expect((await l1Router.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2Router.toLowerCase()
  )
}

async function checkL1StandardGatewayInitialization(
  l1ERC20Gateway: L1ERC20Gateway,
  deploymentAddresses: DeploymentAddresses,
  rollupAddresses: RollupAddresses
) {
  console.log('checkL1StandardGatewayInitialization')

  expect((await l1ERC20Gateway.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2StandardGateway.toLowerCase()
  )
  expect((await l1ERC20Gateway.router()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.router.toLowerCase()
  )
  expect((await l1ERC20Gateway.inbox()).toLowerCase()).to.be.eq(
    rollupAddresses.inbox.toLowerCase()
  )
  expect((await l1ERC20Gateway.l2BeaconProxyFactory()).toLowerCase()).to.be.eq(
    (
      await L2ERC20Gateway__factory.connect(
        await l1ERC20Gateway.counterpartGateway(),
        l2Provider
      ).beaconProxyFactory()
    ).toLowerCase()
  )
  expect((await l1ERC20Gateway.cloneableProxyHash()).toLowerCase()).to.be.eq(
    (
      await BeaconProxyFactory__factory.connect(
        await l1ERC20Gateway.l2BeaconProxyFactory(),
        l2Provider
      ).cloneableProxyHash()
    ).toLowerCase()
  )
  expect((await l1ERC20Gateway.whitelist()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL1CustomGatewayInitialization(
  l1CustomGateway: L1CustomGateway,
  deploymentAddresses: DeploymentAddresses,
  rollupAddresses: RollupAddresses
) {
  console.log('checkL1CustomGatewayInitialization')

  expect((await l1CustomGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2CustomGateway.toLowerCase()
  )

  expect((await l1CustomGateway.router()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.router.toLowerCase()
  )

  expect((await l1CustomGateway.inbox()).toLowerCase()).to.be.eq(
    rollupAddresses.inbox.toLowerCase()
  )

  expect((await l1CustomGateway.whitelist()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL1WethGatewayInitialization(
  l1WethGateway: L1WethGateway,
  deploymentAddresses: DeploymentAddresses,
  rollupAddresses: RollupAddresses
) {
  console.log('checkL1WethGatewayInitialization')

  expect((await l1WethGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2WethGateway.toLowerCase()
  )

  expect((await l1WethGateway.router()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.router.toLowerCase()
  )

  expect((await l1WethGateway.inbox()).toLowerCase()).to.be.eq(
    rollupAddresses.inbox.toLowerCase()
  )

  expect((await l1WethGateway.l1Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l1WethGateway.l2Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL2UpgradeExecutorInitialization(
  l2Executor: Contract,
  rollupAddresses: RollupAddresses
) {
  console.log('checkL2UpgradeExecutorInitialization')

  //// check assigned/revoked roles are correctly set
  const adminRole = await l2Executor.ADMIN_ROLE()
  const executorRole = await l2Executor.EXECUTOR_ROLE()

  expect(await l2Executor.hasRole(adminRole, l2Executor.address)).to.be.true
  expect(await l2Executor.hasRole(executorRole, rollupAddresses.rollupOwner)).to
    .be.true
  const aliasedL1Executor = applyAlias(rollupAddresses.upgradeExecutor)
  expect(await l2Executor.hasRole(executorRole, aliasedL1Executor)).to.be.true
}

//// L2 contracts

async function checkL2RouterInitialization(
  l2Router: L2GatewayRouter,
  deploymentAddresses: DeploymentAddresses
) {
  console.log('checkL2RouterInitialization')

  expect((await l2Router.defaultGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2StandardGateway.toLowerCase()
  )

  expect((await l2Router.router()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l2Router.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.router.toLowerCase()
  )
}

async function checkL2StandardGatewayInitialization(
  l2ERC20Gateway: L2ERC20Gateway,
  deploymentAddresses: DeploymentAddresses
) {
  console.log('checkL2StandardGatewayInitialization')

  expect((await l2ERC20Gateway.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.standardGateway.toLowerCase()
  )

  expect((await l2ERC20Gateway.router()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2Router.toLowerCase()
  )

  expect((await l2ERC20Gateway.beaconProxyFactory()).toLowerCase()).to.be.eq(
    (
      await L1ERC20Gateway__factory.connect(
        await l2ERC20Gateway.counterpartGateway(),
        l1Provider
      ).l2BeaconProxyFactory()
    ).toLowerCase()
  )

  expect((await l2ERC20Gateway.cloneableProxyHash()).toLowerCase()).to.be.eq(
    (
      await L1ERC20Gateway__factory.connect(
        await l2ERC20Gateway.counterpartGateway(),
        l1Provider
      ).cloneableProxyHash()
    ).toLowerCase()
  )
}

async function checkL2CustomGatewayInitialization(
  l2CustomGateway: L2CustomGateway,
  deploymentAddresses: DeploymentAddresses
) {
  console.log('checkL2CustomGatewayInitialization')

  expect((await l2CustomGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.customGateway.toLowerCase()
  )

  expect((await l2CustomGateway.router()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2Router.toLowerCase()
  )
}

async function checkL2WethGatewayInitialization(
  l2WethGateway: L2WethGateway,
  deploymentAddresses: DeploymentAddresses
) {
  console.log('checkL2WethGatewayInitialization')

  expect((await l2WethGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    deploymentAddresses.l1.wethGateway.toLowerCase()
  )

  expect((await l2WethGateway.router()).toLowerCase()).to.be.eq(
    deploymentAddresses.l2Router.toLowerCase()
  )

  expect((await l2WethGateway.l1Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l2WethGateway.l2Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL2MulticallInitialization(l2Multicall: ArbMulticall2) {
  // check l2Multicall is deployed
  const l2MulticallCode = await l2Provider.getCode(l2Multicall.address)
  expect(l2MulticallCode.length).to.be.gt(0)
}

async function checkL1Ownership(
  deploymentAddresses: DeploymentAddresses,
  rollupAddresses: RollupAddresses
) {
  console.log('checkL1Ownership')

  // check proxyAdmins

  expect(
    await _getProxyAdmin(deploymentAddresses.l1.router, l1Provider)
  ).to.be.eq(rollupAddresses.proxyAdmin)
  expect(
    await _getProxyAdmin(deploymentAddresses.l1.standardGateway, l1Provider)
  ).to.be.eq(rollupAddresses.proxyAdmin)
  expect(
    await _getProxyAdmin(deploymentAddresses.l1.customGateway, l1Provider)
  ).to.be.eq(rollupAddresses.proxyAdmin)
  if (deploymentAddresses.l1.wethGateway !== ethers.constants.AddressZero) {
    expect(
      await _getProxyAdmin(deploymentAddresses.l1.wethGateway, l1Provider)
    ).to.be.eq(rollupAddresses.proxyAdmin)
  }
  expect(
    await _getProxyAdmin(rollupAddresses.upgradeExecutor, l1Provider)
  ).to.be.eq(rollupAddresses.proxyAdmin)

  // check ownables
  expect(await _getOwner(rollupAddresses.proxyAdmin, l1Provider)).to.be.eq(
    rollupAddresses.upgradeExecutor
  )
  expect(await _getOwner(deploymentAddresses.l1.router, l1Provider)).to.be.eq(
    rollupAddresses.upgradeExecutor
  )
  expect(
    await _getOwner(deploymentAddresses.l1.customGateway, l1Provider)
  ).to.be.eq(rollupAddresses.upgradeExecutor)
}

async function checkL2Ownership(deploymentAddresses: DeploymentAddresses) {
  console.log('checkL2Ownership')

  const l2ProxyAdmin = await _getProxyAdmin(
    deploymentAddresses.l2Router,
    l2Provider
  )

  // check proxyAdmins
  expect(
    await _getProxyAdmin(deploymentAddresses.l2Router, l2Provider)
  ).to.be.eq(l2ProxyAdmin)
  expect(
    await _getProxyAdmin(deploymentAddresses.l2StandardGateway, l2Provider)
  ).to.be.eq(l2ProxyAdmin)
  expect(
    await _getProxyAdmin(deploymentAddresses.l2CustomGateway, l2Provider)
  ).to.be.eq(l2ProxyAdmin)

  if (deploymentAddresses.l2WethGateway != ethers.constants.AddressZero) {
    expect(
      await _getProxyAdmin(deploymentAddresses.l2WethGateway, l2Provider)
    ).to.be.eq(l2ProxyAdmin)
  }
  expect(
    await _getProxyAdmin(deploymentAddresses.l2UpgradeExecutor, l2Provider)
  ).to.be.eq(l2ProxyAdmin)

  // check ownables
  expect(await _getOwner(l2ProxyAdmin, l2Provider)).to.be.eq(
    deploymentAddresses.l2UpgradeExecutor.toLowerCase()
  )
}

async function checkLogicContracts(
  usingFeeToken: boolean,
  deploymentAddresses: DeploymentAddresses
) {
  console.log('checkLogicContracts')

  const upgExecutorLogic = await _getLogicAddress(
    deploymentAddresses.l2UpgradeExecutor,
    l2Provider
  )
  expect(await _isInitialized(upgExecutorLogic, l2Provider)).to.be.true

  const routerLogic = await _getLogicAddress(
    deploymentAddresses.l2Router,
    l2Provider
  )
  expect(
    await L2GatewayRouter__factory.connect(
      routerLogic,
      l2Provider
    ).counterpartGateway()
  ).to.be.not.eq(ethers.constants.AddressZero)

  const standardGatewayLogic = await _getLogicAddress(
    deploymentAddresses.l2StandardGateway,
    l2Provider
  )
  expect(
    await L2ERC20Gateway__factory.connect(
      standardGatewayLogic,
      l2Provider
    ).counterpartGateway()
  ).to.be.not.eq(ethers.constants.AddressZero)

  const customGatewayLogic = await _getLogicAddress(
    deploymentAddresses.l2CustomGateway,
    l2Provider
  )
  expect(
    await L2CustomGateway__factory.connect(
      customGatewayLogic,
      l2Provider
    ).counterpartGateway()
  ).to.be.not.eq(ethers.constants.AddressZero)

  if (!usingFeeToken) {
    const wethGatewayLogic = await _getLogicAddress(
      deploymentAddresses.l2WethGateway,
      l2Provider
    )
    expect(
      await L2WethGateway__factory.connect(
        wethGatewayLogic,
        l2Provider
      ).counterpartGateway()
    ).to.be.not.eq(ethers.constants.AddressZero)

    const wethLogic = await _getLogicAddress(
      deploymentAddresses.l2Weth,
      l2Provider
    )
    expect(
      await AeWETH__factory.connect(wethLogic, l2Provider).l2Gateway()
    ).to.be.not.eq(ethers.constants.AddressZero)
  }
}

//// utils
async function _isUsingFeeToken(inbox: string, l1Provider: JsonRpcProvider) {
  const bridge = await IInbox__factory.connect(inbox, l1Provider).bridge()

  try {
    await IERC20Bridge__factory.connect(bridge, l1Provider).nativeToken()
  } catch {
    return false
  }

  return true
}

async function _getAddresses(
  rollupAddress: string,
  l1TokenBridgeCreatorAddress: string
) {
  const l1TokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    l1TokenBridgeCreatorAddress,
    l1Provider
  )

  /// get core contracts addresses
  const inbox = await RollupCore__factory.connect(
    rollupAddress,
    l1Provider
  ).inbox()

  const multicall = await l1TokenBridgeCreator.l1Multicall()
  const proxyAdmin = await IInboxProxyAdmin__factory.connect(
    inbox,
    l1Provider
  ).getProxyAdmin()

  const upgradeExecutor = await IOwnable__factory.connect(
    rollupAddress,
    l1Provider
  ).owner()

  const rollupAddresses = {
    rollup: rollupAddress.toLowerCase(),
    inbox: inbox.toLowerCase(),
    rollupOwner: await _getRollupOwnerFromLogs(
      l1Provider,
      l1TokenBridgeCreator,
      inbox
    ),
    proxyAdmin: proxyAdmin.toLowerCase(),
    upgradeExecutor: upgradeExecutor.toLowerCase(),
    multicall: multicall.toLowerCase(),
  }

  /// fetch deployment addresses from registry
  const deploymentAddresses =
    await l1TokenBridgeCreator.getTokenBridgeDeployment(inbox)

  return { rollupAddresses, deploymentAddresses }
}

async function _getProxyAdmin(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  return (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
    )
  ).toLowerCase()
}

async function _getLogicAddress(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  return (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
    )
  ).toLowerCase()
}

async function _getOwner(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  return (
    await IOwnable__factory.connect(contractAddress, provider).owner()
  ).toLowerCase()
}

async function _getAddressAtStorageSlot(
  contractAddress: string,
  provider: Provider,
  storageSlotBytes: string
): Promise<string> {
  const storageValue = await provider.getStorageAt(
    contractAddress,
    storageSlotBytes
  )

  if (!storageValue) {
    return ''
  }

  // remove excess bytes
  const formatAddress =
    storageValue.substring(0, 2) + storageValue.substring(26)

  // return address as checksum address
  return ethers.utils.getAddress(formatAddress)
}

async function _getRollupOwnerFromLogs(
  provider: JsonRpcProvider,
  l1TokenBridgeCreator: L1AtomicTokenBridgeCreator,
  inboxAddress: string
): Promise<string> {
  const filter: Filter = {
    address: l1TokenBridgeCreator.address,
    topics: [
      ethers.utils.id(
        'OrbitTokenBridgeCreated(address,address,address,address,address,address,address,address)'
      ),
      ethers.utils.hexZeroPad(inboxAddress, 32),
    ],
  }

  // Fetch the logs
  const logs = await provider.getLogs({
    ...filter,
    fromBlock: '0x1',
    toBlock: 'latest',
  })
  if (logs.length === 0) {
    throw new Error(
      `Couldn't find any OrbitTokenBridgeCreated events for inbox ${inboxAddress}`
    )
  }

  const logData = l1TokenBridgeCreator.interface.parseLog(logs[logs.length - 1])
  return logData.args.owner
}

/**
 * Return if contracts is initialized or not. Applicable for contracts which use OpenZeppelin Initializable pattern,
 * so state of initialization is stored as uint8 in storage slot 0, offset 0.
 */
async function _isInitialized(
  contractAddress: string,
  provider: Provider
): Promise<boolean> {
  const storageSlot = 0
  const storageValue = await provider.getStorageAt(contractAddress, storageSlot)
  const bigNumberValue = ethers.BigNumber.from(storageValue)

  // Ethereum storage slots are 32 bytes and a uint8 is 1 byte, we mask the lower 8 bits to convert it to uint8.
  const maskedValue = bigNumberValue.and(255)
  return maskedValue.toNumber() == 1
}

interface L1 {
  inbox: string
  rollupOwner: string
  router: string
  standardGateway: string
  customGateway: string
  wethGateway: string
  proxyAdmin: string
  upgradeExecutor: string
}

interface L2 {
  router: string
  standardGateway: string
  customGateway: string
  wethGateway: string
  weth: string
  upgradeExecutor: string
  multicall: string
  proxyAdmin: string
  beaconProxyFactory: string
}

interface RollupAddresses {
  rollup: string
  inbox: string
  rollupOwner: string
  proxyAdmin: string
  upgradeExecutor: string
  multicall: string
}

interface DeploymentAddresses {
  l1: {
    router: string
    standardGateway: string
    customGateway: string
    wethGateway: string
    weth: string
  }
  l2Router: string
  l2StandardGateway: string
  l2CustomGateway: string
  l2WethGateway: string
  l2Weth: string
  l2ProxyAdmin: string
  l2BeaconProxyFactory: string
  l2UpgradeExecutor: string
  l2Multicall: string
}

interface RollupAddresses {
  rollup: string
  inbox: string
  rollupOwner: string
  proxyAdmin: string
  upgradeExecutor: string
  multicall: string
}

interface DeploymentAddresses {
  l1: {
    router: string
    standardGateway: string
    customGateway: string
    wethGateway: string
    weth: string
  }
  l2Router: string
  l2StandardGateway: string
  l2CustomGateway: string
  l2WethGateway: string
  l2Weth: string
  l2ProxyAdmin: string
  l2BeaconProxyFactory: string
  l2UpgradeExecutor: string
  l2Multicall: string
}
