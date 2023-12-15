import { execSync } from 'child_process'
import { existsSync, readdirSync, copyFileSync, unlinkSync } from 'fs'
import * as path from 'path'
import * as fs from 'fs'

const contractPath = 'contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol'
const gambitDir = 'gambit_out/'
const mutantsListFile = 'gambit_out/gambit_results.json'

interface Mutant {
  description: string
  diff: string
  id: string
  name: string
  original: string
  sourceroot: string
}

runMutationTesting().catch(error => {
  console.error('Error during mutation testing:', error)
})

async function runMutationTesting() {
  // Step 1: Generate mutants
  execSync(
    `gambit mutate -n 3 --solc_remappings "@openzeppelin=node_modules/@openzeppelin" "@arbitrum=node_modules/@arbitrum" -f ${contractPath}`
  )

  // read mutants
  const mutants: Mutant[] = JSON.parse(fs.readFileSync(mutantsListFile, 'utf8'))

  // test mutants
  const results = []
  for (const mutant of mutants) {
    console.log(`Testing mutant: ${mutant.id}`)

    // Replace original file with mutant
    copyFileSync(path.join(gambitDir, mutant.name), mutant.original)

    // Re-build and test
    try {
      execSync('forge build')
      execSync('forge test')
      results.push({ mutant: mutant.id, status: 'Survived' })
    } catch (error) {
      results.push({ mutant: mutant.id, status: 'Killed' })
    }

    // Restore original file
    unlinkSync(contractPath)
  }

  // Print summary
  console.log('Mutation Testing Results:')
  results.forEach(result => {
    console.log(`${result.mutant}: ${result.status}`)
  })
}
