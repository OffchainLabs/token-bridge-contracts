import { BigNumber, Wallet, ethers } from 'ethers'
import { JsonRpcProvider } from '@ethersproject/providers'
import { ArbitrumNetwork, registerCustomArbitrumNetwork } from '@arbitrum/sdk'
import { Bridge__factory } from '@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'
import { execSync } from 'child_process'
import {
  createTokenBridge,
  deployTokenBridgeCreatorOnParentChain,
  getEstimateForDeployingFactory,
  registerGateway,
} from '../atomicTokenBridgeDeployer'
import {
  ERC20__factory,
  IERC20Bridge__factory,
  IOwnable__factory,
  TestWETH9__factory,
} from '../../build/types'

const LOCALHOST_L2_RPC = 'http://127.0.0.1:8547'
const LOCALHOST_L3_RPC = 'http://127.0.0.1:3347'
const LOCALHOST_L3_OWNER_KEY =
  '0xecdf21cb41c65afb51f91df408b7656e2c8739a5877f2814add0afd780cc210e'

export const deployCreate2Factory = async (
  deployerWallet: Wallet
): Promise<void> => {
  const create2FactoryAddress = '0x4e59b44847b379578588920ca78fbf26c0b4956c'
  const factoryCode = await deployerWallet.provider.getCode(
    create2FactoryAddress
  )
  if (factoryCode.length <= 2) {
    console.log('CREATE2 factory not yet deployed. Deploying...')
    const fundingTx = await deployerWallet.sendTransaction({
      to: '0x3fab184622dc19b6109349b94811493bf2a45362',
      value: ethers.utils.parseEther('0.01'),
    })
    await fundingTx.wait()
    const create2SignedTx =
      '0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222'
    const create2DeployTx = await deployerWallet.provider.sendTransaction(
      create2SignedTx
    )
    await create2DeployTx.wait()
    console.log(`CREATE2 factory deployed at ${create2FactoryAddress}`)
  }
}

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
  const { l2Network: coreL2Network } = await getLocalNetwork(
    parentRpc,
    childRpc,
    rollupAddress
  )
  registerCustomArbitrumNetwork(coreL2Network)

  // prerequisite - deploy CREATE2 factory
  await deployCreate2Factory(parentDeployer)

  // prerequisite - deploy L1 creator and set templates
  console.log('Deploying TokenBridgeCreator and templates:')

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
  const gasLimitForFactoryDeploymentOnChildChain =
    deployFactoryGasParams.gasLimit

  const { parentTokenBridgeCreator, retryableSender } =
    await deployTokenBridgeCreatorOnParentChain(
      parentDeployer,
      l1Weth,
      gasLimitForFactoryDeploymentOnChildChain,
      false,
      true
    )

  console.log('')
  console.log(
    `TokenBridgeCreator deployed at ${parentTokenBridgeCreator.address}`
  )
  console.log(
    `TokenBridgeRetryableSender deployed at ${retryableSender.address}`
  )

  // create token bridge
  console.log('')
  console.log(
    `Creating a token bridge for rollup ${coreL2Network.ethBridge.rollup}:`
  )
  const { l1Deployment, l2Deployment, l1MultiCall, l1ProxyAdmin } =
    await createTokenBridge(
      parentDeployer,
      childDeployer.provider!,
      parentTokenBridgeCreator,
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

  const l2Network: ArbitrumNetwork = {
    ...coreL2Network,
    tokenBridge: {
      parentCustomGateway: l1Deployment.customGateway,
      parentErc20Gateway: l1Deployment.standardGateway,
      parentGatewayRouter: l1Deployment.router,
      parentMultiCall: l1MultiCall,
      parentProxyAdmin: l1ProxyAdmin,
      parentWeth: l1Deployment.weth,
      parentWethGateway: l1Deployment.wethGateway,

      childCustomGateway: l2Deployment.customGateway,
      childErc20Gateway: l2Deployment.standardGateway,
      childGatewayRouter: l2Deployment.router,
      childMultiCall: l2Deployment.multicall,
      childProxyAdmin: l2Deployment.proxyAdmin,
      childWeth: l2Deployment.weth,
      childWethGateway: l2Deployment.wethGateway,
    },
  }

  const l1TokenBridgeCreatorAddress = parentTokenBridgeCreator.address
  const retryableSenderAddress = retryableSender.address

  return {
    l2Network,
    l1TokenBridgeCreatorAddress,
    retryableSenderAddress,
  }
}

export const getLocalNetwork = async (
  l1Url: string,
  l2Url: string,
  rollupAddress?: string
): Promise<{
  l2Network: ArbitrumNetwork
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

  let nativeToken: string | undefined = undefined
  try {
    nativeToken = await IERC20Bridge__factory.connect(data.bridge, l1Provider).nativeToken()
  }
  catch {}

  const l2Network: ArbitrumNetwork = {
    nativeToken,
    parentChainId: l1NetworkInfo.chainId,
    chainId: l2NetworkInfo.chainId,
    confirmPeriodBlocks: 20,
    ethBridge: {
      bridge: data.bridge,
      inbox: data.inbox,
      outbox: outboxAddr,
      rollup: data.rollup,
      sequencerInbox: data['sequencer-inbox'],
    },
    isCustom: true,
    name: 'OrbitLocal',
    retryableLifetimeSeconds: 7 * 24 * 60 * 60,
    isTestnet: true
  }
  return {
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
