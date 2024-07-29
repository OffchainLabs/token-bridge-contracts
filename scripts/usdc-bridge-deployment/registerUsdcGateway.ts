import dotenv from 'dotenv'
import { Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { JsonRpcProvider } from '@ethersproject/providers'

dotenv.config()

main().then(() => console.log('Done.'))

async function main() {
  const { deployerL1 } = await _loadWallet()
}

async function _loadWallet(): Promise<{
  deployerL1: Wallet
}> {
  const parentRpc = process.env['PARENT_RPC'] as string
  const parentDeployerKey = process.env['PARENT_DEPLOYER_KEY'] as string

  if (!parentRpc || !parentDeployerKey) {
    throw new Error('Missing env vars')
  }

  const parentProvider = new JsonRpcProvider(parentRpc)
  const deployerL1 = new ethers.Wallet(parentDeployerKey, parentProvider)

  return { deployerL1 }
}
