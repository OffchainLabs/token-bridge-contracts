import { BigNumber, Wallet, ethers } from 'ethers'
import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network, addCustomNetwork } from '@arbitrum/sdk'
import { Bridge__factory } from '@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import { execSync } from 'child_process'
import {
  createTokenBridge,
  deployL1TokenBridgeCreator,
  getEstimateForDeployingFactory,
  registerGateway,
} from '../atomicTokenBridgeDeployer'
import {
  ERC20__factory,
  IOwnable__factory,
  TestWETH9__factory,
} from '../../build/types'

const LOCALHOST_L2_RPC = 'http://127.0.0.1:8547'
const LOCALHOST_L3_RPC = 'http://127.0.0.1:3347'
const LOCALHOST_L3_OWNER_KEY =
  '0xecdf21cb41c65afb51f91df408b7656e2c8739a5877f2814add0afd780cc210e'
/**
 * Steps:
 * - read network info from local container and register networks
 * - deploy L1 bridge creator and set templates
 * - do single TX deployment of token bridge
 * - populate network objects with new addresses and return it
 *
 * @param parentDeployer
 * @param childDeployer
 * @param l1Url
 * @param l2Url
 * @returns
 */
export const setupTokenBridgeInLocalEnv = async () => {
  // set RPCs either from env vars or use defaults
  let parentRpc = process.env['PARENT_RPC'] as string
  let childRpc = process.env['CHILD_RPC'] as string
  if (parentRpc === undefined || childRpc === undefined) {
    parentRpc = LOCALHOST_L2_RPC
    childRpc = LOCALHOST_L3_RPC
  }

  // set deployer keys either from env vars or use defaults
  let parentDeployerKey = process.env['PARENT_KEY'] as string
  let childDeployerKey = process.env['CHILD_KEY'] as string
  if (parentDeployerKey === undefined || childDeployerKey === undefined) {
    parentDeployerKey = ethers.utils.sha256(
      ethers.utils.toUtf8Bytes('user_token_bridge_deployer')
    )
    childDeployerKey = ethers.utils.sha256(
      ethers.utils.toUtf8Bytes('user_token_bridge_deployer')
    )
  }

  // set rollup owner either from env vars or use defaults
  let rollupOwnerKey = process.env['ROLLUP_OWNER_KEY'] as string
  if (rollupOwnerKey === undefined) {
    rollupOwnerKey = LOCALHOST_L3_OWNER_KEY
  }
  const rollupOwnerAddress = ethers.utils.computeAddress(rollupOwnerKey)

  // if no ROLLUP_ADDRESS is defined, it will be pulled from local container
  const rollupAddress = process.env['ROLLUP_ADDRESS'] as string

  // create deployer wallets
  const parentDeployer = new ethers.Wallet(
    parentDeployerKey,
    new ethers.providers.JsonRpcProvider(parentRpc)
  )
  const childDeployer = new ethers.Wallet(
    childDeployerKey,
    new ethers.providers.JsonRpcProvider(childRpc)
  )

  /// register networks
  const { l1Network, l2Network: coreL2Network } = await getLocalNetworks(
    parentRpc,
    childRpc,
    rollupAddress
  )
  const _l1Network = l1Network as L2Network
  const ethLocal: L1Network = {
    blockTime: 10,
    chainID: _l1Network.partnerChainID,
    explorerUrl: '',
    isCustom: true,
    name: 'EthLocal',
    partnerChainIDs: [_l1Network.chainID],
    isArbitrum: false,
  }
  addCustomNetwork({
    customL1Network: ethLocal,
    customL2Network: _l1Network,
  })
  addCustomNetwork({
    customL2Network: coreL2Network,
  })

  // prerequisite - deploy L1 creator and set templates
  console.log('Deploying L1TokenBridgeCreator')

  let l1Weth = process.env['PARENT_WETH_OVERRIDE']
  if (l1Weth === undefined || l1Weth === '') {
    const l1WethContract = await new TestWETH9__factory(parentDeployer).deploy(
      'WETH',
      'WETH'
    )
    await l1WethContract.deployed()

    l1Weth = l1WethContract.address
  }

  //// run retryable estimate for deploying L2 factory
  const deployFactoryGasParams = await getEstimateForDeployingFactory(
    parentDeployer,
    childDeployer.provider!
  )
  const gasLimitForL2FactoryDeployment = deployFactoryGasParams.gasLimit

  const { l1TokenBridgeCreator, retryableSender } =
    await deployL1TokenBridgeCreator(
      parentDeployer,
      l1Weth,
      gasLimitForL2FactoryDeployment
    )
  console.log('L1TokenBridgeCreator', l1TokenBridgeCreator.address)
  console.log('L1TokenBridgeRetryableSender', retryableSender.address)

  // create token bridge
  console.log(
    '\nCreating token bridge for rollup',
    coreL2Network.ethBridge.rollup
  )
  const { l1Deployment, l2Deployment, l1MultiCall, l1ProxyAdmin } =
    await createTokenBridge(
      parentDeployer,
      childDeployer.provider!,
      l1TokenBridgeCreator,
      coreL2Network.ethBridge.rollup,
      rollupOwnerAddress
    )

  // register weth gateway if it exists
  if (l1Deployment.wethGateway !== ethers.constants.AddressZero) {
    const upExecAddress = await IOwnable__factory.connect(
      coreL2Network.ethBridge.rollup,
      parentDeployer
    ).owner()

    await registerGateway(
      new Wallet(rollupOwnerKey, parentDeployer.provider!),
      childDeployer.provider!,
      upExecAddress,
      l1Deployment.router,
      [l1Weth],
      [l1Deployment.wethGateway]
    )
  }

  const l2Network: L2Network = {
    ...coreL2Network,
    tokenBridge: {
      l1CustomGateway: l1Deployment.customGateway,
      l1ERC20Gateway: l1Deployment.standardGateway,
      l1GatewayRouter: l1Deployment.router,
      l1MultiCall: l1MultiCall,
      l1ProxyAdmin: l1ProxyAdmin,
      l1Weth: l1Deployment.weth,
      l1WethGateway: l1Deployment.wethGateway,

      l2CustomGateway: l2Deployment.customGateway,
      l2ERC20Gateway: l2Deployment.standardGateway,
      l2GatewayRouter: l2Deployment.router,
      l2Multicall: l2Deployment.multicall,
      l2ProxyAdmin: l2Deployment.proxyAdmin,
      l2Weth: l2Deployment.weth,
      l2WethGateway: l2Deployment.wethGateway,
    },
  }

  const l1TokenBridgeCreatorAddress = l1TokenBridgeCreator.address
  const retryableSenderAddress = retryableSender.address

  return {
    l1Network,
    l2Network,
    l1TokenBridgeCreatorAddress,
    retryableSenderAddress,
  }
}

