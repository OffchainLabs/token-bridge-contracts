import { JsonRpcProvider } from '@ethersproject/providers'
import { L2AtomicTokenBridgeFactory__factory } from '../build/types'
import dotenv from 'dotenv'
import { Wallet } from 'ethers'

dotenv.config()

async function main() {
  const deployRpc = process.env['BASECHAIN_RPC'] as string
  if (deployRpc == undefined) {
    throw new Error("Env var 'BASECHAIN_RPC' not set")
  }
  const rpc = new JsonRpcProvider(deployRpc)

  const deployKey = process.env['BASECHAIN_DEPLOYER_KEY'] as string
  if (deployKey == undefined) {
    throw new Error("Env var 'BASECHAIN_DEPLOYER_KEY' not set")
  }
  const deployer = new Wallet(deployKey).connect(rpc)

  console.log(
    'Deploying L2AtomicTokenBridgeFactory to chain',
    await deployer.getChainId()
  )
  const l2TokenBridgeFactory = await new L2AtomicTokenBridgeFactory__factory(
    deployer
  ).deploy()
  await l2TokenBridgeFactory.deployed()

  console.log('l2TokenBridgeFactory:', l2TokenBridgeFactory.address)
}

main().then(() => console.log('Done.'))
