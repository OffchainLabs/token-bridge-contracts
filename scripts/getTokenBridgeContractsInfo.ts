import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { promises as fs } from 'fs'
import { L1AtomicTokenBridgeCreator__factory } from '../build/types'
import { execSync } from 'child_process'

// Types
type Alloc = {
  [key: string]: {
    code: `0x${string}`
    nonce: number
    balance: string
    storage?: { [key: `0x${string}`]: `0x${string}` }
  }
}

// Constants
// EIP-1967 admin slot
const adminSlot =
  '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
// EIP-1967 implementation slot
const implSlot =
  '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'

// Initialize alloc object
const alloc: Alloc = {}

// Check environment variables
const parentChainRpc = process.env.PARENT_CHAIN_RPC as string
if (!parentChainRpc) {
  throw new Error('PARENT_CHAIN_RPC not set')
}
const parentChainProvider = new ethers.providers.JsonRpcProvider(parentChainRpc)

const tokenBridgeCreatorAddress = process.env
  .TOKENBRIDGE_CREATOR_ADDRESS as `0x${string}`
if (!tokenBridgeCreatorAddress) {
  throw new Error('TOKENBRIDGE_CREATOR_ADDRESS not set')
}

// Helper function to get contract code and nonce
async function getAccountInformation(
  address: `0x${string}`,
  contractPath?: string,
  excludeStorageEntries?: string[]
) {
  const code = await parentChainProvider.getCode(address)
  const nonce = await parentChainProvider.getTransactionCount(address)
  const balance = await parentChainProvider.getBalance(address)
  let storage = {}
  if (contractPath) {
    storage = await getStorageLayout(
      address,
      contractPath,
      excludeStorageEntries
    )
  }
  return {
    code: code as `0x${string}`,
    nonce,
    balance: balance.toString(),
    storage,
  }
}

// Helper function and types to get the storage layout
type ForgeStorageEntry = {
  astId: number
  contract: string
  label: string
  offset: number
  slot: string // note: string, we’ll convert to bigint
  type: string
  bytes: string
}

type ForgeStorageLayout = {
  storage: ForgeStorageEntry[]
  types: Record<string, any>
}

function isMapping(type: string): boolean {
  return type.startsWith('t_mapping')
}

function isArrayType(type: string): boolean {
  return type.startsWith('t_array')
}

// crude: fixed vs dynamic array from type name
function parseArrayInfo(type: string): { baseType: string; length?: number } {
  // examples:
  //   t_array(t_address)dyn_storage
  //   t_array(t_uint256)40_storage
  const m = type.match(/^t_array\(([^)]+)\)([^_]*)_storage$/)
  if (!m) return { baseType: type }

  const baseType = m[1]
  const lenPart = m[2] // "dyn" or "40"
  if (lenPart === 'dyn') {
    return { baseType }
  }

  const length = Number(lenPart)
  return { baseType, length }
}

// pad slot -> 32-byte for keccak
function slotToPaddedHex(slot: bigint): string {
  return ethers.utils.hexZeroPad(ethers.utils.hexlify(slot), 32)
}

async function getStorageLayout(
  address: `0x${string}`,
  contractPath: string,
  excludeStorageEntries?: string[]
) {
  // Get Storage layout from contract code
  const rawStorageLayout = execSync(
    `forge inspect ${contractPath} storage --json`,
    { encoding: 'utf8' } // so we get a string instead of Buffer
  )
  const layout: ForgeStorageLayout = JSON.parse(rawStorageLayout)
  const entries = layout.storage

  // Read storage entries in contract
  const storage: Record<string, string> = {}
  const simpleSlots = new Set<bigint>()

  for (const entry of entries) {
    const slot = BigInt(entry.slot)
    const type = entry.type
    if (excludeStorageEntries && excludeStorageEntries.includes(entry.label)) {
      continue
    }

    // Mappings
    if (isMapping(type)) {
      // skip mappings: need explicit keys
      continue
    }

    // Arrays
    if (isArrayType(type)) {
      const { length } = parseArrayInfo(type)

      if (length !== undefined) {
        // fixed-length array: contiguous slots
        for (let i = 0; i < length; i++) {
          simpleSlots.add(slot + BigInt(i))
        }
      } else {
        // dynamic array: slot holds length; data at keccak(slot) + i
        const lenWord = await parentChainProvider.getStorageAt(address, slot)
        storage[ethers.utils.hexlify(slot)] = lenWord

        const arrLength = Number(BigInt(lenWord))
        const dataStart = ethers.utils.keccak256(slotToPaddedHex(slot))
        const base = BigInt(dataStart)

        for (let i = 0; i < arrLength; i++) {
          const elemSlot = base + BigInt(i)
          const elemValue = await parentChainProvider.getStorageAt(
            address,
            elemSlot
          )
          storage[ethers.utils.hexlify(elemSlot)] = elemValue
        }
      }

      continue
    }

    // For all other types, read number of slots based on size
    //    This covers:
    //    - scalar vars (bytes <= 32 → 1 word)
    //    - structs (ex., bytes=192 → 6 words)
    const typeInfo = layout.types[entry.type]
    const bytes = Number(typeInfo.numberOfBytes)
    const nWords = Math.max(1, Math.ceil(bytes / 32))
    for (let i = 0; i < nWords; i++) {
      simpleSlots.add(slot + BigInt(i))
    }
  }

  // Parallel fetch of simple slots
  await Promise.all(
    Array.from(simpleSlots).map(async slot => {
      const value = await parentChainProvider.getStorageAt(address, slot)
      storage[ethers.utils.hexlify(slot)] = value
    })
  )

  return storage
}

