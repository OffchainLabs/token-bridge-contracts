import { ethers } from 'hardhat'
import { run } from 'hardhat'
import {
  IERC20Bridge__factory,
  IInboxBase__factory,
  L1GatewayRouter__factory,
  L1OrbitGatewayRouter__factory,
} from '../../build/types'
import { JsonRpcProvider, Provider } from '@ethersproject/providers'

main().then(() => console.log('Done.'))

/**
 * USDC bridge verification script for the parent chain.
 * Script will verify the following contracts:
 * - L1 proxy admin
 * - L1 USDC gateway (behind a TUP with L1ProxyAdmin as admin)
 */
async function main() {
  console.log('Starting USDC bridge contract verification on the parent chain')
  _checkEnvVars()

  //
  // Loading chain information
  //
  const parentRpc = process.env['PARENT_RPC'] as string
  const parentProvider = new JsonRpcProvider(parentRpc)

  const inboxAddress = process.env['INBOX'] as string
  const parentGatewayRouterAddress = process.env['L1_ROUTER'] as string
  const parentUsdcAddress = process.env['L1_USDC'] as string

  //
  // Getting deployed contract addresses
  //
  const isFeeToken =
    (await _getFeeToken(inboxAddress, parentProvider)) !=
    ethers.constants.AddressZero

  // Parent chain gateway router
  const parentGatewayRouter = isFeeToken
    ? L1OrbitGatewayRouter__factory.connect(
        parentGatewayRouterAddress,
        parentProvider
      )
    : L1GatewayRouter__factory.connect(
        parentGatewayRouterAddress,
        parentProvider
      )

  // Parent chain USDC gateway
  const parentUsdcGatewayAddress = await parentGatewayRouter.l1TokenToGateway(
    parentUsdcAddress
  )
  if (parentUsdcGatewayAddress === ethers.constants.AddressZero) {
    throw new Error(
      'It looks like the new Usdc custom gateway is not registered in the GatewayRouter'
    )
  }
  const parentUsdcGatewayLogicAddress = await _getLogicAddress(
    parentUsdcGatewayAddress,
    parentProvider
  )

  // Proxy admin
  const parentProxyAdminAddress = await _getAdminAddress(
    parentUsdcGatewayAddress,
    parentProvider
  )

  // Verify single TUP, others TUPs will be verified by bytecode match
  await _verifyContract(
    'TransparentUpgradeableProxy',
    parentUsdcGatewayAddress,
    [parentUsdcGatewayLogicAddress, parentProxyAdminAddress, '0x']
  )

  // Verify Parent chain USDC gateway
  await _verifyContract(
    isFeeToken ? 'L1OrbitUSDCGateway' : 'L1USDCGateway',
    parentUsdcGatewayLogicAddress,
    []
  )

  // Verify Parent chain ProxyAdmin
  await _verifyContract('ProxyAdmin', parentProxyAdminAddress, [])
}

async function _verifyContract(
  contractName: string,
  contractAddress: string,
  constructorArguments: any[] = [],
  contractPathAndName?: string // optional
): Promise<void> {
  try {
    // Define the verification options with possible 'contract' property
    const verificationOptions: {
      contract?: string
      address: string
      constructorArguments: any[]
    } = {
      address: contractAddress,
      constructorArguments: constructorArguments,
    }

    // if contractPathAndName is provided, add it to the verification options
    if (contractPathAndName) {
      verificationOptions.contract = contractPathAndName
    }

    await run('verify:verify', verificationOptions)
    console.log(`Verified contract ${contractName} successfully.`)
  } catch (error: any) {
    if (error.message.includes('Already Verified')) {
      console.log(`Contract ${contractName} is already verified.`)
    } else {
      console.error(
        `Verification for ${contractName} failed with the following error: ${error.message}`
      )
    }
  }
}

async function _getLogicAddress(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  return (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
    )
  ).toLowerCase()
}

async function _getAdminAddress(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  return (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
    )
  ).toLowerCase()
}

async function _getAddressAtStorageSlot(
  contractAddress: string,
  provider: Provider,
  storageSlotBytes: string
): Promise<string> {
  const storageValue = await provider.getStorageAt(
    contractAddress,
    storageSlotBytes
  )

  if (!storageValue) {
    return ''
  }

  // remove excess bytes
  const formatAddress =
    storageValue.substring(0, 2) + storageValue.substring(26)

  // return address as checksum address
  return ethers.utils.getAddress(formatAddress)
}

/**
 * Fetch fee token if it exists or return zero address
 */
async function _getFeeToken(
  inbox: string,
  provider: Provider
): Promise<string> {
  const bridge = await IInboxBase__factory.connect(inbox, provider).bridge()

  let feeToken = ethers.constants.AddressZero

  try {
    feeToken = await IERC20Bridge__factory.connect(
      bridge,
      provider
    ).nativeToken()
  } catch {
    // ignore
  }

  return feeToken
}

/**
 * Check if all required env vars are set
 */
function _checkEnvVars() {
  const requiredEnvVars = [
    'PARENT_RPC',
    'CHILD_RPC',
    'L1_ROUTER',
    'L2_ROUTER',
    'INBOX',
    'L1_USDC',
  ]

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`Missing env var ${envVar}`)
    }
  }
}
