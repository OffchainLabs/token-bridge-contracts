import {
  ParentToChildMessageGasEstimator,
  ParentToChildMessageStatus,
  ParentTransactionReceipt,
  ArbitrumNetwork,
} from '@arbitrum/sdk'
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'
import { JsonRpcProvider } from '@ethersproject/providers'
import { expect } from 'chai'
import {
  _getScaledAmount,
  setupTokenBridgeInLocalEnv,
} from '../scripts/local-deployment/localDeploymentLib'
import {
  ERC20,
  ERC20__factory,
  IERC20Bridge__factory,
  IInbox__factory,
  L1GatewayRouter__factory,
  L1OrbitGatewayRouter__factory,
  L1YbbERC20Gateway__factory,
  L1YbbCustomGateway__factory,
  L2CustomGateway__factory,
  L2GatewayRouter__factory,
  MasterVaultFactory__factory,
  TestArbCustomToken__factory,
  TestCustomTokenL1__factory,
  TestERC20__factory,
  TestOrbitCustomTokenL1__factory,
} from '../build/types'
import { defaultAbiCoder } from 'ethers/lib/utils'
import { BigNumber, Wallet, ethers } from 'ethers'
import { exit } from 'process'
import { TokenBridge } from '@arbitrum/sdk/dist/lib/dataEntities/networks'

const config = {
  parentUrl: 'http://127.0.0.1:8547',
  childUrl: 'http://127.0.0.1:3347',
}

const LOCALHOST_L3_OWNER_KEY =
  '0xecdf21cb41c65afb51f91df408b7656e2c8739a5877f2814add0afd780cc210e'

let parentProvider: JsonRpcProvider
let childProvider: JsonRpcProvider

let deployerL1Wallet: Wallet
let deployerL2Wallet: Wallet

let userL1Wallet: Wallet
let userL2Wallet: Wallet

let _l2Network: ArbitrumNetwork & { tokenBridge: TokenBridge }

let nativeToken: ERC20 | undefined

