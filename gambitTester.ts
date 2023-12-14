import { execSync } from 'child_process'
import { existsSync, readdirSync, copyFileSync, unlinkSync } from 'fs'
import * as path from 'path'

const contractPath = 'contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol'
const mutantsDirectory = 'gambit_out/mutants'

runMutationTesting().catch(error => {
  console.error('Error during mutation testing:', error)
})

async function runMutationTesting() {
  // Step 1: Generate mutants
  execSync(
    `gambit mutate --solc_remappings "@openzeppelin=node_modules/@openzeppelin" "@arbitrum=node_modules/@arbitrum" -f ${contractPath}`
  )

  // Check if mutants directory exists
  if (!existsSync(mutantsDirectory)) {
    throw new Error('Mutants directory not found after running gambit mutate')
  }

  // Step 2: Loop through mutants
  const mutantDirs = readdirSync(mutantsDirectory)
  const results = []

  for (const dir of mutantDirs) {
    const mutantPath = path.join(mutantsDirectory, dir, contractPath)
    if (existsSync(mutantPath)) {
      console.log(`Testing mutant: ${mutantPath}`)

      // Replace original file with mutant
      copyFileSync(mutantPath, contractPath)

      // Step 3: Re-build project
      execSync('forge build')

      // Step 4: Run test suite
      try {
        execSync('forge test')
        results.push({ mutant: mutantPath, status: 'Survived' })
      } catch (error) {
        results.push({ mutant: mutantPath, status: 'Killed' })
      }

      // Restore original file
      unlinkSync(contractPath)
    }
  }

  // Step 5: Print summary
  console.log('Mutation Testing Results:')
  results.forEach(result => {
    console.log(`${result.mutant}: ${result.status}`)
  })
}
