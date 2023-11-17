import hre from 'hardhat'

/**
 * Contracts defined here are the ones for which cosntructor size check will be performed.
 *
 * The reason why we perform constructor size check is due to atomic token bridge creator
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
 * One exception is aeWETH, which has a constructor size of 348 bytes. This is because it
 * inhertis from 'aeERC20' which has 'initializer' modifier in its constructor. This modifier
 * will set the contract to the initialized state. When aeWETH is created on the child chain
 * there will be no constructor code invoked as mentioned earlier, so we do the initialization
 * of the logic contract explicitly in the child chain factory.
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

main().then(() => console.log('Constructor size check found no issues.'))

async function main() {
  for (const [contractName, expectedLength] of Object.entries(
    CONTRACTS_TO_EXPECTED_CONSTRUCTOR_SIZE
  )) {
    const constructorBytecode = await _getConstructorBytecode(contractName)
    const constructorBytecodeLength = _lengthInBytes(constructorBytecode)

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
  const creationCode = artifact.bytecode.substring(2)
  const runtimeCode = artifact.deployedBytecode.substring(2)

  if (!creationCode.includes(runtimeCode)) {
    throw new Error(
      `Error while extracting constructor bytecode for contract ${contractName}.`
    )
  }

  // extract the constructor code
  const constructorPrefix = creationCode.replace(runtimeCode, '')
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