describe('YBB Token Bridge', () => {
  before(async function () {
    parentProvider = new ethers.providers.JsonRpcProvider(config.parentUrl)
    childProvider = new ethers.providers.JsonRpcProvider(config.childUrl)

    const testDevKey =
      '0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659'
    const testDevL1Wallet = new ethers.Wallet(testDevKey, parentProvider)
    const testDevL2Wallet = new ethers.Wallet(testDevKey, childProvider)

    const deployerKey = ethers.utils.sha256(
      ethers.utils.toUtf8Bytes('user_token_bridge_deployer')
    )
    deployerL1Wallet = new ethers.Wallet(deployerKey, parentProvider)
    deployerL2Wallet = new ethers.Wallet(deployerKey, childProvider)
    await (
      await testDevL1Wallet.sendTransaction({
        to: deployerL1Wallet.address,
        value: ethers.utils.parseEther('20.0'),
      })
    ).wait()
    await (
      await testDevL2Wallet.sendTransaction({
        to: deployerL2Wallet.address,
        value: ethers.utils.parseEther('20.0'),
      })
    ).wait()

    const { l2Network } = await setupTokenBridgeInLocalEnv({ isYbb: true })
    if (!l2Network.tokenBridge) {
      throw new Error('L2 network does not have token bridge configured')
    }
    _l2Network = l2Network as ArbitrumNetwork & { tokenBridge: TokenBridge }

    // create user wallets and fund them
    const userKey = ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_wallet'))
    userL1Wallet = new ethers.Wallet(userKey, parentProvider)
    userL2Wallet = new ethers.Wallet(userKey, childProvider)
    await (
      await deployerL1Wallet.sendTransaction({
        to: userL1Wallet.address,
        value: ethers.utils.parseEther('10.0'),
      })
    ).wait()
    await (
      await deployerL2Wallet.sendTransaction({
        to: userL2Wallet.address,
        value: ethers.utils.parseEther('10.0'),
      })
    ).wait()

    const nativeTokenAddress = await getFeeToken(
      l2Network.ethBridge.inbox,
      parentProvider
    )
    nativeToken =
      nativeTokenAddress === ethers.constants.AddressZero
        ? undefined
        : ERC20__factory.connect(nativeTokenAddress, userL1Wallet)

    if (nativeToken) {
      const supply = await nativeToken.balanceOf(deployerL1Wallet.address)
      await (
        await nativeToken
          .connect(deployerL1Wallet)
          .transfer(userL1Wallet.address, supply.div(10))
      ).wait()
    }
  })

  it('should have deployed YBB token bridge contracts', async function () {
    const l1Router = L1GatewayRouter__factory.connect(
      _l2Network.tokenBridge.parentGatewayRouter,
      parentProvider
    )

    const defaultGateway = await l1Router.defaultGateway()
    expect(defaultGateway.toLowerCase()).to.be.eq(
      _l2Network.tokenBridge.parentErc20Gateway.toLowerCase()
    )

    // verify masterVaultFactory is set on the default gateway
    const gateway = L1YbbERC20Gateway__factory.connect(
      defaultGateway,
      parentProvider
    )
    const masterVaultFactory = await gateway.masterVaultFactory()
    expect(masterVaultFactory).to.not.be.eq(ethers.constants.AddressZero)
  })

  it('can deposit token via default gateway', async function () {
    // fund user to be able to pay retryable fees
    if (nativeToken) {
      await (
        await nativeToken
          .connect(deployerL1Wallet)
          .transfer(
            userL1Wallet.address,
            ethers.utils.parseUnits('100', await nativeToken.decimals())
          )
      ).wait()
      nativeToken.connect(userL1Wallet)
    }

    // create token to be bridged
    const token = await (
      await new TestERC20__factory(userL1Wallet).deploy()
    ).deployed()
    await (await token.mint()).wait()

    const depositAmount = 120

    // snapshot state before
    const userTokenBalanceBefore = await token.balanceOf(userL1Wallet.address)

    // approve token
    await (
      await token.approve(
        _l2Network.tokenBridge.parentErc20Gateway,
        depositAmount
      )
    ).wait()

    // calculate retryable params
    const maxSubmissionCost = nativeToken
      ? BigNumber.from(0)
      : BigNumber.from(584000000000)
    const callhook = '0x'

    const gateway = L1YbbERC20Gateway__factory.connect(
      _l2Network.tokenBridge.parentErc20Gateway,
      userL1Wallet
    )
    const outboundCalldata = await gateway.getOutboundCalldata(
      token.address,
      userL1Wallet.address,
      userL2Wallet.address,
      depositAmount,
      callhook
    )

    const l1ToL2MessageGasEstimate = new ParentToChildMessageGasEstimator(
      childProvider
    )
    const retryableParams = await l1ToL2MessageGasEstimate.estimateAll(
      {
        from: userL1Wallet.address,
        to: userL2Wallet.address,
        l2CallValue: BigNumber.from(0),
        excessFeeRefundAddress: userL1Wallet.address,
        callValueRefundAddress: userL1Wallet.address,
        data: outboundCalldata,
      },
      await getBaseFee(parentProvider),
      parentProvider
    )

    const gasLimit = retryableParams.gasLimit.mul(60)
    const maxFeePerGas = retryableParams.maxFeePerGas
    const tokenTotalFeeAmount = nativeToken
      ? await _getScaledAmount(
          nativeToken.address,
          gasLimit.mul(maxFeePerGas).mul(2),
          nativeToken.provider!
        )
      : gasLimit.mul(maxFeePerGas).mul(2)

    // approve fee amount
    if (nativeToken) {
      await (
        await nativeToken.approve(
          _l2Network.tokenBridge.parentErc20Gateway,
          tokenTotalFeeAmount
        )
      ).wait()
    }

    // bridge it
    const userEncodedData = nativeToken
      ? defaultAbiCoder.encode(
          ['uint256', 'bytes', 'uint256'],
          [maxSubmissionCost, callhook, tokenTotalFeeAmount]
        )
      : defaultAbiCoder.encode(
          ['uint256', 'bytes'],
          [maxSubmissionCost, callhook]
        )

    const router = nativeToken
      ? L1OrbitGatewayRouter__factory.connect(
          _l2Network.tokenBridge.parentGatewayRouter,
          userL1Wallet
        )
      : L1GatewayRouter__factory.connect(
          _l2Network.tokenBridge.parentGatewayRouter,
          userL1Wallet
        )

    const depositTx = await router.outboundTransferCustomRefund(
      token.address,
      userL1Wallet.address,
      userL2Wallet.address,
      depositAmount,
      gasLimit,
      maxFeePerGas,
      userEncodedData,
      { value: nativeToken ? BigNumber.from(0) : tokenTotalFeeAmount }
    )

    // wait for L2 msg to be executed
    await waitOnL2Msg(depositTx)

    ///// checks

    // user L1 token balance decreased
    const userTokenBalanceAfter = await token.balanceOf(userL1Wallet.address)
    expect(userTokenBalanceBefore.sub(userTokenBalanceAfter)).to.be.eq(
      depositAmount
    )

    // gateway token balance is 0 (tokens in vault, not gateway)
    expect(
      await token.balanceOf(_l2Network.tokenBridge.parentErc20Gateway)
    ).to.be.eq(0)

    // vault holds the underlying tokens
    const masterVaultFactoryAddr = await gateway.masterVaultFactory()
    const masterVaultFactory = MasterVaultFactory__factory.connect(
      masterVaultFactoryAddr,
      parentProvider
    )
    const vaultAddress = await masterVaultFactory.calculateVaultAddress(
      token.address
    )
    expect(await token.balanceOf(vaultAddress)).to.be.eq(depositAmount)

    // gateway holds vault shares == depositAmount (1:1 ratio)
    const vaultToken = ERC20__factory.connect(vaultAddress, parentProvider)
    expect(
      await vaultToken.balanceOf(_l2Network.tokenBridge.parentErc20Gateway)
    ).to.be.eq(depositAmount)

    // L2 token balance correct
    const l2TokenAddress = await router.calculateL2TokenAddress(token.address)
    const l2Token = ERC20__factory.connect(l2TokenAddress, childProvider)
    expect(await l2Token.balanceOf(userL2Wallet.address)).to.be.eq(
      depositAmount
    )

    // L2 token decimals == L1 token decimals
    expect(await l2Token.decimals()).to.be.eq(await token.decimals())
  })

  it('can deposit token via custom gateway', async function () {
    // fund user to be able to pay retryable fees
    if (nativeToken) {
      await (
        await nativeToken
          .connect(deployerL1Wallet)
          .transfer(
            userL1Wallet.address,
            ethers.utils.parseUnits('100', await nativeToken.decimals())
          )
      ).wait()
    }

    // create L1 custom token
    const customL1TokenFactory = nativeToken
      ? await new TestOrbitCustomTokenL1__factory(deployerL1Wallet).deploy(
          _l2Network.tokenBridge.parentCustomGateway,
          _l2Network.tokenBridge.parentGatewayRouter
        )
      : await new TestCustomTokenL1__factory(deployerL1Wallet).deploy(
          _l2Network.tokenBridge.parentCustomGateway,
          _l2Network.tokenBridge.parentGatewayRouter
        )
    const customL1Token = await customL1TokenFactory.deployed()
    await (await customL1Token.connect(userL1Wallet).mint()).wait()

    // create L2 custom token
    if (nativeToken) {
      await depositNativeToL2()
    }
    const customL2TokenFactory = await new TestArbCustomToken__factory(
      deployerL2Wallet
    ).deploy(_l2Network.tokenBridge.childCustomGateway, customL1Token.address)
    const customL2Token = await customL2TokenFactory.deployed()

    // prepare custom gateway registration params
    const router = nativeToken
      ? L1OrbitGatewayRouter__factory.connect(
          _l2Network.tokenBridge.parentGatewayRouter,
          userL1Wallet
        )
      : L1GatewayRouter__factory.connect(
          _l2Network.tokenBridge.parentGatewayRouter,
          userL1Wallet
        )
    const l1ToL2MessageGasEstimate = new ParentToChildMessageGasEstimator(
      childProvider
    )

    const routerData =
      L2GatewayRouter__factory.createInterface().encodeFunctionData(
        'setGateway',
        [[customL1Token.address], [_l2Network.tokenBridge.childCustomGateway]]
      )
    const routerRetryableParams = await l1ToL2MessageGasEstimate.estimateAll(
      {
        from: _l2Network.tokenBridge.parentGatewayRouter,
        to: _l2Network.tokenBridge.childGatewayRouter,
        l2CallValue: BigNumber.from(0),
        excessFeeRefundAddress: userL1Wallet.address,
        callValueRefundAddress: userL1Wallet.address,
        data: routerData,
      },
      await getBaseFee(parentProvider),
      parentProvider
    )

    const gatewayData =
      L2CustomGateway__factory.createInterface().encodeFunctionData(
        'registerTokenFromL1',
        [[customL1Token.address], [customL2Token.address]]
      )
    const gwRetryableParams = await l1ToL2MessageGasEstimate.estimateAll(
      {
        from: _l2Network.tokenBridge.parentCustomGateway,
        to: _l2Network.tokenBridge.childCustomGateway,
        l2CallValue: BigNumber.from(0),
        excessFeeRefundAddress: userL1Wallet.address,
        callValueRefundAddress: userL1Wallet.address,
        data: gatewayData,
      },
      await getBaseFee(parentProvider),
      parentProvider
    )

    // approve fee amount
    const valueForGateway = gwRetryableParams.deposit
    const valueForRouter = routerRetryableParams.deposit
    const registrationFee = valueForGateway.add(valueForRouter).mul(2)
    if (nativeToken) {
      await (
        await nativeToken.approve(customL1Token.address, registrationFee)
      ).wait()
    }

    // do the custom gateway registration
    const receipt = await (
      await customL1Token
        .connect(userL1Wallet)
        .registerTokenOnL2(
          customL2Token.address,
          gwRetryableParams.maxSubmissionCost,
          routerRetryableParams.maxSubmissionCost,
          gwRetryableParams.gasLimit.mul(2),
          routerRetryableParams.gasLimit.mul(2),
          BigNumber.from(100000000),
          valueForGateway,
          valueForRouter,
          userL1Wallet.address,
          {
            value: nativeToken
              ? BigNumber.from(0)
              : valueForGateway.add(valueForRouter),
          }
        )
    ).wait()

    /// wait for execution of both tickets
    const l1TxReceipt = new ParentTransactionReceipt(receipt)
    const messages = await l1TxReceipt.getParentToChildMessages(childProvider)
    const messageResults = await Promise.all(
      messages.map(message => message.waitForStatus())
    )
    if (
      messageResults[0].status !== ParentToChildMessageStatus.REDEEMED ||
      messageResults[1].status !== ParentToChildMessageStatus.REDEEMED
    ) {
      console.log(
        `Retryable ticket (ID ${messages[0].retryableCreationId}) status: ${
          ParentToChildMessageStatus[messageResults[0].status]
        }`
      )
      console.log(
        `Retryable ticket (ID ${messages[1].retryableCreationId}) status: ${
          ParentToChildMessageStatus[messageResults[1].status]
        }`
      )
      exit()
    }

    // verify router uses custom gateway
    expect(await router.getGateway(customL1Token.address)).to.be.eq(
      _l2Network.tokenBridge.parentCustomGateway
    )

    // snapshot state before deposit
    const userTokenBalanceBefore = await customL1Token.balanceOf(
      userL1Wallet.address
    )

    // approve token for deposit
    const depositAmount = 110
    await (
      await customL1Token
        .connect(userL1Wallet)
        .approve(_l2Network.tokenBridge.parentCustomGateway, depositAmount)
    ).wait()

    // calculate retryable params
    const maxSubmissionCost = nativeToken
      ? BigNumber.from(0)
      : BigNumber.from(584000000000)
    const callhook = '0x'

    const gasLimit = BigNumber.from(1000000)
    const maxFeePerGas = BigNumber.from(300000000)
    const tokenTotalFeeAmount = nativeToken
      ? await _getScaledAmount(
          nativeToken.address,
          gasLimit.mul(maxFeePerGas).mul(2),
          nativeToken.provider!
        )
      : gasLimit.mul(maxFeePerGas).mul(2)

    // approve fee amount
    if (nativeToken) {
      await (
        await nativeToken.approve(
          _l2Network.tokenBridge.parentCustomGateway,
          tokenTotalFeeAmount
        )
      ).wait()
    }

    // bridge it
    const userEncodedData = nativeToken
      ? defaultAbiCoder.encode(
          ['uint256', 'bytes', 'uint256'],
          [maxSubmissionCost, callhook, tokenTotalFeeAmount]
        )
      : defaultAbiCoder.encode(
          ['uint256', 'bytes'],
          [BigNumber.from(334400000000), callhook]
        )

    const depositTx = await router.outboundTransferCustomRefund(
      customL1Token.address,
      userL1Wallet.address,
      userL2Wallet.address,
      depositAmount,
      gasLimit,
      maxFeePerGas,
      userEncodedData,
      { value: nativeToken ? BigNumber.from(0) : tokenTotalFeeAmount }
    )

    // wait for L2 msg to be executed
    await waitOnL2Msg(depositTx)

    ///// checks

    // user L1 token balance decreased
    const userTokenBalanceAfter = await customL1Token.balanceOf(
      userL1Wallet.address
    )
    expect(userTokenBalanceBefore.sub(userTokenBalanceAfter)).to.be.eq(
      depositAmount
    )

    // gateway token balance is 0 (tokens in vault, not gateway)
    expect(
      await customL1Token.balanceOf(
        _l2Network.tokenBridge.parentCustomGateway
      )
    ).to.be.eq(0)

    // vault holds the underlying tokens
    const customGateway = L1YbbCustomGateway__factory.connect(
      _l2Network.tokenBridge.parentCustomGateway,
      parentProvider
    )
    const masterVaultFactoryAddr = await customGateway.masterVaultFactory()
    const masterVaultFactory = MasterVaultFactory__factory.connect(
      masterVaultFactoryAddr,
      parentProvider
    )
    const vaultAddress = await masterVaultFactory.calculateVaultAddress(
      customL1Token.address
    )
    expect(await customL1Token.balanceOf(vaultAddress)).to.be.eq(depositAmount)

    // gateway holds vault shares == depositAmount (1:1 ratio)
    const vaultToken = ERC20__factory.connect(vaultAddress, parentProvider)
    expect(
      await vaultToken.balanceOf(_l2Network.tokenBridge.parentCustomGateway)
    ).to.be.eq(depositAmount)

    // L2 custom token balance correct
    const l2TokenAddress = await router.calculateL2TokenAddress(
      customL1Token.address
    )
    const l2Token = ERC20__factory.connect(l2TokenAddress, childProvider)
    expect(await l2Token.balanceOf(userL2Wallet.address)).to.be.eq(
      depositAmount
    )
  })
})

