import { ethers } from 'hardhat'
import { run } from 'hardhat'
import {
  AeWETH__factory,
  BeaconProxyFactory__factory,
  L1AtomicTokenBridgeCreator__factory,
  UpgradeableBeacon__factory,
} from '../build/types'
import { Provider } from '@ethersproject/providers'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'

main().then(() => console.log('Done.'))

async function main() {
  const parentRpcUrl = process.env['BASECHAIN_RPC'] as string
  const tokenBridgeCreatorAddress = process.env[
    'L1_TOKEN_BRIDGE_CREATOR'
  ] as string
  const inboxAddress = process.env['INBOX_ADDRESS'] as string
  const deployerKey = process.env['DEPLOYER_KEY'] as string

  if (!parentRpcUrl || !tokenBridgeCreatorAddress || !inboxAddress) {
    throw new Error(
      'Required env vars: BASECHAIN_RPC, L1_TOKEN_BRIDGE_CREATOR, INBOX_ADDRESS'
    )
  }

  if (!deployerKey) {
    console.log(
      'DEPLOYER_KEY is missing. Deployer key is required if you want to have aeWETH and UpgradeExecutor verified.'
    )
  }

  const parentProvider = new ethers.providers.JsonRpcProvider(parentRpcUrl)
  const orbitProvider = ethers.provider
  const deployerOnOrbit = new ethers.Wallet(deployerKey, orbitProvider)

  /// collect addresses
  const tokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    tokenBridgeCreatorAddress,
    parentProvider
  )
  const l2Factory = await tokenBridgeCreator.canonicalL2FactoryAddress()
  const l2Deployment = await tokenBridgeCreator.inboxToL2Deployment(
    inboxAddress
  )
  const beaconProxyFactory = BeaconProxyFactory__factory.connect(
    l2Deployment.beaconProxyFactory,
    orbitProvider
  )
  const upgradeableBeacon = UpgradeableBeacon__factory.connect(
    await beaconProxyFactory.beacon(),
    orbitProvider
  )
  const standardArbERC20 = await upgradeableBeacon.implementation()

  console.log(
    'Start verification of token bridge contracts deployed to chain',
    (await orbitProvider.getNetwork()).chainId
  )

  // verify L2 factory
  await _verifyContract('L2AtomicTokenBridgeFactory', l2Factory, [])

  // verify single TUP, others TUPs will be verified by bytecode match
  await _verifyContract('TransparentUpgradeableProxy', l2Deployment.router, [
    l2Factory,
    l2Deployment.proxyAdmin,
    '0x',
  ])

  // verify orbit contracts
  await _verifyContract(
    'L2GatewayRouter',
    await _getLogicAddress(l2Deployment.router, orbitProvider),
    []
  )
  await _verifyContract(
    'L2ERC20Gateway',
    await _getLogicAddress(l2Deployment.standardGateway, orbitProvider),
    []
  )
  await _verifyContract(
    'L2CustomGateway',
    await _getLogicAddress(l2Deployment.customGateway, orbitProvider),
    []
  )
  await _verifyContract(
    'L2WethGateway',
    await _getLogicAddress(l2Deployment.wethGateway, orbitProvider),
    []
  )
  await _verifyContract('BeaconProxyFactory', beaconProxyFactory.address, [])
  await _verifyContract('UpgradeableBeacon', upgradeableBeacon.address, [
    standardArbERC20,
  ])
  await _verifyContract('StandardArbERC20', standardArbERC20, [])
  await _verifyContract('ArbMulticall2', l2Deployment.multicall, [])
  await _verifyContract('ProxyAdmin', l2Deployment.proxyAdmin, [])

  /// special cases - aeWETH and UpgradeExecutor

  if (deployerKey) {
    // deploy dummy aeWETH and verify it. Its deployed bytecode will match the actual aeWETH bytecode
    const dummyAeWethFac = await new AeWETH__factory(deployerOnOrbit).deploy()
    const dummyAeWeth = await dummyAeWethFac.deployed()
    await _verifyContract('aeWETH', dummyAeWeth.address, [])

    // deploy dummy UpgradeExecutor and verify it. Its deployed bytecode will match the actual UpgradeExecutor bytecode
    const dummyUpgradeExecutorFac = new ethers.ContractFactory(
      UpgradeExecutorABI,
      UpgradeExecutorBytecode,
      deployerOnOrbit
    )
    const dummyUpgradeExecutor = await dummyUpgradeExecutorFac.deploy()
    await dummyUpgradeExecutor.deployed()
    await _verifyContract('UpgradeExecutor', dummyUpgradeExecutor.address, [])
  }
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
