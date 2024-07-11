import {
  L1Network,
  L1ToL2MessageGasEstimator,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
  L2TransactionReceipt,
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
  IERC20__factory,
  IInbox__factory,
  IOwnable__factory,
  L1OrbitUSDCGateway__factory,
  L1GatewayRouter__factory,
  L1OrbitERC20Gateway__factory,
  L1OrbitGatewayRouter__factory,
  L1USDCGateway__factory,
  L2CustomGateway__factory,
  L2GatewayRouter__factory,
  L2USDCGateway__factory,
  ProxyAdmin__factory,
  TestArbCustomToken__factory,
  TestCustomTokenL1__factory,
  TestERC20,
  TestERC20__factory,
  TestOrbitCustomTokenL1__factory,
  TransparentUpgradeableProxy__factory,
  UpgradeExecutor__factory,
  IFiatToken__factory,
  IFiatTokenProxy__factory,
} from '../build/types'
import { defaultAbiCoder } from 'ethers/lib/utils'
import { BigNumber, Wallet, ethers } from 'ethers'
import { exit } from 'process'
import {
  abi as SigCheckerAbi,
  bytecode as SigCheckerBytecode,
} from '@offchainlabs/stablecoin-evm/artifacts/hardhat/contracts/util/SignatureChecker.sol/SignatureChecker.json'
import {
  abi as UsdcAbi,
  bytecode as UsdcBytecode,
} from '@offchainlabs/stablecoin-evm/artifacts/hardhat/contracts/v2/FiatTokenV2_2.sol/FiatTokenV2_2.json'
import {
  abi as UsdcProxyAbi,
  bytecode as UsdcProxyBytecode,
} from '@offchainlabs/stablecoin-evm/artifacts/hardhat/contracts/v1/FiatTokenProxy.sol/FiatTokenProxy.json'
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

let _l1Network: L1Network
let _l2Network: L2Network

let token: TestERC20
let l2Token: ERC20
let nativeToken: ERC20 | undefined

