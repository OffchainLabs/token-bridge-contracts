import { L1Network, L2Network, getL1Network, getL2Network } from '@arbitrum/sdk'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  BeaconProxyFactory__factory,
  IOwnable,
  IOwnable__factory,
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
  ProxyAdmin,
  ProxyAdmin__factory,
} from '../build/types'
import path from 'path'
import fs from 'fs'
import {
  addCustomNetwork,
  l1Networks,
  l2Networks,
} from '@arbitrum/sdk/dist/lib/dataEntities/networks'
import { expect } from 'chai'
import { ethers } from 'hardhat'

const config = {
  arbUrl: 'http://localhost:8547',
  ethUrl: 'http://localhost:8545',
}

let _l1Network: L1Network
let _l2Network: L2Network

let _l1Provider: JsonRpcProvider
let _l2Provider: JsonRpcProvider

describe('tokenBridge', () => {
  it('should have deployed and initialized token bridge contracts', async function () {
    const { l1Network, l1Provider, l2Network, l2Provider } =
      await getProvidersAndSetupNetworks({
        l1Url: config.ethUrl,
        l2Url: config.arbUrl,
        networkFilename: './network.json',
      })

    _l1Network = l1Network
    _l2Network = l2Network

    _l1Provider = l1Provider
    _l2Provider = l2Provider

    //// L1 checks

    await checkL1RouterInitialization(
      L1GatewayRouter__factory.connect(
        _l2Network.tokenBridge.l1GatewayRouter,
        l1Provider
      )
    )

    await checkL1StandardGatewayInitialization(
      L1ERC20Gateway__factory.connect(
        _l2Network.tokenBridge.l1ERC20Gateway,
        l1Provider
      )
    )

    await checkL1CustomGatewayInitialization(
      L1CustomGateway__factory.connect(
        _l2Network.tokenBridge.l1CustomGateway,
        l1Provider
      )
    )

    await checkL1WethGatewayInitialization(
      L1WethGateway__factory.connect(
        _l2Network.tokenBridge.l1WethGateway,
        l1Provider
      )
    )

    //// L2 checks

    await checkL2RouterInitialization(
      L2GatewayRouter__factory.connect(
        _l2Network.tokenBridge.l2GatewayRouter,
        l2Provider
      )
    )

    await checkL2StandardGatewayInitialization(
      L2ERC20Gateway__factory.connect(
        _l2Network.tokenBridge.l2ERC20Gateway,
        l2Provider
      )
    )

    await checkL2CustomGatewayInitialization(
      L2CustomGateway__factory.connect(
        _l2Network.tokenBridge.l2CustomGateway,
        l2Provider
      )
    )

    const rollupOwner = await IOwnable__factory.connect(
      _l2Network.ethBridge.rollup,
      l1Provider
    ).owner()
    await checkOwnership(
      rollupOwner.toLowerCase(),
      ProxyAdmin__factory.connect(
        _l2Network.tokenBridge.l1ProxyAdmin,
        l1Provider
      ),
      ProxyAdmin__factory.connect(
        _l2Network.tokenBridge.l2ProxyAdmin,
        l2Provider
      ),
      L1GatewayRouter__factory.connect(
        _l2Network.tokenBridge.l1GatewayRouter,
        l1Provider
      ),
      L1CustomGateway__factory.connect(
        _l2Network.tokenBridge.l1CustomGateway,
        l1Provider
      )
    )

    await checkL2WethGatewayInitialization(
      L2WethGateway__factory.connect(
        _l2Network.tokenBridge.l2WethGateway,
        l2Provider
      )
    )
  })
})

//// L1 contracts

