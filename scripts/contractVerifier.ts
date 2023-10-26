import { exec } from 'child_process'
import { ethers } from 'ethers'

export class ContractVerifier {
  chainId: number
  apiKey: string = ''

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
    l1TokenBridgeCreatorProxyAdmin: this.PROXY_ADMIN,
    l1TokenBridgeCreatorLogic:
      'contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol:L1AtomicTokenBridgeCreator',
    l1TokenBridgeCreatorProxy: this.TUP,
    retryableSenderLogic:
      'contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol:L1TokenBridgeRetryableSender',
    retryableSenderProxy: this.TUP,
    routerTemplate:
      'contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol:L1GatewayRouter',
    standardGatewayTemplate:
      'contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol:L1ERC20Gateway',
    customGatewayTemplate:
      'contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol:L1CustomGateway',
    wethGatewayTemplate:
      'contracts/tokenbridge/ethereum/gateway/L1WethGateway.sol:L1WethGateway',
    feeTokenBasedRouterTemplate:
      'contracts/tokenbridge/ethereum/gateway/L1OrbitGatewayRouter.sol:L1OrbitGatewayRouter',
    feeTokenBasedStandardGatewayTemplate:
      'contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol:L1OrbitERC20Gateway',
    feeTokenBasedCustomGatewayTemplate:
      'contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol:L1OrbitCustomGateway',
    upgradeExecutor: this.EXECUTOR,
    l2TokenBridgeFactoryOnL1:
      'contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol:L2AtomicTokenBridgeFactory',
    l2GatewayRouterOnL1:
      'contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol:L2GatewayRouter',
    l2StandardGatewayAddressOnL1:
      'contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol:L2ERC20Gateway',
    l2CustomGatewayAddressOnL1:
      'contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol:L2CustomGateway',
    l2WethGatewayAddressOnL1:
      'contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol:L2WethGateway',
    l2WethAddressOnL1: 'contracts/tokenbridge/libraries/aeWETH.sol:aeWETH',
    l2MulticallAddressOnL1: 'contracts/rpc-utils/MulticallV2.sol:ArbMulticall2',
    l1Multicall: 'contracts/rpc-utils/MulticallV2.sol:Multicall2',
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
  ) {
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