describe('orbitTokenBridge', () => {
  // configure orbit token bridge
  before(async function () {
    parentProvider = new ethers.providers.JsonRpcProvider(config.parentUrl)
    childProvider = new ethers.providers.JsonRpcProvider(config.childUrl)

    TransparentUpgradeableProxy__factory

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

    const { l1Network, l2Network } = await setupTokenBridgeInLocalEnv()

    _l1Network = l1Network
    _l2Network = l2Network

    // create user wallets and fund it
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

  it('should have deployed token bridge contracts', async function () {
    // get router as entry point
    const l1Router = L1OrbitGatewayRouter__factory.connect(
      _l2Network.tokenBridge.l1GatewayRouter,
      parentProvider
    )

    expect((await l1Router.defaultGateway()).toLowerCase()).to.be.eq(
      _l2Network.tokenBridge.l1ERC20Gateway.toLowerCase()
    )
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
    const tokenFactory = await new TestERC20__factory(userL1Wallet).deploy()
    token = await tokenFactory.deployed()
    await (await token.mint()).wait()

    // snapshot state before
    const userTokenBalanceBefore = await token.balanceOf(userL1Wallet.address)

    const gatewayTokenBalanceBefore = await token.balanceOf(
      _l2Network.tokenBridge.l1ERC20Gateway
    )
    const userNativeTokenBalanceBefore = nativeToken
      ? await nativeToken.balanceOf(userL1Wallet.address)
      : await parentProvider.getBalance(userL1Wallet.address)
    const bridgeNativeTokenBalanceBefore = nativeToken
      ? await nativeToken.balanceOf(_l2Network.ethBridge.bridge)
      : await parentProvider.getBalance(_l2Network.ethBridge.bridge)

    // approve token
    const depositAmount = 120
    await (
      await token.approve(_l2Network.tokenBridge.l1ERC20Gateway, depositAmount)
    ).wait()

    // calculate retryable params
    const maxSubmissionCost = nativeToken
      ? BigNumber.from(0)
      : BigNumber.from(584000000000)
    const callhook = '0x'

    const gateway = L1OrbitERC20Gateway__factory.connect(
      _l2Network.tokenBridge.l1ERC20Gateway,
      userL1Wallet
    )
    const outboundCalldata = await gateway.getOutboundCalldata(
      token.address,
      userL1Wallet.address,
      userL2Wallet.address,
      depositAmount,
      callhook
    )

    const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(
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
          _l2Network.tokenBridge.l1ERC20Gateway,
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
          _l2Network.tokenBridge.l1GatewayRouter,
          userL1Wallet
        )
      : L1GatewayRouter__factory.connect(
          _l2Network.tokenBridge.l1GatewayRouter,
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

    const l2TokenAddress = await router.calculateL2TokenAddress(token.address)
    l2Token = ERC20__factory.connect(l2TokenAddress, childProvider)
    expect(await l2Token.balanceOf(userL2Wallet.address)).to.be.eq(
      depositAmount
    )

    const userTokenBalanceAfter = await token.balanceOf(userL1Wallet.address)
    expect(userTokenBalanceBefore.sub(userTokenBalanceAfter)).to.be.eq(
      depositAmount
    )

    const gatewayTokenBalanceAfter = await token.balanceOf(
      _l2Network.tokenBridge.l1ERC20Gateway
    )
    expect(gatewayTokenBalanceAfter.sub(gatewayTokenBalanceBefore)).to.be.eq(
      depositAmount
    )

    const userNativeTokenBalanceAfter = nativeToken
      ? await nativeToken.balanceOf(userL1Wallet.address)
      : await parentProvider.getBalance(userL1Wallet.address)
    if (nativeToken) {
      expect(
        userNativeTokenBalanceBefore.sub(userNativeTokenBalanceAfter)
      ).to.be.eq(tokenTotalFeeAmount)
    } else {
      expect(
        userNativeTokenBalanceBefore.sub(userNativeTokenBalanceAfter)
      ).to.be.gte(tokenTotalFeeAmount.toNumber())
    }

    const bridgeNativeTokenBalanceAfter = nativeToken
      ? await nativeToken.balanceOf(_l2Network.ethBridge.bridge)
      : await parentProvider.getBalance(_l2Network.ethBridge.bridge)
    expect(
      bridgeNativeTokenBalanceAfter.sub(bridgeNativeTokenBalanceBefore)
    ).to.be.eq(tokenTotalFeeAmount)
  })

  xit('can withdraw token via default gateway', async function () {
    // fund userL2Wallet so it can pay for L2 withdraw TX
    await depositNativeToL2()

    // snapshot state before
    const userL1TokenBalanceBefore = await token.balanceOf(userL1Wallet.address)
    const userL2TokenBalanceBefore = await l2Token.balanceOf(
      userL2Wallet.address
    )
    const l1GatewayTokenBalanceBefore = await token.balanceOf(
      _l2Network.tokenBridge.l1ERC20Gateway
    )
    const l2TokenSupplyBefore = await l2Token.totalSupply()

    // start withdrawal
    const withdrawalAmount = 250
    const l2Router = L2GatewayRouter__factory.connect(
      _l2Network.tokenBridge.l2GatewayRouter,
      userL2Wallet
    )
    const withdrawTx = await l2Router[
      'outboundTransfer(address,address,uint256,bytes)'
    ](token.address, userL1Wallet.address, withdrawalAmount, '0x')
    const withdrawReceipt = await withdrawTx.wait()
    const l2Receipt = new L2TransactionReceipt(withdrawReceipt)

    // wait until dispute period passes and withdrawal is ready for execution
    await sleep(5 * 1000)

    const messages = await l2Receipt.getL2ToL1Messages(userL1Wallet)
    const l2ToL1Msg = messages[0]
    const timeToWaitMs = 1000
    await l2ToL1Msg.waitUntilReadyToExecute(childProvider, timeToWaitMs)

    // execute on L1
    await (await l2ToL1Msg.execute(childProvider)).wait()

    //// checks
    const userL1TokenBalanceAfter = await token.balanceOf(userL1Wallet.address)
    expect(userL1TokenBalanceAfter.sub(userL1TokenBalanceBefore)).to.be.eq(
      withdrawalAmount
    )

    const userL2TokenBalanceAfter = await l2Token.balanceOf(
      userL2Wallet.address
    )
    expect(userL2TokenBalanceBefore.sub(userL2TokenBalanceAfter)).to.be.eq(
      withdrawalAmount
    )

    const l1GatewayTokenBalanceAfter = await token.balanceOf(
      _l2Network.tokenBridge.l1ERC20Gateway
    )
    expect(
      l1GatewayTokenBalanceBefore.sub(l1GatewayTokenBalanceAfter)
    ).to.be.eq(withdrawalAmount)

    const l2TokenSupplyAfter = await l2Token.totalSupply()
    expect(l2TokenSupplyBefore.sub(l2TokenSupplyAfter)).to.be.eq(
      withdrawalAmount
    )
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
          _l2Network.tokenBridge.l1CustomGateway,
          _l2Network.tokenBridge.l1GatewayRouter
        )
      : await new TestCustomTokenL1__factory(deployerL1Wallet).deploy(
          _l2Network.tokenBridge.l1CustomGateway,
          _l2Network.tokenBridge.l1GatewayRouter
        )
    const customL1Token = await customL1TokenFactory.deployed()
    await (await customL1Token.connect(userL1Wallet).mint()).wait()

    // create L2 custom token
    if (nativeToken) {
      await depositNativeToL2()
    }
    const customL2TokenFactory = await new TestArbCustomToken__factory(
      deployerL2Wallet
    ).deploy(_l2Network.tokenBridge.l2CustomGateway, customL1Token.address)
    const customL2Token = await customL2TokenFactory.deployed()

    // prepare custom gateway registration params
    const router = nativeToken
      ? L1OrbitGatewayRouter__factory.connect(
          _l2Network.tokenBridge.l1GatewayRouter,
          userL1Wallet
        )
      : L1GatewayRouter__factory.connect(
          _l2Network.tokenBridge.l1GatewayRouter,
          userL1Wallet
        )
    const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(
      childProvider
    )

    const routerData =
      L2GatewayRouter__factory.createInterface().encodeFunctionData(
        'setGateway',
        [[customL1Token.address], [_l2Network.tokenBridge.l2CustomGateway]]
      )
    const routerRetryableParams = await l1ToL2MessageGasEstimate.estimateAll(
      {
        from: _l2Network.tokenBridge.l1GatewayRouter,
        to: _l2Network.tokenBridge.l2GatewayRouter,
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
        from: _l2Network.tokenBridge.l1CustomGateway,
        to: _l2Network.tokenBridge.l2CustomGateway,
        l2CallValue: BigNumber.from(0),
        excessFeeRefundAddress: userL1Wallet.address,
        callValueRefundAddress: userL1Wallet.address,
        data: gatewayData,
      },
      await getBaseFee(parentProvider),
      parentProvider
    )

    // approve fee amount
    const valueForGateway = nativeToken
      ? await _getScaledAmount(
          nativeToken.address,
          gwRetryableParams.deposit,
          nativeToken.provider!
        )
      : gwRetryableParams.deposit
    const valueForRouter = nativeToken
      ? await _getScaledAmount(
          nativeToken.address,
          routerRetryableParams.deposit,
          nativeToken.provider!
        )
      : routerRetryableParams.deposit
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
    const l1TxReceipt = new L1TransactionReceipt(receipt)
    const messages = await l1TxReceipt.getL1ToL2Messages(childProvider)
    const messageResults = await Promise.all(
      messages.map(message => message.waitForStatus())
    )
    if (
      messageResults[0].status !== L1ToL2MessageStatus.REDEEMED ||
      messageResults[1].status !== L1ToL2MessageStatus.REDEEMED
    ) {
      console.log(
        `Retryable ticket (ID ${messages[0].retryableCreationId}) status: ${
          L1ToL2MessageStatus[messageResults[0].status]
        }`
      )
      console.log(
        `Retryable ticket (ID ${messages[1].retryableCreationId}) status: ${
          L1ToL2MessageStatus[messageResults[1].status]
        }`
      )
      exit()
    }

    // snapshot state before
    const userTokenBalanceBefore = await customL1Token.balanceOf(
      userL1Wallet.address
    )
    const gatewayTokenBalanceBefore = await customL1Token.balanceOf(
      _l2Network.tokenBridge.l1CustomGateway
    )
    const userNativeTokenBalanceBefore = nativeToken
      ? await nativeToken.balanceOf(userL1Wallet.address)
      : await parentProvider.getBalance(userL1Wallet.address)
    const bridgeNativeTokenBalanceBefore = nativeToken
      ? await nativeToken.balanceOf(_l2Network.ethBridge.bridge)
      : await parentProvider.getBalance(_l2Network.ethBridge.bridge)

    // approve token
    const depositAmount = 110
    await (
      await customL1Token
        .connect(userL1Wallet)
        .approve(_l2Network.tokenBridge.l1CustomGateway, depositAmount)
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
          _l2Network.tokenBridge.l1CustomGateway,
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
    expect(await router.getGateway(customL1Token.address)).to.be.eq(
      _l2Network.tokenBridge.l1CustomGateway
    )

    const l2TokenAddress = await router.calculateL2TokenAddress(
      customL1Token.address
    )

    l2Token = ERC20__factory.connect(l2TokenAddress, childProvider)
    expect(await l2Token.balanceOf(userL2Wallet.address)).to.be.eq(
      depositAmount
    )

    const userTokenBalanceAfter = await customL1Token.balanceOf(
      userL1Wallet.address
    )
    expect(userTokenBalanceBefore.sub(userTokenBalanceAfter)).to.be.eq(
      depositAmount
    )

    const gatewayTokenBalanceAfter = await customL1Token.balanceOf(
      _l2Network.tokenBridge.l1CustomGateway
    )
    expect(gatewayTokenBalanceAfter.sub(gatewayTokenBalanceBefore)).to.be.eq(
      depositAmount
    )

    const userNativeTokenBalanceAfter = nativeToken
      ? await nativeToken.balanceOf(userL1Wallet.address)
      : await parentProvider.getBalance(userL1Wallet.address)
    if (nativeToken) {
      expect(
        userNativeTokenBalanceBefore.sub(userNativeTokenBalanceAfter)
      ).to.be.eq(tokenTotalFeeAmount)
    } else {
      expect(
        userNativeTokenBalanceBefore.sub(userNativeTokenBalanceAfter)
      ).to.be.gte(tokenTotalFeeAmount.toNumber())
    }
    const bridgeNativeTokenBalanceAfter = nativeToken
      ? await nativeToken.balanceOf(_l2Network.ethBridge.bridge)
      : await parentProvider.getBalance(_l2Network.ethBridge.bridge)
    expect(
      bridgeNativeTokenBalanceAfter.sub(bridgeNativeTokenBalanceBefore)
    ).to.be.eq(tokenTotalFeeAmount)
  })

  it('can upgrade from bridged USDC to native USDC when eth is native token', async function () {
    /// test applicable only for eth based chains
    if (nativeToken) {
      return
    }

    /// create new L1 usdc gateway behind proxy
    const proxyAdminFac = await new ProxyAdmin__factory(
      deployerL1Wallet
    ).deploy()
    const proxyAdmin = await proxyAdminFac.deployed()
    const l1USDCCustomGatewayFactory = await new L1USDCGateway__factory(
      deployerL1Wallet
    ).deploy()
    const l1USDCCustomGatewayLogic = await l1USDCCustomGatewayFactory.deployed()
    const tupFactory = await new TransparentUpgradeableProxy__factory(
      deployerL1Wallet
    ).deploy(l1USDCCustomGatewayLogic.address, proxyAdmin.address, '0x')
    const tup = await tupFactory.deployed()
    const l1USDCCustomGateway = L1USDCGateway__factory.connect(
      tup.address,
      deployerL1Wallet
    )
    console.log('L1USDCGateway address: ', l1USDCCustomGateway.address)

    /// create new L2 usdc gateway behind proxy
    const proxyAdminL2Fac = await new ProxyAdmin__factory(
      deployerL2Wallet
    ).deploy()
    const proxyAdminL2 = await proxyAdminL2Fac.deployed()
    const l2USDCCustomGatewayFactory = await new L2USDCGateway__factory(
      deployerL2Wallet
    ).deploy()
    const l2USDCCustomGatewayLogic = await l2USDCCustomGatewayFactory.deployed()
    const tupL2Factory = await new TransparentUpgradeableProxy__factory(
      deployerL2Wallet
    ).deploy(l2USDCCustomGatewayLogic.address, proxyAdminL2.address, '0x')
    const tupL2 = await tupL2Factory.deployed()
    const l2USDCCustomGateway = L2USDCGateway__factory.connect(
      tupL2.address,
      deployerL2Wallet
    )
    console.log('L2USDCGateway address: ', l2USDCCustomGateway.address)

    /// create l1 usdc behind proxy
    const l1UsdcLogic = await _deployUsdcToken(deployerL1Wallet)
    const tupL1UsdcFactory = await new TransparentUpgradeableProxy__factory(
      deployerL1Wallet
    ).deploy(l1UsdcLogic.address, proxyAdmin.address, '0x')
    const tupL1Usdc = await tupL1UsdcFactory.deployed()
    const l1UsdcInit = IFiatToken__factory.connect(
      tupL1Usdc.address,
      deployerL1Wallet
    )
    const masterMinterL1 = deployerL1Wallet
    await (
      await l1UsdcInit.initialize(
        'USDC token',
        'USDC.e',
        'USD',
        6,
        masterMinterL1.address,
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
        deployerL2Wallet.address
      )
    ).wait()
    await (await l1UsdcInit.initializeV2('USDC')).wait()
    await (
      await l1UsdcInit.initializeV2_1(ethers.Wallet.createRandom().address)
    ).wait()
    await (await l1UsdcInit.initializeV2_2([], 'USDC')).wait()
    const l1Usdc = IERC20__factory.connect(l1UsdcInit.address, deployerL1Wallet)
    console.log('L1 USDC address: ', l1Usdc.address)

    /// create l2 usdc behind proxy
    const l2UsdcLogic = await _deployUsdcToken(deployerL2Wallet)
    const l2UsdcProxyAddress = await _deployUsdcProxy(
      deployerL2Wallet,
      l2UsdcLogic.address,
      proxyAdminL2.address
    )

    const l2UsdcFiatToken = IFiatToken__factory.connect(
      l2UsdcProxyAddress,
      deployerL2Wallet
    )
    const masterMinterL2 = deployerL2Wallet
    await (
      await l2UsdcFiatToken.initialize(
        'USDC token',
        'USDC.e',
        'USD',
        6,
        masterMinterL2.address,
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
        deployerL2Wallet.address
      )
    ).wait()
    await (await l2UsdcFiatToken.initializeV2('USDC')).wait()
    await (
      await l2UsdcFiatToken.initializeV2_1(ethers.Wallet.createRandom().address)
    ).wait()
    await (await l2UsdcFiatToken.initializeV2_2([], 'USDC.e')).wait()
    const l2Usdc = IERC20__factory.connect(
      l2UsdcFiatToken.address,
      deployerL2Wallet
    )
    console.log('L2 USDC address: ', l2Usdc.address)

    /// initialize gateways
    await (
      await l1USDCCustomGateway.initialize(
        l2USDCCustomGateway.address,
        _l2Network.tokenBridge.l1GatewayRouter,
        _l2Network.ethBridge.inbox,
        l1Usdc.address,
        l2Usdc.address,
        deployerL1Wallet.address
      )
    ).wait()
    console.log('L1 USDC custom gateway initialized')

    await (
      await l2USDCCustomGateway.initialize(
        l1USDCCustomGateway.address,
        _l2Network.tokenBridge.l2GatewayRouter,
        l1Usdc.address,
        l2Usdc.address,
        deployerL2Wallet.address
      )
    ).wait()
    console.log('L2 USDC custom gateway initialized')

    /// register USDC custom gateway
    const router = L1GatewayRouter__factory.connect(
      _l2Network.tokenBridge.l1GatewayRouter,
      deployerL1Wallet
    )
    const l2Router = L2GatewayRouter__factory.connect(
      _l2Network.tokenBridge.l2GatewayRouter,
      deployerL2Wallet
    )
    const maxGas = BigNumber.from(500000)
    const gasPriceBid = BigNumber.from(200000000)
    let maxSubmissionCost = BigNumber.from(257600000000)
    const registrationCalldata = router.interface.encodeFunctionData(
      'setGateways',
      [
        [l1Usdc.address],
        [l1USDCCustomGateway.address],
        maxGas,
        gasPriceBid,
        maxSubmissionCost,
      ]
    )
    const rollupOwner = new Wallet(LOCALHOST_L3_OWNER_KEY, parentProvider)
    const upExec = UpgradeExecutor__factory.connect(
      await IOwnable__factory.connect(
        _l2Network.ethBridge.rollup,
        deployerL1Wallet
      ).owner(),
      rollupOwner
    )
    const gwRegistrationTx = await upExec.executeCall(
      router.address,
      registrationCalldata,
      {
        value: maxGas.mul(gasPriceBid).add(maxSubmissionCost),
      }
    )
    await waitOnL2Msg(gwRegistrationTx)
    console.log('USDC custom gateway registered')

    /// check gateway registration
    expect(await router.getGateway(l1Usdc.address)).to.be.eq(
      l1USDCCustomGateway.address
    )
    expect(await l1USDCCustomGateway.depositsPaused()).to.be.eq(false)
    expect(await l2Router.getGateway(l1Usdc.address)).to.be.eq(
      l2USDCCustomGateway.address
    )
    expect(await l2USDCCustomGateway.withdrawalsPaused()).to.be.eq(false)

    /// add minter role with max allowance to L2 gateway
    await (
      await l2UsdcFiatToken
        .connect(masterMinterL2)
        .configureMinter(
          l2USDCCustomGateway.address,
          ethers.constants.MaxUint256
        )
    ).wait()
    expect(
      await l2UsdcFiatToken.isMinter(l2USDCCustomGateway.address)
    ).to.be.eq(true)
    console.log('Minter role with max allowance granted to L2 USDC gateway')

    /// mint some USDC to user
    await (
      await l1UsdcInit
        .connect(masterMinterL1)
        .configureMinter(
          masterMinterL1.address,
          ethers.utils.parseEther('1000')
        )
    ).wait()
    await (
      await l1UsdcInit
        .connect(masterMinterL1)
        .mint(userL1Wallet.address, ethers.utils.parseEther('10'))
    ).wait()
    console.log('Minted USDC to user')

    /// do a deposit
    const depositAmount = ethers.utils.parseEther('2')
    await (
      await l1Usdc
        .connect(userL1Wallet)
        .approve(l1USDCCustomGateway.address, depositAmount)
    ).wait()
    maxSubmissionCost = BigNumber.from(334400000000)
    const depositTx = await router
      .connect(userL1Wallet)
      .outboundTransferCustomRefund(
        l1Usdc.address,
        userL2Wallet.address,
        userL2Wallet.address,
        depositAmount,
        maxGas,
        gasPriceBid,
        defaultAbiCoder.encode(['uint256', 'bytes'], [maxSubmissionCost, '0x']),
        { value: maxGas.mul(gasPriceBid).add(maxSubmissionCost) }
      )
    await waitOnL2Msg(depositTx)
    expect(await l2Usdc.balanceOf(userL2Wallet.address)).to.be.eq(depositAmount)
    expect(await l1Usdc.balanceOf(l1USDCCustomGateway.address)).to.be.eq(
      depositAmount
    )
    expect(await l2Usdc.totalSupply()).to.be.eq(depositAmount)
    console.log('Deposited USDC')

    /// pause deposits
    await (await l1USDCCustomGateway.pauseDeposits()).wait()
    expect(await l1USDCCustomGateway.depositsPaused()).to.be.eq(true)
    console.log('Deposits paused')

    /// pause withdrawals
    await (await l2USDCCustomGateway.pauseWithdrawals()).wait()
    expect(await l2USDCCustomGateway.withdrawalsPaused()).to.be.eq(true)
    console.log('Withdrawals paused')

    /// chain owner/circle checks that all pending deposits (all retryables depositing usdc) are executed

    // set burn amount
    const burnAmount = await l2Usdc.totalSupply()
    await (await l1USDCCustomGateway.setBurnAmount(burnAmount)).wait()
    expect(await l1USDCCustomGateway.burnAmount()).to.be.eq(burnAmount)
    console.log('Burn amount set')

    /// make circle the burner
    const circleWalletL1 = ethers.Wallet.createRandom().connect(parentProvider)
    await (
      await deployerL1Wallet.sendTransaction({
        to: circleWalletL1.address,
        value: ethers.utils.parseEther('1'),
      })
    ).wait()
    await (await l1USDCCustomGateway.setBurner(circleWalletL1.address)).wait()
    expect(await l1USDCCustomGateway.burner()).to.be.eq(circleWalletL1.address)

    /// add minter rights to usdc gateway so it can burn USDC
    await (
      await l1UsdcInit.configureMinter(l1USDCCustomGateway.address, 0)
    ).wait()
    console.log('Minter role with 0 allowance added to L1 USDC gateway')

    /// remove minter role from the L2 gateway
    await (
      await l2UsdcFiatToken
        .connect(masterMinterL2)
        .removeMinter(l2USDCCustomGateway.address)
    ).wait()
    expect(
      await l2UsdcFiatToken.isMinter(l2USDCCustomGateway.address)
    ).to.be.eq(false)
    console.log('Minter role removed from L2 USDC gateway')

    /// set USDC role transferrer
    const circleWalletL2 = ethers.Wallet.createRandom().connect(childProvider)
    await (
      await deployerL2Wallet.sendTransaction({
        to: circleWalletL2.address,
        value: ethers.utils.parseEther('1'),
      })
    ).wait()
    await (
      await l2USDCCustomGateway.setUsdcOwnershipTransferrer(
        circleWalletL2.address
      )
    ).wait()
    expect(await l2USDCCustomGateway.usdcOwnershipTransferrer()).to.be.eq(
      circleWalletL2.address
    )
    console.log('USDC ownership transferrer set to', circleWalletL2.address)

    /// transfer child chain USDC ownership to gateway
    await (
      await l2UsdcFiatToken.transferOwnership(l2USDCCustomGateway.address)
    ).wait()
    expect(await l2UsdcFiatToken.owner()).to.be.eq(l2USDCCustomGateway.address)
    console.log('USDC ownership transferred to gateway')

    /// transfer proxyAdmin to gateway
    const fiatTokenProxy = IFiatTokenProxy__factory.connect(
      l2UsdcFiatToken.address,
      deployerL2Wallet
    )
    await (
      await proxyAdminL2.changeProxyAdmin(
        fiatTokenProxy.address,
        l2USDCCustomGateway.address
      )
    ).wait()
    expect(await fiatTokenProxy.admin()).to.be.eq(l2USDCCustomGateway.address)
    console.log('Proxy admin transferred to gateway')

    /// transfer child chain USDC ownership to circle
    await (
      await l2USDCCustomGateway
        .connect(circleWalletL2)
        .transferUSDCRoles(circleWalletL2.address)
    ).wait()

    expect(await l2UsdcFiatToken.owner()).to.be.eq(circleWalletL2.address)
    expect(await fiatTokenProxy.admin()).to.be.eq(circleWalletL2.address)
    console.log('USDC ownership transferred to circle')

    /// circle burns USDC on L1
    await (
      await l1USDCCustomGateway.connect(circleWalletL1).burnLockedUSDC()
    ).wait()
    expect(await l1Usdc.balanceOf(l1USDCCustomGateway.address)).to.be.eq(0)
    expect(await l2Usdc.balanceOf(userL2Wallet.address)).to.be.eq(depositAmount)
    console.log('USDC burned')
  })

  it('can upgrade from bridged USDC to native USDC when fee token is used', async function () {
    /// test applicable only for fee token based chains
    if (!nativeToken) {
      return
    }

    /// create new L1 usdc gateway behind proxy
    const proxyAdminFac = await new ProxyAdmin__factory(
      deployerL1Wallet
    ).deploy()
    const proxyAdmin = await proxyAdminFac.deployed()
    const l1USDCCustomGatewayFactory = await new L1OrbitUSDCGateway__factory(
      deployerL1Wallet
    ).deploy()
    const l1USDCCustomGatewayLogic = await l1USDCCustomGatewayFactory.deployed()
    const tupFactory = await new TransparentUpgradeableProxy__factory(
      deployerL1Wallet
    ).deploy(l1USDCCustomGatewayLogic.address, proxyAdmin.address, '0x')
    const tup = await tupFactory.deployed()
    const l1USDCCustomGateway = L1USDCGateway__factory.connect(
      tup.address,
      deployerL1Wallet
    )
    console.log('L1USDCGateway address: ', l1USDCCustomGateway.address)

    /// create new L2 usdc gateway behind proxy
    const proxyAdminL2Fac = await new ProxyAdmin__factory(
      deployerL2Wallet
    ).deploy()
    const proxyAdminL2 = await proxyAdminL2Fac.deployed()
    const l2USDCCustomGatewayFactory = await new L2USDCGateway__factory(
      deployerL2Wallet
    ).deploy()
    const l2USDCCustomGatewayLogic = await l2USDCCustomGatewayFactory.deployed()
    const tupL2Factory = await new TransparentUpgradeableProxy__factory(
      deployerL2Wallet
    ).deploy(l2USDCCustomGatewayLogic.address, proxyAdminL2.address, '0x')
    const tupL2 = await tupL2Factory.deployed()
    const l2USDCCustomGateway = L2USDCGateway__factory.connect(
      tupL2.address,
      deployerL2Wallet
    )
    console.log('L2USDCGateway address: ', l2USDCCustomGateway.address)

    /// create l1 usdc behind proxy
    const l1UsdcLogic = await _deployUsdcToken(deployerL1Wallet)
    const tupL1UsdcFactory = await new TransparentUpgradeableProxy__factory(
      deployerL1Wallet
    ).deploy(l1UsdcLogic.address, proxyAdmin.address, '0x')
    const tupL1Usdc = await tupL1UsdcFactory.deployed()
    const l1UsdcInit = IFiatToken__factory.connect(
      tupL1Usdc.address,
      deployerL1Wallet
    )
    const masterMinterL1 = deployerL1Wallet
    await (
      await l1UsdcInit.initialize(
        'USDC token',
        'USDC.e',
        'USD',
        6,
        masterMinterL1.address,
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
        deployerL2Wallet.address
      )
    ).wait()
    await (await l1UsdcInit.initializeV2('USDC')).wait()
    await (
      await l1UsdcInit.initializeV2_1(ethers.Wallet.createRandom().address)
    ).wait()
    await (await l1UsdcInit.initializeV2_2([], 'USDC')).wait()
    const l1Usdc = IERC20__factory.connect(l1UsdcInit.address, deployerL1Wallet)
    console.log('L1 USDC address: ', l1Usdc.address)

    /// create l2 usdc behind proxy
    const l2UsdcLogic = await _deployUsdcToken(deployerL2Wallet)
    const l2UsdcProxyAddress = await _deployUsdcProxy(
      deployerL2Wallet,
      l2UsdcLogic.address,
      proxyAdminL2.address
    )

    const l2UsdcFiatToken = IFiatToken__factory.connect(
      l2UsdcProxyAddress,
      deployerL2Wallet
    )
    const masterMinterL2 = deployerL2Wallet
    await (
      await l2UsdcFiatToken.initialize(
        'USDC token',
        'USDC.e',
        'USD',
        6,
        masterMinterL2.address,
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
        deployerL2Wallet.address
      )
    ).wait()
    await (await l2UsdcFiatToken.initializeV2('USDC')).wait()
    await (
      await l2UsdcFiatToken.initializeV2_1(ethers.Wallet.createRandom().address)
    ).wait()
    await (await l2UsdcFiatToken.initializeV2_2([], 'USDC.e')).wait()
    const l2Usdc = IERC20__factory.connect(
      l2UsdcFiatToken.address,
      deployerL2Wallet
    )
    console.log('L2 USDC address: ', l2Usdc.address)

    /// initialize gateways
    await (
      await l1USDCCustomGateway.initialize(
        l2USDCCustomGateway.address,
        _l2Network.tokenBridge.l1GatewayRouter,
        _l2Network.ethBridge.inbox,
        l1Usdc.address,
        l2Usdc.address,
        deployerL1Wallet.address
      )
    ).wait()
    console.log('L1 USDC custom gateway initialized')

    await (
      await l2USDCCustomGateway.initialize(
        l1USDCCustomGateway.address,
        _l2Network.tokenBridge.l2GatewayRouter,
        l1Usdc.address,
        l2Usdc.address,
        deployerL2Wallet.address
      )
    ).wait()
    console.log('L2 USDC custom gateway initialized')

    /// register USDC custom gateway
    const router = L1OrbitGatewayRouter__factory.connect(
      _l2Network.tokenBridge.l1GatewayRouter,
      deployerL1Wallet
    )
    const l2Router = L2GatewayRouter__factory.connect(
      _l2Network.tokenBridge.l2GatewayRouter,
      deployerL2Wallet
    )
    const maxGas = BigNumber.from(500000)
    const gasPriceBid = BigNumber.from(200000000)
    const totalFeeTokenAmount = await _getScaledAmount(
      nativeToken!.address,
      maxGas.mul(gasPriceBid),
      nativeToken!.provider
    )
    const maxSubmissionCost = BigNumber.from(0)

    // prefund inbox to pay for registration
    await (
      await nativeToken
        .connect(deployerL1Wallet)
        .transfer(_l2Network.ethBridge.inbox, totalFeeTokenAmount)
    ).wait()

    const registrationCalldata = (router.interface as any).encodeFunctionData(
      'setGateways(address[],address[],uint256,uint256,uint256,uint256)',
      [
        [l1Usdc.address],
        [l1USDCCustomGateway.address],
        maxGas,
        gasPriceBid,
        maxSubmissionCost,
        totalFeeTokenAmount,
      ]
    )
    const rollupOwner = new Wallet(LOCALHOST_L3_OWNER_KEY, parentProvider)
    // approve fee amount
    console.log('Approving fee amount')
    await (
      await nativeToken
        .connect(rollupOwner)
        .approve(l1USDCCustomGateway.address, totalFeeTokenAmount)
    ).wait()

    const upExec = UpgradeExecutor__factory.connect(
      await IOwnable__factory.connect(
        _l2Network.ethBridge.rollup,
        deployerL1Wallet
      ).owner(),
      rollupOwner
    )
    const gwRegistrationTx = await upExec.executeCall(
      router.address,
      registrationCalldata
    )
    await waitOnL2Msg(gwRegistrationTx)
    console.log('USDC custom gateway registered')

    /// check gateway registration
    expect(await router.getGateway(l1Usdc.address)).to.be.eq(
      l1USDCCustomGateway.address
    )
    expect(await l1USDCCustomGateway.depositsPaused()).to.be.eq(false)
    expect(await l2Router.getGateway(l1Usdc.address)).to.be.eq(
      l2USDCCustomGateway.address
    )
    expect(await l2USDCCustomGateway.withdrawalsPaused()).to.be.eq(false)

    /// add minter role with max allowance to L2 gateway
    await (
      await l2UsdcFiatToken
        .connect(masterMinterL2)
        .configureMinter(
          l2USDCCustomGateway.address,
          ethers.constants.MaxUint256
        )
    ).wait()
    expect(
      await l2UsdcFiatToken.isMinter(l2USDCCustomGateway.address)
    ).to.be.eq(true)
    console.log('Minter role with max allowance granted to L2 USDC gateway')

    /// mint some USDC to user
    await (
      await l1UsdcInit
        .connect(masterMinterL1)
        .configureMinter(
          masterMinterL1.address,
          ethers.utils.parseEther('1000')
        )
    ).wait()
    await (
      await l1UsdcInit
        .connect(masterMinterL1)
        .mint(userL1Wallet.address, ethers.utils.parseEther('10'))
    ).wait()
    console.log('Minted USDC to user')

    /// do a deposit
    const depositAmount = ethers.utils.parseEther('2')
    await (
      await l1Usdc
        .connect(userL1Wallet)
        .approve(l1USDCCustomGateway.address, depositAmount)
    ).wait()

    // approve fee amount
    await (
      await nativeToken
        .connect(userL1Wallet)
        .approve(l1USDCCustomGateway.address, totalFeeTokenAmount)
    ).wait()

    const depositTx = await router
      .connect(userL1Wallet)
      .outboundTransferCustomRefund(
        l1Usdc.address,
        userL2Wallet.address,
        userL2Wallet.address,
        depositAmount,
        maxGas,
        gasPriceBid,
        defaultAbiCoder.encode(
          ['uint256', 'bytes', 'uint256'],
          [maxSubmissionCost, '0x', totalFeeTokenAmount]
        )
      )
    await waitOnL2Msg(depositTx)
    expect(await l2Usdc.balanceOf(userL2Wallet.address)).to.be.eq(depositAmount)
    expect(await l1Usdc.balanceOf(l1USDCCustomGateway.address)).to.be.eq(
      depositAmount
    )
    expect(await l2Usdc.totalSupply()).to.be.eq(depositAmount)
    console.log('Deposited USDC')

    /// pause deposits
    await (await l1USDCCustomGateway.pauseDeposits()).wait()
    expect(await l1USDCCustomGateway.depositsPaused()).to.be.eq(true)
    console.log('Deposits paused')

    /// pause withdrawals
    await (await l2USDCCustomGateway.pauseWithdrawals()).wait()
    expect(await l2USDCCustomGateway.withdrawalsPaused()).to.be.eq(true)
    console.log('Withdrawals paused')

    /// chain owner/circle checks that all pending deposits (all retryables depositing usdc) are executed

    // set burn amount
    const burnAmount = await l2Usdc.totalSupply()
    await (await l1USDCCustomGateway.setBurnAmount(burnAmount)).wait()
    expect(await l1USDCCustomGateway.burnAmount()).to.be.eq(burnAmount)
    console.log('Burn amount set')

    /// make circle the burner
    const circleWalletL1 = ethers.Wallet.createRandom().connect(parentProvider)
    await (
      await deployerL1Wallet.sendTransaction({
        to: circleWalletL1.address,
        value: ethers.utils.parseEther('1'),
      })
    ).wait()
    await (await l1USDCCustomGateway.setBurner(circleWalletL1.address)).wait()
    expect(await l1USDCCustomGateway.burner()).to.be.eq(circleWalletL1.address)
    console.log('Circle set as burner')

    /// add minter rights to usdc gateway so it can burn USDC
    await (
      await l1UsdcInit.configureMinter(l1USDCCustomGateway.address, 0)
    ).wait()
    console.log('Minter role with 0 allowance added to L1 USDC gateway')

    /// remove minter role from the L2 gateway
    await (
      await l2UsdcFiatToken
        .connect(masterMinterL2)
        .removeMinter(l2USDCCustomGateway.address)
    ).wait()
    expect(
      await l2UsdcFiatToken.isMinter(l2USDCCustomGateway.address)
    ).to.be.eq(false)
    console.log('Minter role removed from L2 USDC gateway')

    /// set USDC role transferrer
    const circleWalletL2 = ethers.Wallet.createRandom().connect(childProvider)
    await (
      await deployerL2Wallet.sendTransaction({
        to: circleWalletL2.address,
        value: ethers.utils.parseEther('1'),
      })
    ).wait()
    await (
      await l2USDCCustomGateway.setUsdcOwnershipTransferrer(
        circleWalletL2.address
      )
    ).wait()
    expect(await l2USDCCustomGateway.usdcOwnershipTransferrer()).to.be.eq(
      circleWalletL2.address
    )
    console.log('USDC ownership transferrer set to', circleWalletL2.address)

    /// transfer child chain USDC ownership to gateway
    await (
      await l2UsdcFiatToken.transferOwnership(l2USDCCustomGateway.address)
    ).wait()
    expect(await l2UsdcFiatToken.owner()).to.be.eq(l2USDCCustomGateway.address)
    console.log('USDC ownership transferred to gateway')

    /// transfer proxyAdmin to gateway
    const fiatTokenProxy = IFiatTokenProxy__factory.connect(
      l2UsdcFiatToken.address,
      deployerL2Wallet
    )
    await (
      await proxyAdminL2.changeProxyAdmin(
        fiatTokenProxy.address,
        l2USDCCustomGateway.address
      )
    ).wait()
    expect(await fiatTokenProxy.admin()).to.be.eq(l2USDCCustomGateway.address)
    console.log('Proxy admin transferred to gateway')

    /// transfer child chain USDC ownership to circle
    await (
      await l2USDCCustomGateway
        .connect(circleWalletL2)
        .transferUSDCRoles(circleWalletL2.address)
    ).wait()

    expect(await l2UsdcFiatToken.owner()).to.be.eq(circleWalletL2.address)
    expect(await fiatTokenProxy.admin()).to.be.eq(circleWalletL2.address)
    console.log('USDC ownership transferred to circle')

    /// circle burns USDC on L1
    await (
      await l1USDCCustomGateway.connect(circleWalletL1).burnLockedUSDC()
    ).wait()
    expect(await l1Usdc.balanceOf(l1USDCCustomGateway.address)).to.be.eq(0)
    expect(await l2Usdc.balanceOf(userL2Wallet.address)).to.be.eq(depositAmount)
    console.log('USDC burned')
  })
})

/**
 * helper function to fund user wallet on L2
 */
async function depositNativeToL2() {
  /// deposit tokens
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

  // wait for deposit to be processed
  const depositRec = await L1TransactionReceipt.monkeyPatchEthDepositWait(
    depositTx
  ).wait()
  await depositRec.waitForL2(childProvider)
}

async function waitOnL2Msg(tx: ethers.ContractTransaction) {
  const retryableReceipt = await tx.wait()
  const l1TxReceipt = new L1TransactionReceipt(retryableReceipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(childProvider)

  // 1 msg expected
  const messageResult = await messages[0].waitForStatus()
  const status = messageResult.status
  expect(status).to.be.eq(L1ToL2MessageStatus.REDEEMED)
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

function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function _deployUsdcToken(deployer: Wallet) {
  /// deploy library
  const sigCheckerFac = new ethers.ContractFactory(
    SigCheckerAbi,
    SigCheckerBytecode,
    deployer
  )
  const sigCheckerLib = await sigCheckerFac.deploy()

  // prepare bridged usdc bytecode
  const bytecodeWithPlaceholder: string = UsdcBytecode
  const placeholder = '__$715109b5d747ea58b675c6ea3f0dba8c60$__'

  const libAddressStripped = sigCheckerLib.address.replace(/^0x/, '')
  const bridgedUsdcLogicBytecode = bytecodeWithPlaceholder
    .split(placeholder)
    .join(libAddressStripped)

  // deploy bridged usdc logic
  const bridgedUsdcLogicFactory = new ethers.ContractFactory(
    UsdcAbi,
    bridgedUsdcLogicBytecode,
    deployer
  )
  const bridgedUsdcLogic = await bridgedUsdcLogicFactory.deploy()

  return bridgedUsdcLogic
}

async function _deployUsdcProxy(
  deployer: Wallet,
  bridgedUsdcLogic: string,
  proxyAdmin: string
) {
  const usdcProxyFactory = new ethers.ContractFactory(
    UsdcProxyAbi,
    UsdcProxyBytecode,
    deployer
  )
  const usdcProxy = await usdcProxyFactory.deploy(bridgedUsdcLogic)

  await (
    await IFiatTokenProxy__factory.connect(
      usdcProxy.address,
      deployer
    ).changeAdmin(proxyAdmin)
  ).wait()

  return usdcProxy.address
}
