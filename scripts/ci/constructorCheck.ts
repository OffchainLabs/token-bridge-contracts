import hre from 'hardhat'

main().then(() => console.log('Done.'))

async function main() {
  const contractName = 'L2GatewayRouter'

  // Extracting the constructor prefix
  const constructorBytecode = await _getConstructorBytecode(contractName)

  console.log('Constructor code:', constructorBytecode)
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
