import dotenv from 'dotenv'
import { Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  L1GatewayRouter__factory,
  UpgradeExecutor__factory,
} from '../../build/types'

dotenv.config()

main().then(() => console.log('Done.'))

async function main() {
  const { rollupOwner } = await _loadWallet()

  const l1RouterAddress = process.env['L1_ROUTER'] as string
  const l1Router = L1GatewayRouter__factory.connect(l1RouterAddress, rollupOwner)

  const routerOwnerAddress = await l1Router.owner()
  if (!(await _isUpgradeExecutor(routerOwnerAddress, rollupOwner))) {
    throw new Error('Router owner is expected to be an UpgradeExecutor')
  }

  const upgradeExecutor = UpgradeExecutor__factory.connect(
    routerOwnerAddress,
    rollupOwner
  )
}

async function _loadWallet(): Promise<{
  rollupOwner: Wallet
}> {
  const parentRpc = process.env['PARENT_RPC'] as string
  const parentRollupOwnerKey = process.env['ROLLUP_OWNER'] as string

  if (!parentRpc || !parentRollupOwnerKey) {
    throw new Error('Missing env vars')
  }

  const parentProvider = new JsonRpcProvider(parentRpc)
  const rollupOwner = new ethers.Wallet(parentRollupOwnerKey, parentProvider)

  return { rollupOwner }
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