async function depositNativeToL2() {
  const amountToDeposit = ethers.utils.parseUnits(
    '2.0',
    await nativeToken!.decimals()
  )
  await (
    await nativeToken!
      .connect(userL1Wallet)
      .approve(_l2Network.ethBridge.inbox, amountToDeposit)
  ).wait()

  const depositFuncSig = {
    name: 'depositERC20',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      {
        name: 'amount',
        type: 'uint256',
      },
    ],
  }
  const inbox = new ethers.Contract(
    _l2Network.ethBridge.inbox,
    [depositFuncSig],
    userL1Wallet
  )

  const depositTx = await inbox.depositERC20(amountToDeposit)

  const depositRec = await ParentTransactionReceipt.monkeyPatchEthDepositWait(
    depositTx
  ).wait()
  await depositRec.waitForChildTransactionReceipt(childProvider)
}

async function waitOnL2Msg(tx: ethers.ContractTransaction) {
  const retryableReceipt = await tx.wait()
  const l1TxReceipt = new ParentTransactionReceipt(retryableReceipt)
  const messages = await l1TxReceipt.getParentToChildMessages(childProvider)

  // 1 msg expected
  const messageResult = await messages[0].waitForStatus()
  const status = messageResult.status
  expect(status).to.be.eq(ParentToChildMessageStatus.REDEEMED)
}

const getFeeToken = async (inbox: string, parentProvider: any) => {
  const bridge = await IInbox__factory.connect(inbox, parentProvider).bridge()

  let feeToken = ethers.constants.AddressZero

  try {
    feeToken = await IERC20Bridge__factory.connect(
      bridge,
      parentProvider
    ).nativeToken()
  } catch {}

  return feeToken
}
