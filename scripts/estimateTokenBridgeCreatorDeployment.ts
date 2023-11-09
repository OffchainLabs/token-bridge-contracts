import dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { NODE_INTERFACE_ADDRESS } from '@arbitrum/sdk/dist/lib/dataEntities/constants'
import { NodeInterface__factory } from '@arbitrum/sdk/dist/lib/abi/factories/NodeInterface__factory'
import { NodeInterface } from '@arbitrum/sdk/dist/lib/abi/NodeInterface'
import { BigNumber, ContractFactory, Signer } from 'ethers'
import { JsonRpcProvider } from '@ethersproject/providers'
import { getSigner } from './atomicTokenBridgeDeployer'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'

dotenv.config()

export const envVars = {
  baseChainRpc: process.env['BASECHAIN_RPC'] as string,
  baseChainDeployerKey: process.env['BASECHAIN_DEPLOYER_KEY'] as string,
}

// some contract address has to be provided as a constructor arg to TransparentUpgradeableProxy
const ARB_CONTRACT = '0x912CE59144191C1204E64559FE8253a0e49E6548'

/// gas/fee trackers
let totalGas = BigNumber.from(0)
let totalL1Gas = BigNumber.from(0)
let totalL2Gas = BigNumber.from(0)
let l2BaseFee = BigNumber.from(0)
let l1BaseFee = BigNumber.from(0)
let totalTxFees = BigNumber.from(0)

async function estimateContractDeployment(
  contractName: string,
  nodeInterface: NodeInterface,
  constructorArgs: any[] = []
): Promise<void> {
  const factory: ContractFactory = await ethers.getContractFactory(contractName)
  const gasEstimateComponents =
    await nodeInterface.callStatic.gasEstimateComponents(
      ethers.constants.AddressZero,
      true,
      factory.getDeployTransaction(...constructorArgs).data!,
      {
        blockTag: 'latest',
      }
    )

  _handleGasEstimates(gasEstimateComponents, contractName)
}

async function estimateUpgradeExecutorDeployment(
  nodeInterface: NodeInterface
): Promise<void> {
  const upgradeExecutorFac = await ethers.getContractFactory(
    UpgradeExecutorABI,
    UpgradeExecutorBytecode
  )
  const gasEstimateComponents =
    await nodeInterface.callStatic.gasEstimateComponents(
      ethers.constants.AddressZero,
      true,
      upgradeExecutorFac.getDeployTransaction().data!,
      {
        blockTag: 'latest',
      }
    )

  _handleGasEstimates(gasEstimateComponents, 'UpgradeExecutor')
}

async function estimateAll(signer: any) {
  const nodeInterface = NodeInterface__factory.connect(
    NODE_INTERFACE_ADDRESS,
    signer
  )

  await estimateContractDeployment('ArbMulticall2', nodeInterface)
  await estimateContractDeployment('ProxyAdmin', nodeInterface)
  await estimateContractDeployment(
    'L1AtomicTokenBridgeCreator',
    nodeInterface,
    [ethers.Wallet.createRandom().address]
  )
  await estimateContractDeployment(
    'TransparentUpgradeableProxy',
    nodeInterface,
    [ARB_CONTRACT, ethers.Wallet.createRandom().address, '0x']
  )
  await estimateContractDeployment(
    'L1TokenBridgeRetryableSender',
    nodeInterface
  )
  await estimateContractDeployment(
    'TransparentUpgradeableProxy',
    nodeInterface,
    [ARB_CONTRACT, ethers.Wallet.createRandom().address, '0x']
  )

  await estimateContractDeployment('L1GatewayRouter', nodeInterface)
  await estimateContractDeployment('L1ERC20Gateway', nodeInterface)
  await estimateContractDeployment('L1CustomGateway', nodeInterface)
  await estimateContractDeployment('L1WethGateway', nodeInterface)
  await estimateContractDeployment('L1OrbitGatewayRouter', nodeInterface)
  await estimateContractDeployment('L1OrbitERC20Gateway', nodeInterface)
  await estimateContractDeployment('L1OrbitCustomGateway', nodeInterface)
  await estimateUpgradeExecutorDeployment(nodeInterface)
  await estimateContractDeployment('L2AtomicTokenBridgeFactory', nodeInterface)
  await estimateContractDeployment('L2GatewayRouter', nodeInterface)
  await estimateContractDeployment('L2ERC20Gateway', nodeInterface)
  await estimateContractDeployment('L2CustomGateway', nodeInterface)
  await estimateContractDeployment('L2WethGateway', nodeInterface)
  await estimateContractDeployment('aeWETH', nodeInterface)
  await estimateContractDeployment('Multicall2', nodeInterface)
}

