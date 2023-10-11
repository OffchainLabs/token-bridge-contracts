import { JsonRpcProvider, Provider, Filter } from '@ethersproject/providers'
import {
  BeaconProxyFactory__factory,
  IERC20Bridge__factory,
  IInbox__factory,
  IOwnable__factory,
  IRollupCore__factory,
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
  l1Url: process.env.BASECHAIN_RPC || 'http://localhost:8545',
  l2Url: process.env.ORBIT_RPC || 'http://localhost:8547',
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

    /// get addresses
    const { l1, l2 } = await _getTokenBridgeAddresses(
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
      L1GatewayRouter__factory.connect(l1.router, l1Provider),
      l1,
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
      L2GatewayRouter__factory.connect(l2.router, l2Provider),
      l1,
      l2
    )

    await checkL2StandardGatewayInitialization(
      L2ERC20Gateway__factory.connect(l2.standardGateway, l2Provider),
      l1,
      l2
    )

    await checkL2CustomGatewayInitialization(
      L2CustomGateway__factory.connect(l2.customGateway, l2Provider),
      l1,
      l2
    )

    if (!usingFeeToken) {
      await checkL2WethGatewayInitialization(
        L2WethGateway__factory.connect(l2.wethGateway, l2Provider),
        l1,
        l2
      )
    }

    const upgExecutor = new ethers.Contract(
      l2.upgradeExecutor,
      UpgradeExecutorABI,
      l2Provider
    )
    await checkL2UpgradeExecutorInitialization(upgExecutor, l1)

    await checkL1Ownership(l1)
    await checkL2Ownership(l2)
  })
})

//// L1 contracts

async function checkL1RouterInitialization(
  l1Router: L1GatewayRouter,
  l1: L1,
  l2: L2
) {
  console.log('checkL1RouterInitialization')

  expect((await l1Router.defaultGateway()).toLowerCase()).to.be.eq(
    l1.standardGateway.toLowerCase()
  )
  expect((await l1Router.inbox()).toLowerCase()).to.be.eq(
    l1.inbox.toLowerCase()
  )
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

async function checkL2UpgradeExecutorInitialization(
  l2Executor: Contract,
  l1: L1
) {
  console.log('checkL2UpgradeExecutorInitialization')

  //// check assigned/revoked roles are correctly set
  const adminRole = await l2Executor.ADMIN_ROLE()
  const executorRole = await l2Executor.EXECUTOR_ROLE()

  expect(await l2Executor.hasRole(adminRole, l2Executor.address)).to.be.true
  expect(await l2Executor.hasRole(executorRole, l1.rollupOwner)).to.be.true
  const aliasedL1Executor = applyAlias(l1.upgradeExecutor)
  expect(await l2Executor.hasRole(executorRole, aliasedL1Executor)).to.be.true
}

//// L2 contracts

async function checkL2RouterInitialization(
  l2Router: L2GatewayRouter,
  l1: L1,
  l2: L2
) {
  console.log('checkL2RouterInitialization')

  expect((await l2Router.defaultGateway()).toLowerCase()).to.be.eq(
    l2.standardGateway.toLowerCase()
  )

  expect((await l2Router.router()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l2Router.counterpartGateway()).toLowerCase()).to.be.eq(
    l1.router.toLowerCase()
  )
}

async function checkL2StandardGatewayInitialization(
  l2ERC20Gateway: L2ERC20Gateway,
  l1: L1,
  l2: L2
) {
  console.log('checkL2StandardGatewayInitialization')

  expect((await l2ERC20Gateway.counterpartGateway()).toLowerCase()).to.be.eq(
    l1.standardGateway.toLowerCase()
  )

  expect((await l2ERC20Gateway.router()).toLowerCase()).to.be.eq(
    l2.router.toLowerCase()
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
  l1: L1,
  l2: L2
) {
  console.log('checkL2CustomGatewayInitialization')

  expect((await l2CustomGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    l1.customGateway.toLowerCase()
  )

  expect((await l2CustomGateway.router()).toLowerCase()).to.be.eq(
    l2.router.toLowerCase()
  )
}

async function checkL2WethGatewayInitialization(
  l2WethGateway: L2WethGateway,
  l1: L1,
  l2: L2
) {
  console.log('checkL2WethGatewayInitialization')

  expect((await l2WethGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    l1.wethGateway.toLowerCase()
  )

  expect((await l2WethGateway.router()).toLowerCase()).to.be.eq(
    l2.router.toLowerCase()
  )

  expect((await l2WethGateway.l1Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l2WethGateway.l2Weth()).toLowerCase()).to.not.be.eq(
    ethers.constants.AddressZero
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

  if (l2.wethGateway != ethers.constants.AddressZero) {
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

  const filter: Filter = {
    address: l1TokenBridgeCreatorAddress,
    topics: [
      ethers.utils.id(
        'OrbitTokenBridgeCreated(address,address,address,address,address,address,address,address)'
      ),
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
    throw new Error(
      "Couldn't find any OrbitTokenBridgeCreated events in block range[" +
        fromBlock +
        ',latest]'
    )
  }

  const logData = l1TokenBridgeCreator.interface.parseLog(logs[0])

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
    inbox: inbox.toLowerCase(),
    rollupOwner: owner.toLowerCase(),
    router: router.toLowerCase(),
    standardGateway: standardGateway.toLowerCase(),
    customGateway: customGateway.toLowerCase(),
    wethGateway: wethGateway.toLowerCase(),
    proxyAdmin: proxyAdmin.toLowerCase(),
    upgradeExecutor: upgradeExecutor.toLowerCase(),
  }

  const usingFeeToken = await isUsingFeeToken(l1.inbox, l1Provider)

  const chainId = await IRollupCore__factory.connect(
    rollupAddress,
    l1Provider
  ).chainId()

  //// L2
  const l2 = {
    router: (
      await l1TokenBridgeCreator.getCanonicalL2RouterAddress(chainId)
    ).toLowerCase(),
    standardGateway: (
      await l1TokenBridgeCreator.getCanonicalL2StandardGatewayAddress(chainId)
    ).toLowerCase(),
    customGateway: (
      await l1TokenBridgeCreator.getCanonicalL2CustomGatewayAddress(chainId)
    ).toLowerCase(),
    wethGateway: (usingFeeToken
      ? ethers.constants.AddressZero
      : await l1TokenBridgeCreator.getCanonicalL2WethGatewayAddress(chainId)
    ).toLowerCase(),
    weth: (usingFeeToken
      ? ethers.constants.AddressZero
      : await l1TokenBridgeCreator.getCanonicalL2WethAddress(chainId)
    ).toLowerCase(),
    upgradeExecutor: (
      await l1TokenBridgeCreator.getCanonicalL2UpgradeExecutorAddress(chainId)
    ).toLowerCase(),
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
  return (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
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