async function checkL1RouterInitialization(l1Router: L1GatewayRouter) {
  console.log('checkL1RouterInitialization')

  expect((await l1Router.defaultGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1ERC20Gateway.toLowerCase()
  )

  expect((await l1Router.inbox()).toLowerCase()).to.be.eq(
    _l2Network.ethBridge.inbox.toLowerCase()
  )

  expect((await l1Router.router()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )

  expect((await l1Router.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2GatewayRouter.toLowerCase()
  )
}

async function checkL1StandardGatewayInitialization(
  l1ERC20Gateway: L1ERC20Gateway
) {
  console.log('checkL1StandardGatewayInitialization')

  expect((await l1ERC20Gateway.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2ERC20Gateway.toLowerCase()
  )
  expect((await l1ERC20Gateway.router()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1GatewayRouter.toLowerCase()
  )
  expect((await l1ERC20Gateway.inbox()).toLowerCase()).to.be.eq(
    _l2Network.ethBridge.inbox.toLowerCase()
  )
  expect((await l1ERC20Gateway.l2BeaconProxyFactory()).toLowerCase()).to.be.eq(
    (
      await L2ERC20Gateway__factory.connect(
        await l1ERC20Gateway.counterpartGateway(),
        _l2Provider
      ).beaconProxyFactory()
    ).toLowerCase()
  )
  expect((await l1ERC20Gateway.cloneableProxyHash()).toLowerCase()).to.be.eq(
    (
      await BeaconProxyFactory__factory.connect(
        await l1ERC20Gateway.l2BeaconProxyFactory(),
        _l2Provider
      ).cloneableProxyHash()
    ).toLowerCase()
  )
  expect((await l1ERC20Gateway.whitelist()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL1CustomGatewayInitialization(
  l1CustomGateway: L1CustomGateway
) {
  console.log('checkL1CustomGatewayInitialization')

  expect((await l1CustomGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2CustomGateway.toLowerCase()
  )

  expect((await l1CustomGateway.router()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1GatewayRouter.toLowerCase()
  )

  expect((await l1CustomGateway.inbox()).toLowerCase()).to.be.eq(
    _l2Network.ethBridge.inbox.toLowerCase()
  )

  // TODO
  // owner check

  expect((await l1CustomGateway.whitelist()).toLowerCase()).to.be.eq(
    ethers.constants.AddressZero
  )
}

async function checkL1WethGatewayInitialization(l1WethGateway: L1WethGateway) {
  console.log('checkL1WethGatewayInitialization')

  expect((await l1WethGateway.counterpartGateway()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2WethGateway.toLowerCase()
  )

  expect((await l1WethGateway.router()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1GatewayRouter.toLowerCase()
  )

  expect((await l1WethGateway.inbox()).toLowerCase()).to.be.eq(
    _l2Network.ethBridge.inbox.toLowerCase()
  )

  expect((await l1WethGateway.l1Weth()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l1Weth.toLowerCase()
  )

  expect((await l1WethGateway.l2Weth()).toLowerCase()).to.be.eq(
    _l2Network.tokenBridge.l2Weth.toLowerCase()
  )
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

async function checkOwnership(
  rollupOwner: string,
  l1ProxyAdmin: ProxyAdmin,
  l2ProxyAdmin: ProxyAdmin,
  l1Router: L1GatewayRouter,
  l1CustomGateway: L1CustomGateway
) {
  console.log('checkL2ProxyAdminInitialization')

  expect(rollupOwner).to.be.eq((await l1ProxyAdmin.owner()).toLowerCase())
  expect(rollupOwner).to.be.eq((await l2ProxyAdmin.owner()).toLowerCase())
  expect(rollupOwner).to.be.eq((await l1Router.owner()).toLowerCase())
  expect(rollupOwner).to.be.eq((await l1CustomGateway.owner()).toLowerCase())
}

export const getProvidersAndSetupNetworks = async (setupConfig: {
  l1Url: string
  l2Url: string
  networkFilename?: string
}): Promise<{
  l1Network: L1Network
  l2Network: L2Network
  l1Provider: JsonRpcProvider
  l2Provider: JsonRpcProvider
}> => {
  const l1Provider = new JsonRpcProvider(setupConfig.l1Url)
  const l2Provider = new JsonRpcProvider(setupConfig.l2Url)

  if (setupConfig.networkFilename) {
    // check if theres an existing network available
    const localNetworkFile = path.join(
      __dirname,
      '..',
      setupConfig.networkFilename
    )
    if (fs.existsSync(localNetworkFile)) {
      const { l1Network, l2Network } = JSON.parse(
        fs.readFileSync(localNetworkFile).toString()
      ) as {
        l1Network: L1Network
        l2Network: L2Network
      }

      const existingL1Network = l1Networks[l1Network.chainID.toString()]
      const existingL2Network = l2Networks[l2Network.chainID.toString()]
      if (!existingL2Network) {
        addCustomNetwork({
          // dont add the l1 network if it's already been added
          customL1Network: existingL1Network ? undefined : l1Network,
          customL2Network: l2Network,
        })
      }

      return {
        l1Network,
        l1Provider,
        l2Network,
        l2Provider,
      }
    } else throw Error(`Missing file ${localNetworkFile}`)
  } else {
    return {
      l1Network: await getL1Network(l1Provider),
      l1Provider,
      l2Network: await getL2Network(l2Provider),
      l2Provider,
    }
  }
}