function _handleGasEstimates(
  gasEstimateComponents: [BigNumber, BigNumber, BigNumber, BigNumber] & {
    gasEstimate: BigNumber
    gasEstimateForL1: BigNumber
    baseFee: BigNumber
    l1BaseFeeEstimate: BigNumber
  },
  contractName: string
) {
  totalGas = totalGas.add(gasEstimateComponents.gasEstimate)
  totalL1Gas = totalL1Gas.add(gasEstimateComponents.gasEstimateForL1)
  totalL2Gas = totalL2Gas.add(
    gasEstimateComponents.gasEstimate.sub(
      gasEstimateComponents.gasEstimateForL1
    )
  )
  l2BaseFee = gasEstimateComponents.baseFee
  l1BaseFee = gasEstimateComponents.l1BaseFeeEstimate

  const P = l2BaseFee
  const L1P = l1BaseFee.mul(16)
  const l1Size = totalL1Gas.mul(P).div(L1P)
  const L1C = L1P.mul(l1Size)
  const B = L1C.div(P)
  const G = totalL2Gas.add(B)
  const TXFEES = P.mul(G)

  totalTxFees = totalTxFees.add(TXFEES)

  _printInfo(contractName, gasEstimateComponents, L1P, l1Size, TXFEES)
}

function _printInfo(
  contractName: String,
  gasEstimateComponents: [BigNumber, BigNumber, BigNumber, BigNumber] & {
    gasEstimate: BigNumber
    gasEstimateForL1: BigNumber
    baseFee: BigNumber
    l1BaseFeeEstimate: BigNumber
  },
  L1P: BigNumber,
  l1Size: BigNumber,
  TXFEES: BigNumber
) {
  console.log(contractName)
  console.log('  L1 gas: ' + gasEstimateComponents.gasEstimateForL1)
  console.log(
    '  L2 gas: ' +
      gasEstimateComponents.gasEstimate.sub(
        gasEstimateComponents.gasEstimateForL1
      )
  )
  console.log('  L1S (L1 Calldata size in bytes):', l1Size.toString(), 'bytes')
  console.log(
    '  Estimated fees to pay:',
    ethers.utils.formatEther(TXFEES),
    ' ETH'
  )
}

async function main() {
  const l1Provider = new JsonRpcProvider(envVars.baseChainRpc)
  const l1Deployer = getSigner(
    l1Provider,
    envVars.baseChainDeployerKey
  ) as Signer

  await estimateAll(l1Deployer)

  console.log('\n==========================================')
  console.log('Total gas:' + totalGas)
  console.log('  L1:' + totalL1Gas)
  console.log('  L2:' + totalL2Gas)

  console.log(
    'l1BaseFee: ' + ethers.utils.formatUnits(l1BaseFee, 'gwei'),
    'gwei'
  )
  console.log(
    'l2BaseFee: ' + ethers.utils.formatUnits(l2BaseFee, 'gwei'),
    'gwei'
  )

  console.log('Total TX fees = ', ethers.utils.formatEther(totalTxFees), 'ETH')
}

main().then(() => console.log('Done.'))
