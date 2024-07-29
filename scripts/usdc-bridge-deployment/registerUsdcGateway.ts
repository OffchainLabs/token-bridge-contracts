import dotenv from 'dotenv'
import { BigNumber, ContractTransaction, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { JsonRpcProvider, Provider } from '@ethersproject/providers'
import {
  L1GatewayRouter__factory,
  UpgradeExecutor__factory,
} from '../../build/types'
import {
  addCustomNetwork,
  L1Network,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
} from '@arbitrum/sdk'
import { RollupAdminLogic__factory } from '@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory'

dotenv.config()

main().then(() => console.log('Done.'))

async function main() {
  const { rollupOwner, childProvider } = await _loadWallet()

  const rollup = process.env['ROLLUP'] as string
  _registerNetworks(rollupOwner.provider!, childProvider, rollup)

  const l1RouterAddress = process.env['L1_ROUTER'] as string
  const l1Router = L1GatewayRouter__factory.connect(
    l1RouterAddress,
    rollupOwner
  )

  /// load upgrade executor
  const routerOwnerAddress = await l1Router.owner()
  if (!(await _isUpgradeExecutor(routerOwnerAddress, rollupOwner))) {
    throw new Error('Router owner is expected to be an UpgradeExecutor')
  }
  const upgradeExecutor = UpgradeExecutor__factory.connect(
    routerOwnerAddress,
    rollupOwner
  )

  /// prepare calldata for executor
  const l1UsdcAddress = process.env['L1_USDC'] as string
  const l1UsdcGatewayAddress = process.env['L1_USDC_GATEWAY'] as string

  const maxGas = BigNumber.from(500000)
  const gasPriceBid = BigNumber.from(200000000)
  let maxSubmissionCost = BigNumber.from(257600000000)
  const registrationCalldata = l1Router.interface.encodeFunctionData(
    'setGateways',
    [
      [l1UsdcAddress],
      [l1UsdcGatewayAddress],
      maxGas,
      gasPriceBid,
      maxSubmissionCost,
    ]
  )

  /// execute the registration
  const gwRegistrationTx = await upgradeExecutor.executeCall(
    l1Router.address,
    registrationCalldata,
    {
      value: maxGas.mul(gasPriceBid).add(maxSubmissionCost),
    }
  )
  await waitOnL2Msg(gwRegistrationTx, childProvider)
  console.log('USDC custom gateway registered')
}

async function _loadWallet(): Promise<{
  rollupOwner: Wallet
  childProvider: JsonRpcProvider
}> {
  const parentRpc = process.env['PARENT_RPC'] as string
  const parentRollupOwnerKey = process.env['ROLLUP_OWNER_KEY'] as string
  const childRpc = process.env['CHILD_RPC'] as string

  if (!parentRpc || !parentRollupOwnerKey || !childRpc) {
    throw new Error('Missing env vars')
  }

  const parentProvider = new JsonRpcProvider(parentRpc)
  const rollupOwner = new ethers.Wallet(parentRollupOwnerKey, parentProvider)
  const childProvider = new JsonRpcProvider(childRpc)

  return { rollupOwner, childProvider }
}

/**
 * Check if owner is UpgardeExecutor by polling ADMIN_ROLE() and EXECUTOR_ROLE()
 * @param routerOwnerAddress
 * @param rollupOwner
 * @returns
 */
async function _isUpgradeExecutor(
  routerOwnerAddress: string,
  rollupOwner: Wallet
): Promise<boolean> {
  // check if address implements ADMIN_ROLE() and EXECUTOR_ROLE()
  const upgExecutor = UpgradeExecutor__factory.connect(
    routerOwnerAddress,
    rollupOwner
  )
  try {
    await upgExecutor.ADMIN_ROLE()
    await upgExecutor.EXECUTOR_ROLE()
  } catch {
    return false
  }

  return true
}

async function waitOnL2Msg(
  tx: ContractTransaction,
  childProvider: JsonRpcProvider
) {
  const retryableReceipt = await tx.wait()
  const l1TxReceipt = new L1TransactionReceipt(retryableReceipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(childProvider)

  // 1 msg expected
  const messageResult = await messages[0].waitForStatus()
  const status = messageResult.status

  if (status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error('L1->L2 message not redeemed')
  }
}

const _registerNetworks = async (
  l1Provider: Provider,
  l2Provider: Provider,
  rollupAddress: string
): Promise<{
  l1Network: L1Network
  l2Network: Omit<L2Network, 'tokenBridge'>
}> => {
  const l1NetworkInfo = await l1Provider.getNetwork()
  const l2NetworkInfo = await l2Provider.getNetwork()

  const l1Network: L1Network = {
    blockTime: 10,
    chainID: l1NetworkInfo.chainId,
    explorerUrl: '',
    isCustom: true,
    name: l1NetworkInfo.name,
    partnerChainIDs: [l2NetworkInfo.chainId],
    isArbitrum: false,
  }

  const rollup = RollupAdminLogic__factory.connect(rollupAddress, l1Provider)
  const l2Network: L2Network = {
    blockTime: 10,
    partnerChainIDs: [],
    chainID: l2NetworkInfo.chainId,
    confirmPeriodBlocks: (await rollup.confirmPeriodBlocks()).toNumber(),
    ethBridge: {
      bridge: await rollup.bridge(),
      inbox: await rollup.inbox(),
      outbox: await rollup.outbox(),
      rollup: rollup.address,
      sequencerInbox: await rollup.sequencerInbox(),
    },
    explorerUrl: '',
    isArbitrum: true,
    isCustom: true,
    name: 'OrbitChain',
    partnerChainID: l1NetworkInfo.chainId,
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

  // register - needed for retryables
  addCustomNetwork({
    customL1Network: l1Network,
    customL2Network: l2Network,
  })

  return {
    l1Network,
    l2Network,
  }
}