export const getLocalNetworks = async (
  l1Url: string,
  l2Url: string,
  rollupAddress?: string
): Promise<{
  l1Network: L1Network | L2Network
  l2Network: L2Network
}> => {
  const l1Provider = new JsonRpcProvider(l1Url)
  const l2Provider = new JsonRpcProvider(l2Url)

  const l1NetworkInfo = await l1Provider.getNetwork()
  const l2NetworkInfo = await l2Provider.getNetwork()

  /// get parent chain info
  const container = execSync(
    'docker ps --filter "name=sequencer" --format "{{.Names}}"'
  )
    .toString()
    .trim()
  const l2DeploymentData = execSync(
    `docker exec ${container} cat /config/deployment.json`
  ).toString()
  const l2Data = JSON.parse(l2DeploymentData) as {
    bridge: string
    inbox: string
    ['sequencer-inbox']: string
    rollup: string
  }

  const l1Network: L1Network | L2Network = {
    partnerChainID: 1337,
    partnerChainIDs: [l2NetworkInfo.chainId],
    isArbitrum: true,
    confirmPeriodBlocks: 20,
    retryableLifetimeSeconds: 7 * 24 * 60 * 60,
    nitroGenesisBlock: 0,
    nitroGenesisL1Block: 0,
    depositTimeout: 900000,
    chainID: 412346,
    explorerUrl: '',
    isCustom: true,
    name: 'ArbLocal',
    blockTime: 0.25,
    ethBridge: {
      bridge: l2Data.bridge,
      inbox: l2Data.inbox,
      outbox: '',
      rollup: l2Data.rollup,
      sequencerInbox: l2Data['sequencer-inbox'],
    },
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

  /// get L3 info
  let deploymentData: string
  let data = {
    bridge: '',
    inbox: '',
    'sequencer-inbox': '',
    rollup: '',
  }

  if (rollupAddress === undefined || rollupAddress === '') {
    let sequencerContainer = execSync(
      'docker ps --filter "name=l3node" --format "{{.Names}}"'
    )
      .toString()
      .trim()

    deploymentData = execSync(
      `docker exec ${sequencerContainer} cat /config/l3deployment.json`
    ).toString()

    data = JSON.parse(deploymentData) as {
      bridge: string
      inbox: string
      ['sequencer-inbox']: string
      rollup: string
    }
  } else {
    const rollup = RollupAdminLogic__factory.connect(rollupAddress!, l1Provider)
    data.bridge = await rollup.bridge()
    data.inbox = await rollup.inbox()
    data['sequencer-inbox'] = await rollup.sequencerInbox()
    data.rollup = rollupAddress!
  }

  const bridge = Bridge__factory.connect(data.bridge, l1Provider)
  const outboxAddr = await bridge.allowedOutboxList(0)

  const l2Network: L2Network = {
    partnerChainID: l1NetworkInfo.chainId,
    partnerChainIDs: [],
    chainID: l2NetworkInfo.chainId,
    confirmPeriodBlocks: 20,
    ethBridge: {
      bridge: data.bridge,
      inbox: data.inbox,
      outbox: outboxAddr,
      rollup: data.rollup,
      sequencerInbox: data['sequencer-inbox'],
    },
    explorerUrl: '',
    isArbitrum: true,
    isCustom: true,
    blockTime: 0.25,
    name: 'OrbitLocal',
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
  return {
    l1Network,
    l2Network,
  }
}

/**
 * Scale the amount from 18-denomination to the fee token decimals denomination
 */
export async function _getScaledAmount(
  feeToken: string,
  amount: BigNumber,
  provider: ethers.providers.Provider
): Promise<BigNumber> {
  const decimals = await ERC20__factory.connect(feeToken, provider).decimals()
  if (decimals == 18) {
    return amount
  } else if (decimals < 18) {
    let scaledAmount = amount.div(BigNumber.from(10).pow(18 - decimals))
    // round up if necessary
    if (scaledAmount.mul(BigNumber.from(10).pow(18 - decimals)).lt(amount)) {
      scaledAmount = scaledAmount.add(1)
    }
    return scaledAmount
  } else {
    return amount.mul(BigNumber.from(10).pow(decimals - 18))
  }
}
