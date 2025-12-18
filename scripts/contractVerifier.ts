import { exec } from 'child_process'
import { BigNumber, ethers, Signer } from 'ethers'

type VerificationRequest = {
  signer: Signer
  contractName: string
  contractAddress: string
  constructorArguments: any[]
}

// Helper function to encode constructor arguments based on their types
function abiEncodeConstructorArguments(args: any[]): string {
  if (args.length === 0) return ''

  // Infer types from the arguments
  const types: string[] = args.map(arg => {
    if (typeof arg === 'string' && arg.match(/^0x[a-fA-F0-9]{40}$/)) {
      return 'address'
    } else if (typeof arg === 'string' && arg.match(/^0x[a-fA-F0-9]*$/)) {
      return 'bytes'
    } else if (typeof arg === 'string') {
      return 'string'
    } else if (typeof arg === 'number' || BigNumber.isBigNumber(arg)) {
      return 'uint256'
    } else if (typeof arg === 'boolean') {
      return 'bool'
    } else if (Array.isArray(arg)) {
      // For arrays, detect the inner type from first element
      if (arg.length > 0) {
        const innerType =
          typeof arg[0] === 'string' && arg[0].match(/^0x[a-fA-F0-9]{40}$/)
            ? 'address'
            : 'string'
        return `${innerType}[]`
      }
      return 'string[]' // fallback
    }
    return 'bytes32' // fallback for unknown types
  })

  const abi = ethers.utils.defaultAbiCoder
  return abi.encode(types, args)
}

export class ContractVerifier {
  chainId: number
  apiKey = ''
  verificationQueue: VerificationRequest[] = []

  readonly NUM_OF_OPTIMIZATIONS = 100
  readonly COMPILER_VERSION = '0.8.16'

  ///// List of contract addresses and their corresponding source code files
  readonly TUP =
    'node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy'
  readonly PROXY_ADMIN =
    'node_modules/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin'
  readonly EXECUTOR =
    'node_modules/@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol:UpgradeExecutor'

  readonly contractToSource = {
    ProxyAdmin: this.PROXY_ADMIN,
    TransparentUpgradeableProxy: this.TUP,
    UpgradeExecutor: this.EXECUTOR,
    L1AtomicTokenBridgeCreator:
      'contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol:L1AtomicTokenBridgeCreator',
    L1TokenBridgeRetryableSender:
      'contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol:L1TokenBridgeRetryableSender',
    L1GatewayRouter:
      'contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol:L1GatewayRouter',
    L1ERC20Gateway:
      'contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol:L1ERC20Gateway',
    L1CustomGateway:
      'contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol:L1CustomGateway',
    L1WethGateway:
      'contracts/tokenbridge/ethereum/gateway/L1WethGateway.sol:L1WethGateway',
    L1OrbitGatewayRouter:
      'contracts/tokenbridge/ethereum/gateway/L1OrbitGatewayRouter.sol:L1OrbitGatewayRouter',
    L1OrbitERC20Gateway:
      'contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol:L1OrbitERC20Gateway',
    L1OrbitCustomGateway:
      'contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol:L1OrbitCustomGateway',
    L2AtomicTokenBridgeFactory:
      'contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol:L2AtomicTokenBridgeFactory',
    L2GatewayRouter:
      'contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol:L2GatewayRouter',
    L2ERC20Gateway:
      'contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol:L2ERC20Gateway',
    L2CustomGateway:
      'contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol:L2CustomGateway',
    L2WethGateway:
      'contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol:L2WethGateway',
    AeWETH: 'contracts/tokenbridge/libraries/aeWETH.sol:aeWETH',
    ArbMulticall2: 'contracts/rpc-utils/MulticallV2.sol:ArbMulticall2',
    Multicall2: 'contracts/rpc-utils/MulticallV2.sol:Multicall2',
  }

  constructor(chainId: number, apiKey: string) {
    this.chainId = chainId
    if (apiKey) {
      this.apiKey = apiKey
    }
  }

  queueContractForVerification(
    signer: Signer,
    contractName: string,
    contractAddress: string,
    constructorArguments: any[] = []
  ): void {
    this.verificationQueue.push({
      signer,
      contractName,
      contractAddress,
      constructorArguments,
    })
  }

  async verifyAllQueuedContracts(): Promise<void> {
    if (this.verificationQueue.length === 0) {
      return
    }

    if (!process.env.ARBISCAN_API_KEY) {
      console.warn(
        'ARBISCAN_API_KEY is not set. Skipping contract verification.'
      )
      this.verificationQueue = [] // Clear queue
      return
    }

    console.log()
    console.log(`=== Verification of contracts ===`)

    for (let i = 0; i < this.verificationQueue.length; i++) {
      const request = this.verificationQueue[i]
      await this.verifyContract(
        request.signer,
        request.contractName,
        request.contractAddress,
        request.constructorArguments
      )

      // Add a small delay between verifications to avoid rate limiting
      if (i < this.verificationQueue.length - 1) {
        await new Promise(resolve => setTimeout(resolve, 1000))
      }
    }

    // Clear the queue after processing
    this.verificationQueue = []

    // Allow a few seconds for all pending verifications to complete
    await new Promise(resolve => setTimeout(resolve, 3000))
  }

  async verifyContract(
    signer: Signer,
    contractName: string,
    contractAddress: string,
    constructorArguments: any[] = []
  ): Promise<void> {
    const contractVerifier = new ContractVerifier(
      (await signer.provider!.getNetwork()).chainId,
      process.env.ARBISCAN_API_KEY!
    )

    // Encode constructor arguments if provided
    const encodedConstructorArgs =
      abiEncodeConstructorArguments(constructorArguments)

    await contractVerifier.verifyWithAddress(
      contractName,
      contractAddress,
      encodedConstructorArgs
    )
  }

  async verifyWithAddress(
    name: string,
    contractAddress: string,
    constructorArgs?: string,
    _numOfOptimization?: number
  ): Promise<void> {
    // avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 1000))

    let command = `forge verify-contract --chain-id ${this.chainId} --compiler-version ${this.COMPILER_VERSION}`

    if (_numOfOptimization !== undefined) {
      command = `${command} --num-of-optimizations ${_numOfOptimization}`
    } else {
      command = `${command} --num-of-optimizations ${this.NUM_OF_OPTIMIZATIONS}`
    }

    const sourceFile =
      this.contractToSource[name as keyof typeof this.contractToSource]

    if (constructorArgs) {
      command = `${command} --constructor-args ${constructorArgs}`
    }
    command = `${command} ${contractAddress} ${sourceFile} --etherscan-api-key ${this.apiKey}`

    exec(command, (err: Error | null, stdout: string, stderr: string) => {
      console.log('-----------------')
      console.log(command)
      if (err) {
        console.log(
          'Failed to submit for verification',
          contractAddress,
          stderr
        )
      } else {
        console.log('Successfully submitted for verification', contractAddress)
      }
    })
  }
}
