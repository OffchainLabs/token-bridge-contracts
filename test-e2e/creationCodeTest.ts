import hre, { ethers } from 'hardhat'
import { expect } from 'chai'
import { JsonRpcProvider } from '@ethersproject/providers'
import {
  CreationCodeTest,
  CreationCodeTest__factory,
  L1AtomicTokenBridgeCreator,
  L1AtomicTokenBridgeCreator__factory,
} from '../build/types'
import path from 'path'
import fs from 'fs'

const LOCALHOST_L2_RPC = 'http://localhost:8547'

const AE_WETH_EXPECTED_CONSTRUCTOR_SIZE = 348
const UPGRADE_EXECUTOR_EXPECTED_CONSTRUCTOR_SIZE = 242

let provider: JsonRpcProvider
let creationCodeTester: CreationCodeTest
let l1TokenBridgeCreator: L1AtomicTokenBridgeCreator

/**
 * This test ensures that the Solidity lib generates the same creation code as the
 * compiler for the contracts which are deployed to the child chain.
 *
 * The reason why we perform constructor check is due to atomic token bridge creator
 * implementation. Due to contract size limits, we deploy child chain templates to the
 * parent chain. When token bridge is being created, parent chain creator will fetch the
 * runtime bytecode of the templates and send it to the child chain via retryable tickets.
 * Child chain factory will then prepend the empty-constructor bytecode to the runtime code
 * and use resulting bytecode for deployment. That's why we need to ensure that those
 * impacted contracts don't have any logic in their constructors, as that logic can't be
 * executed when deploying to the child chain.
 *
 * All impacted contracts have 32 bytes of constructor bytecode which look like this:
 *   608060405234801561001057600080fd5b50615e7c806100206000396000f3fe
 * This constructor checks that there's no callvalue, copies the contract code to memory
 * and returns it. The only place where constructor bytecode differs between contracts
 * is in 61xxxx80 where xxxx is the length of the contract's bytecode.
 *
 * Exception are aeWETH and UpgradeExecutor contracts. Their constructors are not empty as they
 * contain logic to set the logic contract to the initialized state. In our system we need to
 * perform this initialization by chaild chain factory. It is important though that constructor
 * for these contracts never changes. That's why we check the constructor size matches the
 * expected hardcoded size.
 */
describe('creationCodeTest', () => {
  before(async function () {
    /// get default deployer params in local test env
    provider = new ethers.providers.JsonRpcProvider(LOCALHOST_L2_RPC)
    const deployerKey = ethers.utils.sha256(
      ethers.utils.toUtf8Bytes('user_token_bridge_deployer')
    )
    const deployer = new ethers.Wallet(deployerKey, provider)

    /// tester which implements the 'getCreationCode' lib function
    const testerFactory = await new CreationCodeTest__factory(deployer).deploy()
    creationCodeTester = await testerFactory.deployed()

    /// token bridge creator which has the templates stored
    l1TokenBridgeCreator = await _getTokenBridgeCreator(provider)
  })

  it('compiler generated and solidity lib generated creation code should match for L2 templates', async function () {
    expect(await _getCompilerGeneratedCreationCode('L2GatewayRouter')).to.be.eq(
      await _getSolidityLibGeneratedCreationCode(
        provider,
        creationCodeTester,
        await l1TokenBridgeCreator.l2RouterTemplate()
      )
    )

    expect(await _getCompilerGeneratedCreationCode('L2ERC20Gateway')).to.be.eq(
      await _getSolidityLibGeneratedCreationCode(
        provider,
        creationCodeTester,
        await l1TokenBridgeCreator.l2StandardGatewayTemplate()
      )
    )

    expect(await _getCompilerGeneratedCreationCode('L2CustomGateway')).to.be.eq(
      await _getSolidityLibGeneratedCreationCode(
        provider,
        creationCodeTester,
        await l1TokenBridgeCreator.l2CustomGatewayTemplate()
      )
    )

    expect(await _getCompilerGeneratedCreationCode('L2WethGateway')).to.be.eq(
      await _getSolidityLibGeneratedCreationCode(
        provider,
        creationCodeTester,
        await l1TokenBridgeCreator.l2WethGatewayTemplate()
      )
    )

    expect(await _getCompilerGeneratedCreationCode('ArbMulticall2')).to.be.eq(
      await _getSolidityLibGeneratedCreationCode(
        provider,
        creationCodeTester,
        await l1TokenBridgeCreator.l2MulticallTemplate()
      )
    )

    expect(
      await _getCompilerGeneratedCreationCode('L2AtomicTokenBridgeFactory')
    ).to.be.eq(
      await _getSolidityLibGeneratedCreationCode(
        provider,
        creationCodeTester,
        await l1TokenBridgeCreator.l2TokenBridgeFactoryTemplate()
      )
    )
  })

  it('aeWETH constructor has expected size', async function () {
    const constructorBytecode = await _getConstructorBytecode('aeWETH')
    const constructorBytecodeLength = _lengthInBytes(constructorBytecode)

    expect(constructorBytecodeLength).to.be.eq(
      AE_WETH_EXPECTED_CONSTRUCTOR_SIZE
    )
  })

  it('UpgradeExecutor constructor has expected size', async function () {
    const constructorBytecode = await _getConstructorBytecode('@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol:UpgradeExecutor')
    const constructorBytecodeLength = _lengthInBytes(constructorBytecode)

    expect(constructorBytecodeLength).to.be.eq(
      UPGRADE_EXECUTOR_EXPECTED_CONSTRUCTOR_SIZE
    )
  })
})

async function _getCompilerGeneratedCreationCode(
  contractName: string
): Promise<string> {
  //  get creation code generated by the compiler
  const artifact = await hre.artifacts.readArtifact(contractName)
  return artifact.bytecode
}

async function _getSolidityLibGeneratedCreationCode(
  provider: JsonRpcProvider,
  creationCodeTester: CreationCodeTest,
  templateAddress: string
) {
  const runtimeCode = await provider.getCode(templateAddress)
  const solidityLibGeneratedCreationCode =
    await creationCodeTester.creationCodeFor(runtimeCode)

  return solidityLibGeneratedCreationCode
}

async function _getTokenBridgeCreator(
  provider: JsonRpcProvider
): Promise<L1AtomicTokenBridgeCreator> {
  const localNetworkFile = path.join(__dirname, '..', 'network.json')
  if (!fs.existsSync(localNetworkFile)) {
    throw new Error("Can't find network.json file")
  }
  const data = JSON.parse(fs.readFileSync(localNetworkFile).toString())
  return L1AtomicTokenBridgeCreator__factory.connect(
    data['l1TokenBridgeCreator'],
    provider
  )
}

/**
 * Get constructor bytecode as a difference between creation and deployed bytecode
 * @param contractName
 * @returns
 */
async function _getConstructorBytecode(contractName: string): Promise<string> {
  const artifact = await hre.artifacts.readArtifact(contractName)

  // remove '0x'
  const creationCode = artifact.bytecode.substring(2)
  const runtimeCode = artifact.deployedBytecode.substring(2)

  if (!creationCode.includes(runtimeCode)) {
    throw new Error(
      `Error while extracting constructor bytecode for contract ${contractName}.`
    )
  }

  // extract the constructor code
  return creationCode.replace(runtimeCode, '')
}

/**
 * Every byte in the constructor bytecode is represented by 2 characters in hex
 * @param hex
 * @returns
 */
function _lengthInBytes(hex: string): number {
  return hex.length / 2
}
