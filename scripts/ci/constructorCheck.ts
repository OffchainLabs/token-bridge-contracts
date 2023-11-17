import hre from 'hardhat'

/**
 * Contracts defined here are the one for which cosntructor size check will be performed.
 */
export const CONTRACTS_TO_EXPECTED_CONSTRUCTOR_SIZE: Record<string, number> = {
  L2AtomicTokenBridgeFactory: 32,
  ArbMulticall2: 32,
  L2GatewayRouter: 32,
  L2ERC20Gateway: 32,
  L2CustomGateway: 32,
  L2WethGateway: 32,
  aeWETH: 348,
}

main().then(() => console.log('Done.'))

async function main() {
  for (const [contractName, expectedLength] of Object.entries(
    CONTRACTS_TO_EXPECTED_CONSTRUCTOR_SIZE
  )) {
    // Extracting the constructor prefix
    const constructorBytecode = await _getConstructorBytecode(contractName)
    const constructorBytecodeLength = _lengthInBytes(constructorBytecode)

    console.log(
      `Constructor length of ${contractName} is ${constructorBytecodeLength} bytes, expected ${expectedLength} bytes.`
    )

    if (constructorBytecodeLength !== expectedLength) {
      throw new Error(
        `Constructor length of ${contractName} is ${constructorBytecodeLength} bytes, expected ${expectedLength} bytes.`
      )
    }
  }
}

/**
 * Get constructor bytecode as a difference between creation and deployed bytecode
 * @param contractName
 * @returns
 */
async function _getConstructorBytecode(contractName: string): Promise<string> {
  const artifact = await hre.artifacts.readArtifact(contractName)

  // remove '0x'
  const completeBytecode = artifact.bytecode.substring(2)
  const deployedBytecode = artifact.deployedBytecode.substring(2)

  // extract the constructor prefix
  const constructorPrefix = completeBytecode.replace(deployedBytecode, '')
  return constructorPrefix
}

/**
 * Every byte in the constructor bytecode is represented by 2 characters in hex
 * @param hex
 * @returns
 */
function _lengthInBytes(hex: string): number {
  return hex.length / 2
}
