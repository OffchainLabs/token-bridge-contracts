/*
 * Copyright 2019-2020, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* eslint-env node, mocha */
import { ethers, network } from 'hardhat'
import { assert, expect } from 'chai'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import {
  InboxMock,
  L1ReverseCustomGateway,
  L1ForceOnlyReverseCustomGateway,
  L1GatewayRouter,
  L2ReverseCustomGateway,
  L2GatewayRouter,
} from '../build/types'
import { processL1ToL2Tx, processL2ToL1Tx } from './testhelper'

describe('Bridge peripherals end-to-end reverse custom gateway', () => {
  let accounts: SignerWithAddress[]

  let l1TestRouter: L1GatewayRouter
  let l2TestRouter: L2GatewayRouter
  let l1TestReverseGateway: L1ReverseCustomGateway
  let l2TestReverseGateway: L2ReverseCustomGateway
  let inboxMock: InboxMock

  const maxSubmissionCost = 1
  const maxGas = 1000000000
  const gasPrice = 1

  before(async function () {
    accounts = await ethers.getSigners()

    const InboxMock = await ethers.getContractFactory('InboxMock')
    inboxMock = await InboxMock.deploy()

    // l1 side deploy
    const L1RouterTestBridge = await ethers.getContractFactory(
      'L1GatewayRouter'
    )
    l1TestRouter = await L1RouterTestBridge.deploy()

    const L1TestBridge = await ethers.getContractFactory(
      'L1ReverseCustomGateway'
    )
    l1TestReverseGateway = await L1TestBridge.deploy()

    // l2 side deploy
    const L2TestBridge = await ethers.getContractFactory(
      'L2ReverseCustomGateway'
    )
    l2TestReverseGateway = await L2TestBridge.deploy()

    const L2RouterTestBridge = await ethers.getContractFactory(
      'L2GatewayRouter'
    )
    l2TestRouter = await L2RouterTestBridge.deploy()

    await l1TestReverseGateway.functions.initialize(
      l2TestReverseGateway.address,
      l1TestRouter.address,
      inboxMock.address, // inbox
      accounts[0].address // owner
    )

    await l2TestReverseGateway.initialize(
      l1TestReverseGateway.address,
      l2TestRouter.address
    )

    await l1TestRouter.functions.initialize(
      accounts[0].address,
      ethers.constants.AddressZero, // l1TestBridge.address, // defaultGateway
      '0x0000000000000000000000000000000000000000', // no whitelist
      l2TestRouter.address, // counterparty
      inboxMock.address // inbox
    )

    const l2DefaultGateway = await l1TestReverseGateway.counterpartGateway()
    await l2TestRouter.functions.initialize(
      l1TestRouter.address,
      l2DefaultGateway
    )

    const ArbSysMock = await ethers.getContractFactory('ArbSysMock')
    const arbsysmock = await ArbSysMock.deploy()
    await network.provider.send('hardhat_setCode', [
      '0x0000000000000000000000000000000000000064',
      await network.provider.send('eth_getCode', [arbsysmock.address]),
    ])
  })

  it('should withdraw tokens (L2->L1)', async function () {
    // custom token setup
    const L1ReverseCustomToken = await ethers.getContractFactory(
      'ReverseTestCustomTokenL1'
    )
    const l1ReverseCustomToken = await L1ReverseCustomToken.deploy(
      l1TestReverseGateway.address,
      l1TestRouter.address
    )

    const L2ReverseToken = await ethers.getContractFactory(
      'ReverseTestArbCustomToken'
    )
    const l2ReverseToken = await L2ReverseToken.deploy(
      l2TestReverseGateway.address,
      l1ReverseCustomToken.address
    )

    await processL1ToL2Tx(
      await l1ReverseCustomToken.registerTokenOnL2(
        l2ReverseToken.address,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        accounts[0].address
      )
    )

    // send escrowed tokens to bridge
    const tokenAmount = 100
    await l2ReverseToken.mint()
    await l2ReverseToken.approve(l2TestReverseGateway.address, tokenAmount)

    await processL2ToL1Tx(
      await l2TestRouter['outboundTransfer(address,address,uint256,bytes)'](
        l1ReverseCustomToken.address,
        accounts[0].address,
        tokenAmount,
        '0x'
      ),
      inboxMock
    )

    const escrowedTokens = await l2ReverseToken.balanceOf(
      l2TestReverseGateway.address
    )
    assert.equal(escrowedTokens.toNumber(), tokenAmount, 'Tokens not escrowed')

    const l2TokenAddress = await l2TestRouter.calculateL2TokenAddress(
      l1ReverseCustomToken.address
    )
    assert.equal(
      l2TokenAddress,
      l2ReverseToken.address,
      'Token Pair not correct'
    )

    const l1Balance = await l1ReverseCustomToken.balanceOf(accounts[0].address)
    assert.equal(l1Balance.toNumber(), tokenAmount, 'Tokens not minted')
  })

  it('should deposit tokens (L1->L2)', async function () {
    // custom token setup
    const L1ReverseCustomToken = await ethers.getContractFactory(
      'ReverseTestCustomTokenL1'
    )
    const l1ReverseCustomToken = await L1ReverseCustomToken.deploy(
      l1TestReverseGateway.address,
      l1TestRouter.address
    )

    const L2ReverseToken = await ethers.getContractFactory(
      'ReverseTestArbCustomToken'
    )
    const l2ReverseToken = await L2ReverseToken.deploy(
      l2TestReverseGateway.address,
      l1ReverseCustomToken.address
    )

    await processL1ToL2Tx(
      await l1ReverseCustomToken.registerTokenOnL2(
        l2ReverseToken.address,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        accounts[0].address
      )
    )

    // send escrowed tokens to bridge
    const tokenAmount = 100
    await l2ReverseToken.mint()
    await l2ReverseToken.approve(l2TestReverseGateway.address, tokenAmount)

    await processL2ToL1Tx(
      await l2TestReverseGateway.functions[
        'outboundTransfer(address,address,uint256,bytes)'
      ](l1ReverseCustomToken.address, accounts[0].address, tokenAmount, '0x'),
      inboxMock
    )
    const prevUserBalance = await l2ReverseToken.balanceOf(accounts[0].address)

    const data = ethers.utils.defaultAbiCoder.encode(
      ['uint256', 'bytes'],
      [maxSubmissionCost, '0x']
    )

    await processL1ToL2Tx(
      await l1TestRouter.outboundTransfer(
        l1ReverseCustomToken.address,
        accounts[0].address,
        tokenAmount,
        maxGas,
        gasPrice,
        data,
        { value: maxSubmissionCost + maxGas * gasPrice }
      )
    )

    const postUserBalance = await l2ReverseToken.balanceOf(accounts[0].address)

    assert.equal(
      prevUserBalance.toNumber() + tokenAmount,
      postUserBalance.toNumber(),
      'Tokens not escrowed'
    )
  })

  it('should support ERC165 interface in L1 bridges', async function () {
    expect(await l1TestReverseGateway.supportsInterface('0x01ffc9a7')).is.true
    expect(await l1TestReverseGateway.supportsInterface('0xffffffff')).is.false
  })

  it('should support outboundTransferCustomRefund interface', async function () {
    // 4fb1a07b  =>  outboundTransferCustomRefund(address,address,address,uint256,uint256,uint256,bytes)
    expect(await l1TestReverseGateway.supportsInterface('0x4fb1a07b')).is.true
  })
})

