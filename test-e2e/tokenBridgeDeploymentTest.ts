import { JsonRpcProvider, Provider } from '@ethersproject/providers'
import {
  BeaconProxyFactory__factory,
  IERC20Bridge__factory,
  IInbox__factory,
  IOwnable__factory,
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
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from '../build/types'
import { RollupCore__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupCore__factory'
import { applyAlias } from '../test/testhelper'
import path from 'path'
import fs from 'fs'
import { expect } from 'chai'
import { ethers } from 'hardhat'

const config = {
  l1Url: process.env.BASECHAIN_RPC || 'http://localhost:8545',
  l2Url: process.env.ORBIT_RPC || 'http://localhost:8547',
}

let l1Provider: JsonRpcProvider
let l2Provider: JsonRpcProvider

describe('tokenBridge', () => {
  it('should have deployed and initialized token bridge contracts', async function () {
    l1Provider = new JsonRpcProvider(config.l1Url)
    l2Provider = new JsonRpcProvider(config.l2Url)

    /// get rollup and L1 creator addresses as entrypoint, either from env vars or from network.json
    let rollupAddress: string
    let l1TokenBridgeCreator: string
    if (process.env.ROLLUP_ADDRESS && process.env.L1_TOKEN_BRIDGE_CREATOR) {
      rollupAddress = process.env.ROLLUP_ADDRESS as string
      l1TokenBridgeCreator = process.env.L1_TOKEN_BRIDGE_CREATOR as string
    } else {
      const localNetworkFile = path.join(__dirname, '..', 'network.json')
      if (fs.existsSync(localNetworkFile)) {
        const data = JSON.parse(fs.readFileSync(localNetworkFile).toString())
        rollupAddress = data['l2Network']['ethBridge']['rollup']
        l1TokenBridgeCreator = data['l1TokenBridgeCreator']
      } else {
        throw new Error(
          "Can't find rollup address info. Either set ROLLUP_ADDRESS env var or provide network.json file"
        )
      }
    }

    /// get addresses
    const { l1, l2 } = await _getTokenBridgeAddresses(
      rollupAddress,
      l1TokenBridgeCreator
    )

    // console.log(l1)
    // console.log('############')
    // console.log(l2)
    // exit()

    //// L1 checks

    await checkL1RouterInitialization(
      L1GatewayRouter__factory.connect(l1.router, l1Provider),
      l1.inbox,
      l2
    )

    await checkL1StandardGatewayInitialization(
      L1ERC20Gateway__factory.connect(l1.standardGateway, l1Provider),
      l1,
      l2
    )

    await checkL1CustomGatewayInitialization(
      L1CustomGateway__factory.connect(l1.customGateway, l1Provider),
      l1,
      l2
    )

    const usingFeeToken = await isUsingFeeToken(l1.inbox, l1Provider)
    if (!usingFeeToken)
      await checkL1WethGatewayInitialization(
        L1WethGateway__factory.connect(l1.wethGateway, l1Provider),
        l1,
        l2
      )

    //// L2 checks

    await checkL2RouterInitialization(
      L2GatewayRouter__factory.connect(l2.router, l2Provider)
    )

    await checkL2StandardGatewayInitialization(
      L2ERC20Gateway__factory.connect(l2.standardGateway, l2Provider)
    )

    await checkL2CustomGatewayInitialization(
      L2CustomGateway__factory.connect(l2.customGateway, l2Provider)
    )

    if (!usingFeeToken) {
      await checkL2WethGatewayInitialization(
        L2WethGateway__factory.connect(l2.wethGateway, l2Provider)
      )
    }

    await checkL2UpgadeExecutorInitialization(
      UpgradeExecutor__factory.connect(l1.upgradeExecutor, l1Provider),
      l1
    )

    await checkL1Ownership(l1)
    await checkL2Ownership(l2)
  })
})

//// L1 contracts

async function checkL1RouterInitialization(
  l1Router: L1GatewayRouter,
  inbox: string,
  l2: L2
) {
  console.log('checkL1RouterInitialization')

  expect((await l1Router.defaultGateway()).toLowerCase()).to.be.eq(
    l2.standardGateway.toLowerCase()
  )
  expect((await l1Router.inbox()).toLowerCase()).to.be.eq(inbox.toLowerCase())
  expect((await l1Router.router()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )
  expect((await l1Router.counterpartGateway()).toLowerCase()).to.be.eq(
    l2.router.toLowerCase()
  )
}

async function checkL1StandardGatewayInitialization(
  l1ERC20Gateway: L1ERC20Gateway,
  l1: L1,
  l2: L2
) {
  console.log('checkL1StandardGatewayInitialization')

  expect((await l1ERC20Gateway.counterpartGateway()).toLowerCase()).to.be.eq(
    l2.standardGateway.toLowerCase()
  )
  expect((await l1ERC20Gateway.router()).toLowerCase()).to.be.eq(
    l1.router.toLowerCase()
  )
  expect((await l1ERC20Gateway.inbox()).toLowerCase()).to.be.eq(
    l1.inbox.toLowerCase()
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
  l1: L1,
  l2: L2
) {
  console.log('checkL1CustomGatewayInitialization')

  expect((await l1CustomGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    l2.customGateway.toLowerCase()
  )

  expect((await l1CustomGateway.router()).toLowerCase()).to.be.eq(
    l1.router.toLowerCase()
  )

  expect((await l1CustomGateway.inbox()).toLowerCase()).to.be.eq(
    l1.inbox.toLowerCase()
  )

  expect((await l1CustomGateway.whitelist()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL1WethGatewayInitialization(
  l1WethGateway: L1WethGateway,
  l1: L1,
  l2: L2
) {
  console.log('checkL1WethGatewayInitialization')

  expect((await l1WethGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    l2.wethGateway.toLowerCase()
  )

  expect((await l1WethGateway.router()).toLowerCase()).to.be.eq(
    l1.router.toLowerCase()
  )

  expect((await l1WethGateway.inbox()).toLowerCase()).to.be.eq(
    l1.inbox.toLowerCase()
  )

  expect((await l1WethGateway.l1Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l1WethGateway.l2Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL2UpgadeExecutorInitialization(
  l2Executor: UpgradeExecutor,
  l1: L1
) {
  console.log('checkL2UpgadeExecutorInitialization')

  //// check assigned/revoked roles are correctly set
  const adminRole = await l2Executor.ADMIN_ROLE()
  const executorRole = await l2Executor.EXECUTOR_ROLE()

  expect(await l2Executor.hasRole(adminRole, l2Executor.address)).to.be.true
  expect(await l2Executor.hasRole(executorRole, l1.rollupOwner)).to.be.true
  expect(await l2Executor.hasRole(executorRole, applyAlias(l1.upgradeExecutor)))
    .to.be.true
}

//// L2 contracts

async function checkL2RouterInitialization(l2Router: L2GatewayRouter) {
  console.log('checkL2RouterInitialization')

  expect((await l2Router.defaultGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2ERC20Gateway.toLowerCase()
  )

  expect((await l2Router.router()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l2Router.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1GatewayRouter.toLowerCase()
  )
}

async function checkL2StandardGatewayInitialization(
  l2ERC20Gateway: L2ERC20Gateway
) {
  console.log('checkL2StandardGatewayInitialization')

  expect((await l2ERC20Gateway.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1ERC20Gateway.toLowerCase()
  )

  expect((await l2ERC20Gateway.router()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2GatewayRouter.toLowerCase()
  )

  expect((await l2ERC20Gateway.beaconProxyFactory()).toLowerCase()).to.be.eq(
    (
      await L1ERC20Gateway__factory.connect(
        await l2ERC20Gateway.counterpartGateway(),
        _l1Provider
      ).l2BeaconProxyFactory()
    ).toLowerCase()
  )

  expect((await l2ERC20Gateway.cloneableProxyHash()).toLowerCase()).to.be.eq(
    (
      await L1ERC20Gateway__factory.connect(
        await l2ERC20Gateway.counterpartGateway(),
        _l1Provider
      ).cloneableProxyHash()
    ).toLowerCase()
  )
}

async function checkL2CustomGatewayInitialization(
  l2CustomGateway: L2CustomGateway
) {
  console.log('checkL2CustomGatewayInitialization')

  expect((await l2CustomGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1CustomGateway.toLowerCase()
  )

  expect((await l2CustomGateway.router()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2GatewayRouter.toLowerCase()
  )
}

async function checkL2WethGatewayInitialization(l2WethGateway: L2WethGateway) {
  console.log('checkL2WethGatewayInitialization')

  expect((await l2WethGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1WethGateway.toLowerCase()
  )

  expect((await l2WethGateway.router()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2GatewayRouter.toLowerCase()
  )

  expect((await l2WethGateway.l1Weth()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1Weth.toLowerCase()
  )

  expect((await l2WethGateway.l2Weth()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2Weth.toLowerCase()
  )
}

async function checkL1Ownership(l1: L1) {
  console.log('checkL1Ownership')

  // check proxyAdmins
  expect(await _getProxyAdmin(l1.router, l1Provider)).to.be.eq(l1.proxyAdmin)
  expect(await _getProxyAdmin(l1.standardGateway, l1Provider)).to.be.eq(
    l1.proxyAdmin
  )
  expect(await _getProxyAdmin(l1.customGateway, l1Provider)).to.be.eq(
    l1.proxyAdmin
  )
  if (l1.wethGateway !== ethers.constants.AddressZero) {
    expect(await _getProxyAdmin(l1.wethGateway, l1Provider)).to.be.eq(
      l1.proxyAdmin
    )
  }
  expect(await _getProxyAdmin(l1.upgradeExecutor, l1Provider)).to.be.eq(
    l1.proxyAdmin
  )

  // check ownables
  expect(await _getOwner(l1.proxyAdmin, l1Provider)).to.be.eq(
    l1.upgradeExecutor
  )
  expect(await _getOwner(l1.router, l1Provider)).to.be.eq(l1.upgradeExecutor)
  expect(await _getOwner(l1.customGateway, l1Provider)).to.be.eq(
    l1.upgradeExecutor
  )
  expect(await _getOwner(l1.upgradeExecutor, l1Provider)).to.be.eq(
    l1.upgradeExecutor
  )
}

async function checkL2Ownership(l2: L2) {
  console.log('checkL2Ownership')

  const l2ProxyAdmin = await _getProxyAdmin(l2.router, l2Provider)

  // check proxyAdmins
  expect(await _getProxyAdmin(l2.router, l2Provider)).to.be.eq(l2ProxyAdmin)
  expect(await _getProxyAdmin(l2.standardGateway, l2Provider)).to.be.eq(
    l2ProxyAdmin
  )
  expect(await _getProxyAdmin(l2.customGateway, l2Provider)).to.be.eq(
    l2ProxyAdmin
  )
  if (l2.wethGateway !== ethers.constants.AddressZero) {
    expect(await _getProxyAdmin(l2.wethGateway, l2Provider)).to.be.eq(
      l2ProxyAdmin
    )
  }
  expect(await _getProxyAdmin(l2.upgradeExecutor, l2Provider)).to.be.eq(
    l2ProxyAdmin
  )

  // check ownables
  expect(await _getOwner(l2ProxyAdmin, l2Provider)).to.be.eq(l2.upgradeExecutor)
}

//// utils
async function isUsingFeeToken(inbox: string, l1Provider: JsonRpcProvider) {
  const bridge = await IInbox__factory.connect(inbox, l1Provider).bridge()

  try {
    await IERC20Bridge__factory.connect(bridge, l1Provider).nativeToken()
  } catch {
    return false
  }

  return true
}

async function _getTokenBridgeAddresses(
  rollupAddress: string,
  l1TokenBridgeCreatorAddress: string
) {
  const inboxAddress = await RollupCore__factory.connect(
    rollupAddress,
    l1Provider
  ).inbox()

  const l1TokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    l1TokenBridgeCreatorAddress,
    l1Provider
  )

  //// L1
  // find all the events emitted by this address
  const filter: ethers.providers.Filter = {
    address: l1TokenBridgeCreatorAddress,
    topics: [
      ethers.utils.id('OrbitTokenBridgeCreated'),
      ethers.utils.hexZeroPad(inboxAddress, 32),
    ],
  }

  const currentBlock = await l1Provider.getBlockNumber()
  const fromBlock = currentBlock - 100000 // ~last 24h on
  const logs = await l1Provider.getLogs({
    ...filter,
    fromBlock: fromBlock,
    toBlock: 'latest',
  })

  if (logs.length === 0) {
    throw new Error("Couldn't find any OrbitTokenBridgeCreated events")
  }

  const logData = l1TokenBridgeCreator.interface.parseLog(logs[0])
  console.log(logData)

  const {
    inbox,
    owner,
    router,
    standardGateway,
    customGateway,
    wethGateway,
    proxyAdmin,
    upgradeExecutor,
  } = logData.args
  const l1 = {
    inbox,
    rollupOwner: owner,
    router,
    standardGateway,
    customGateway,
    wethGateway,
    proxyAdmin,
    upgradeExecutor,
  }

  //// L2
  const l2 = {
    router: await l1TokenBridgeCreator.getCanonicalL2RouterAddress(),
    standardGateway:
      await l1TokenBridgeCreator.getCanonicalL2StandardGatewayAddress(),
    customGateway:
      await l1TokenBridgeCreator.getCanonicalL2CustomGatewayAddress(),
    wethGateway: await l1TokenBridgeCreator.getCanonicalL2WethGatewayAddress(),
    weth: await l1TokenBridgeCreator.getCanonicalL2WethAddress(),
    upgradeExecutor:
      await l1TokenBridgeCreator.getCanonicalL2UpgradeExecutorAddress(),
  }

  return {
    l1,
    l2,
  }
}

async function _getProxyAdmin(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  return _getAddressAtStorageSlot(
    contractAddress,
    provider,
    '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
  )
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
}