async function getAddressFromStorage(
  address: `0x${string}`,
  rawslot: `0x${string}`
): Promise<`0x${string}`> {
  const slot = ethers.BigNumber.from(rawslot)
  const addressRaw = await parentChainProvider.getStorageAt(
    address,
    slot.toBigInt()
  )
  return ethers.utils.getAddress(
    ethers.utils.hexDataSlice(addressRaw, 12)
  ) as `0x${string}`
}

async function addAddressToStorage(
  contractAddress: `0x${string}`,
  slot: `0x${string}`,
  addressToAdd: `0x${string}`
): Promise<void> {
  if (!alloc[contractAddress].storage) {
    alloc[contractAddress].storage = {}
  }
  alloc[contractAddress].storage![slot] = addressToAdd
}

async function main() {
  // Create2 proxy
  const create2ProxyAddress =
    '0x4e59b44847b379578588920cA78FbF26c0B4956C' as `0x${string}`
  alloc[create2ProxyAddress] = await getAccountInformation(create2ProxyAddress)

  // TokenBridgeCreator
  alloc[tokenBridgeCreatorAddress] = await getAccountInformation(
    tokenBridgeCreatorAddress,
    'contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol:L1AtomicTokenBridgeCreator'
  )

  // TokenBridgeCreator ProxyAdmin
  const tokenBridgeCreatorProxyAdminAddress = await getAddressFromStorage(
    tokenBridgeCreatorAddress,
    adminSlot
  )
  alloc[tokenBridgeCreatorProxyAdminAddress] = await getAccountInformation(
    tokenBridgeCreatorProxyAdminAddress,
    'ProxyAdmin'
  )
  await addAddressToStorage(
    tokenBridgeCreatorAddress,
    adminSlot,
    tokenBridgeCreatorProxyAdminAddress
  )

  // TokenBridgeCreator Logic
  const tokenBridgeCreatorLogicAddress = await getAddressFromStorage(
    tokenBridgeCreatorAddress,
    implSlot
  )
  alloc[tokenBridgeCreatorLogicAddress] = await getAccountInformation(
    tokenBridgeCreatorLogicAddress,
    'contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol:L1AtomicTokenBridgeCreator'
  )
  await addAddressToStorage(
    tokenBridgeCreatorAddress,
    implSlot,
    tokenBridgeCreatorLogicAddress
  )

  // RetryableSender
  const tokenBridgeCreator = L1AtomicTokenBridgeCreator__factory.connect(
    tokenBridgeCreatorAddress,
    parentChainProvider
  )
  const retryableSenderAddress =
    (await tokenBridgeCreator.retryableSender()) as `0x${string}`
  alloc[retryableSenderAddress] = await getAccountInformation(
    retryableSenderAddress,
    'contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol:L1TokenBridgeRetryableSender'
  )

  // RetryableSender Logic
  const retryableSenderLogicAddress = await getAddressFromStorage(
    retryableSenderAddress,
    implSlot
  )
  alloc[retryableSenderLogicAddress] = await getAccountInformation(
    retryableSenderLogicAddress,
    'contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol:L1TokenBridgeRetryableSender'
  )
  await addAddressToStorage(
    retryableSenderAddress,
    implSlot,
    retryableSenderLogicAddress
  )

  // L1 templates
  const {
    routerTemplate,
    standardGatewayTemplate,
    customGatewayTemplate,
    wethGatewayTemplate,
    feeTokenBasedRouterTemplate,
    feeTokenBasedStandardGatewayTemplate,
    feeTokenBasedCustomGatewayTemplate,
    upgradeExecutor,
  } = await tokenBridgeCreator.l1Templates()

  alloc[routerTemplate] = await getAccountInformation(
    routerTemplate as `0x${string}`,
    'contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol:L1GatewayRouter'
  )
  alloc[standardGatewayTemplate] = await getAccountInformation(
    standardGatewayTemplate as `0x${string}`,
    'contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol:L1ERC20Gateway'
  )
  alloc[customGatewayTemplate] = await getAccountInformation(
    customGatewayTemplate as `0x${string}`,
    'contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol:L1CustomGateway'
  )
  alloc[wethGatewayTemplate] = await getAccountInformation(
    wethGatewayTemplate as `0x${string}`,
    'contracts/tokenbridge/ethereum/gateway/L1WethGateway.sol:L1WethGateway'
  )
  alloc[feeTokenBasedRouterTemplate] = await getAccountInformation(
    feeTokenBasedRouterTemplate as `0x${string}`,
    'contracts/tokenbridge/ethereum/gateway/L1OrbitGatewayRouter.sol:L1OrbitGatewayRouter'
  )
  alloc[feeTokenBasedStandardGatewayTemplate] = await getAccountInformation(
    feeTokenBasedStandardGatewayTemplate as `0x${string}`,
    'contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol:L1OrbitERC20Gateway'
  )
  alloc[feeTokenBasedCustomGatewayTemplate] = await getAccountInformation(
    feeTokenBasedCustomGatewayTemplate as `0x${string}`,
    'contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol:L1OrbitCustomGateway'
  )
  alloc[upgradeExecutor] = await getAccountInformation(
    upgradeExecutor as `0x${string}`
  )

  // L2 templates
  const l2TokenBridgeFactoryTemplate =
    (await tokenBridgeCreator.l2TokenBridgeFactoryTemplate()) as `0x${string}`
  alloc[l2TokenBridgeFactoryTemplate] = await getAccountInformation(
    l2TokenBridgeFactoryTemplate,
    'contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol:L2AtomicTokenBridgeFactory'
  )
  const l2RouterTemplate =
    (await tokenBridgeCreator.l2RouterTemplate()) as `0x${string}`
  alloc[l2RouterTemplate] = await getAccountInformation(
    l2RouterTemplate,
    'contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol:L2GatewayRouter'
  )
  const l2StandardGatewayTemplate =
    (await tokenBridgeCreator.l2StandardGatewayTemplate()) as `0x${string}`
  alloc[l2StandardGatewayTemplate] = await getAccountInformation(
    l2StandardGatewayTemplate,
    'contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol:L2ERC20Gateway'
  )
  const l2CustomGatewayTemplate =
    (await tokenBridgeCreator.l2CustomGatewayTemplate()) as `0x${string}`
  alloc[l2CustomGatewayTemplate] = await getAccountInformation(
    l2CustomGatewayTemplate,
    'contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol:L2CustomGateway'
  )
  const l2WethGatewayTemplate =
    (await tokenBridgeCreator.l2WethGatewayTemplate()) as `0x${string}`
  alloc[l2WethGatewayTemplate] = await getAccountInformation(
    l2WethGatewayTemplate,
    'contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol:L2WethGateway'
  )
  const l2WethTemplate =
    (await tokenBridgeCreator.l2WethTemplate()) as `0x${string}`
  alloc[l2WethTemplate] = await getAccountInformation(
    l2WethTemplate,
    'contracts/tokenbridge/libraries/aeWETH.sol:aeWETH'
  )
  const l2MulticallTemplate =
    (await tokenBridgeCreator.l2MulticallTemplate()) as `0x${string}`
  alloc[l2MulticallTemplate] = await getAccountInformation(
    l2MulticallTemplate,
    'contracts/rpc-utils/MulticallV2.sol:ArbMulticall2'
  )

  // L1 Weth
  const l1WethAddress = (await tokenBridgeCreator.l1Weth()) as `0x${string}`
  alloc[l1WethAddress] = await getAccountInformation(
    l1WethAddress,
    'contracts/tokenbridge/test/TestWETH9.sol:TestWETH9'
  )

  // L1 Multicall
  const l1MulticallAddress =
    (await tokenBridgeCreator.l1Multicall()) as `0x${string}`
  alloc[l1MulticallAddress] = await getAccountInformation(
    l1MulticallAddress,
    'contracts/rpc-utils/MulticallV2.sol:Multicall2'
  )

  // Craft file
  const allocPath =
    process.env.LOCAL_DEPLOYMENT_ALLOC_PATH !== undefined
      ? process.env.LOCAL_DEPLOYMENT_ALLOC_PATH
      : 'local_deployment_alloc.json'

  await fs.writeFile(allocPath, JSON.stringify(alloc, null, 2), 'utf8')
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