describe('Bridge peripherals end-to-end force only reverse custom gateway', () => {
  let accounts: SignerWithAddress[]

  let l1TestRouter: L1GatewayRouter
  let l2TestRouter: L2GatewayRouter
  let l1TestForceOnlyReverseGateway: L1ForceOnlyReverseCustomGateway
  let l2TestReverseGateway: L2ReverseCustomGateway
  let inboxMock: InboxMock

  const maxSubmissionCost = 1
  const maxGas = 1000000000
  const gasPrice = 1

  before(async function () {
    accounts = await ethers.getSigners()

    const InboxMock = await ethers.getContractFactory('InboxMock')
    inboxMock = await InboxMock.deploy()

    // l1 side deploy
    const L1RouterTestBridge = await ethers.getContractFactory(
      'L1GatewayRouter'
    )
    l1TestRouter = await L1RouterTestBridge.deploy()

    const L1TestBridge = await ethers.getContractFactory(
      'L1ForceOnlyReverseCustomGateway'
    )
    l1TestForceOnlyReverseGateway = await L1TestBridge.deploy()

    // l2 side deploy
    const L2TestBridge = await ethers.getContractFactory(
      'L2ReverseCustomGateway'
    )
    l2TestReverseGateway = await L2TestBridge.deploy()

    const L2RouterTestBridge = await ethers.getContractFactory(
      'L2GatewayRouter'
    )
    l2TestRouter = await L2RouterTestBridge.deploy()

    await l1TestForceOnlyReverseGateway.functions.initialize(
      l2TestReverseGateway.address,
      l1TestRouter.address,
      inboxMock.address, // inbox
      accounts[0].address // owner
    )

    await l2TestReverseGateway.initialize(
      l1TestForceOnlyReverseGateway.address,
      l2TestRouter.address
    )

    await l1TestRouter.functions.initialize(
      accounts[0].address,
      ethers.constants.AddressZero, // l1TestBridge.address, // defaultGateway
      '0x0000000000000000000000000000000000000000', // no whitelist
      l2TestRouter.address, // counterparty
      inboxMock.address // inbox
    )

    const l2DefaultGateway =
      await l1TestForceOnlyReverseGateway.counterpartGateway()
    await l2TestRouter.functions.initialize(
      l1TestRouter.address,
      l2DefaultGateway
    )

    const ArbSysMock = await ethers.getContractFactory('ArbSysMock')
    const arbsysmock = await ArbSysMock.deploy()
    await network.provider.send('hardhat_setCode', [
      '0x0000000000000000000000000000000000000064',
      await network.provider.send('eth_getCode', [arbsysmock.address]),
    ])
  })

  it('should deposit tokens (L1->L2)', async function () {
    // custom token setup
    const L1ReverseCustomToken = await ethers.getContractFactory(
      'ReverseTestCustomTokenL1'
    )
    const l1ReverseCustomToken = await L1ReverseCustomToken.deploy(
      l1TestForceOnlyReverseGateway.address,
      l1TestRouter.address
    )

    const L2ReverseToken = await ethers.getContractFactory(
      'ReverseTestArbCustomToken'
    )
    const l2ReverseToken = await L2ReverseToken.deploy(
      l2TestReverseGateway.address,
      l1ReverseCustomToken.address
    )

    try {
      await l1ReverseCustomToken.registerTokenOnL2(
        l2ReverseToken.address,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        accounts[0].address
      )

      expect(true, 'Register should have failed but didnt').to.be.false
    } catch (err) {
      const error = err as Error
      expect(error.message, 'Registration disabled').to.include(
        'REGISTER_TOKEN_ON_L2_DISABLED'
      )
    }

    await processL1ToL2Tx(
      await l1TestForceOnlyReverseGateway.forceRegisterTokenToL2(
        [l1ReverseCustomToken.address],
        [l2ReverseToken.address],
        0,
        0,
        0
      )
    )

    await processL1ToL2Tx(
      await l1TestRouter.setGateways(
        [l1ReverseCustomToken.address],
        [l1TestForceOnlyReverseGateway.address],
        0,
        0,
        0
      )
    )

    // send escrowed tokens to bridge
    const tokenAmount = 100
    await l2ReverseToken.mint()
    await l2ReverseToken.approve(l2TestReverseGateway.address, tokenAmount)

    await processL2ToL1Tx(
      await l2TestReverseGateway.functions[
        'outboundTransfer(address,address,uint256,bytes)'
      ](l1ReverseCustomToken.address, accounts[0].address, tokenAmount, '0x'),
      inboxMock
    )
    const prevUserBalance = await l2ReverseToken.balanceOf(accounts[0].address)

    const data = ethers.utils.defaultAbiCoder.encode(
      ['uint256', 'bytes'],
      [maxSubmissionCost, '0x']
    )

    await processL1ToL2Tx(
      await l1TestRouter.outboundTransfer(
        l1ReverseCustomToken.address,
        accounts[0].address,
        tokenAmount,
        maxGas,
        gasPrice,
        data,
        { value: maxSubmissionCost + maxGas * gasPrice }
      )
    )

    const postUserBalance = await l2ReverseToken.balanceOf(accounts[0].address)

    assert.equal(
      prevUserBalance.toNumber() + tokenAmount,
      postUserBalance.toNumber(),
      'Tokens not escrowed'
    )
  })
})
