import { exec } from 'child_process'

export class ContractVerifier {
  chainId: number
  apiKey = ''

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

  async verifyWithAddress(
    name: string,
    contractAddress: string,
    constructorArgs?: string,
    _numOfOptimization?: number
  ): Promise<void> {
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

    console.log(`Verifying ${name} at ${contractAddress}...`)
    exec(command, (err: Error | null, stdout: string, stderr: string) => {
      if (err) {
        console.log('-----------------')
        console.log(
          ` * Contract ${name} at ${contractAddress} failed verification`,
          command,
          stderr
        )
        console.log('-----------------')
      } else {
        console.log(
          ` * Contract ${name} at ${contractAddress} was successfully verified`
        )
      }
    })
  }
}
