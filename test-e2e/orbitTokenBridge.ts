import {
  L1Network,
  L1ToL2MessageGasEstimator,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
} from '@arbitrum/sdk'
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'
import { JsonRpcProvider } from '@ethersproject/providers'
import { expect } from 'chai'
import { ethers, Wallet } from '@arbitrum/sdk/node_modules/ethers'
import { setupOrbitTokenBridge } from '../scripts/local-deployment/testSetup'
import {
  ERC20__factory,
  L1OrbitERC20Gateway__factory,
  L1OrbitGatewayRouter__factory,
  TestERC20__factory,
} from '../build/types'
import { defaultAbiCoder } from 'ethers/lib/utils'
import { BigNumber } from 'ethers'

const config = {
  arbUrl: 'http://localhost:8547',
  ethUrl: 'http://localhost:8545',
}

let l1Provider: JsonRpcProvider
let l2Provider: JsonRpcProvider

let deployerL1Wallet: Wallet
let deployerL2Wallet: Wallet

let userL1Wallet: Wallet
let userL2Wallet: Wallet

let _l1Network: L1Network
let _l2Network: L2Network & { nativeToken: string }

describe('orbitTokenBridge', () => {
  // configure orbit token bridge
  before(async function () {
    l1Provider = new ethers.providers.JsonRpcProvider(config.ethUrl)
    l2Provider = new ethers.providers.JsonRpcProvider(config.arbUrl)

    const deployerKey = ethers.utils.sha256(
      ethers.utils.toUtf8Bytes('user_l1user')
    )
    deployerL1Wallet = new ethers.Wallet(deployerKey, l1Provider)
    deployerL2Wallet = new ethers.Wallet(deployerKey, l2Provider)

    console.log('setupOrbitTokenBridge')
    const { l1Network, l2Network } = await setupOrbitTokenBridge(
      deployerL1Wallet,
      deployerL2Wallet,
      config.ethUrl,
      config.arbUrl
    )

    _l1Network = l1Network
    _l2Network = l2Network

    // create user wallets and fund it
    const userKey = ethers.utils.sha256(ethers.utils.toUtf8Bytes('user_wallet'))
    userL1Wallet = new ethers.Wallet(userKey, l1Provider)
    userL2Wallet = new ethers.Wallet(userKey, l2Provider)
    console.log('fund userL1Wallet')
    await (
      await deployerL1Wallet.sendTransaction({
        to: userL1Wallet.address,
        value: ethers.utils.parseEther('1.0'),
      })
    ).wait()
  })

  it('should have deployed token bridge contracts', async function () {
    // get router as entry point
    const l1Router = L1OrbitGatewayRouter__factory.connect(
      _l2Network.tokenBridge.l1GatewayRouter,
      l1Provider
    )

    expect((await l1Router.defaultGateway()).toLowerCase()).to.be.eq(
      _l2Network.tokenBridge.l1ERC20Gateway.toLowerCase()
    )
    // expect((await l1Router.counterpartGateway()).toLowerCase()).to.be.eq(
    //   _l2Network.tokenBridge.l2ERC20Gateway.toLowerCase()
    // )
  })

  it('can deposit token via default gateway', async function () {
    // fund user to be able to pay retryable fees
    const nativeToken = ERC20__factory.connect(
      _l2Network.nativeToken,
      userL1Wallet
    )
    await (
      await nativeToken
        .connect(deployerL1Wallet)
        .transfer(userL1Wallet.address, ethers.utils.parseEther('1000'))
    ).wait()

    // create token to be bridged
    const tokenFactory = await new TestERC20__factory(userL1Wallet).deploy()
    const token = await tokenFactory.deployed()
    await (await token.mint()).wait()

    // snapshot state before

    const userTokenBalanceBefore = await token.balanceOf(userL1Wallet.address)
    const gatewayTokenBalanceBefore = await token.balanceOf(
      _l2Network.tokenBridge.l1ERC20Gateway
    )
    const userNativeTokenBalanceBefore = await nativeToken.balanceOf(
      userL1Wallet.address
    )
    const bridgeNativeTokenBalanceBefore = await nativeToken.balanceOf(
      _l2Network.ethBridge.bridge
    )

    // approve token
    const depositAmount = 350
    await (
      await token.approve(_l2Network.tokenBridge.l1ERC20Gateway, depositAmount)
    ).wait()

    // calculate retryable params
    const maxSubmissionCost = 0
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

    const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(l2Provider)
    const retryableParams = await l1ToL2MessageGasEstimate.estimateAll(
      {
        from: userL1Wallet.address,
        to: userL2Wallet.address,
        l2CallValue: BigNumber.from(0),
        excessFeeRefundAddress: userL1Wallet.address,
        callValueRefundAddress: userL1Wallet.address,
        data: outboundCalldata,
      },
      await getBaseFee(l1Provider),
      l1Provider
    )

    const gasLimit = retryableParams.gasLimit.mul(40)
    const maxFeePerGas = retryableParams.maxFeePerGas
    const tokenTotalFeeAmount = gasLimit.mul(maxFeePerGas).mul(2)

    // approve fee amount
    await (
      await nativeToken.approve(
        _l2Network.tokenBridge.l1ERC20Gateway,
        tokenTotalFeeAmount
      )
    ).wait()

    // bridge it
    const userEncodedData = defaultAbiCoder.encode(
      ['uint256', 'bytes', 'uint256'],
      [maxSubmissionCost, callhook, tokenTotalFeeAmount]
    )

    const router = L1OrbitGatewayRouter__factory.connect(
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
      userEncodedData
    )

    // wait for L2 msg to be executed
    await waitOnL2Msg(depositTx)

    ///// checks

    const l2TokenAddress = await router.calculateL2TokenAddress(token.address)
    const l2Token = ERC20__factory.connect(l2TokenAddress, l2Provider)
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

    const userNativeTokenBalanceAfter = await nativeToken.balanceOf(
      userL1Wallet.address
    )
    console.log('userNativeTokenBalanceAfter', userNativeTokenBalanceAfter)
    expect(
      userNativeTokenBalanceBefore.sub(userNativeTokenBalanceAfter)
    ).to.be.eq(tokenTotalFeeAmount)

    const bridgeNativeTokenBalanceAfter = await nativeToken.balanceOf(
      _l2Network.ethBridge.bridge
    )
    expect(
      bridgeNativeTokenBalanceAfter.sub(bridgeNativeTokenBalanceBefore)
    ).to.be.eq(tokenTotalFeeAmount)
  })
})

async function waitOnL2Msg(tx: ethers.ContractTransaction) {
  const retryableReceipt = await tx.wait()
  const l1TxReceipt = new L1TransactionReceipt(retryableReceipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(l2Provider)

  // 1 msg expected
  const messageResult = await messages[0].waitForStatus()
  const status = messageResult.status
  expect(status).to.be.eq(L1ToL2MessageStatus.REDEEMED)
}
