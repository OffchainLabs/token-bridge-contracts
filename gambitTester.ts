import { execSync } from 'child_process'
import { copyFileSync, unlinkSync } from 'fs'
import * as path from 'path'
import * as fs from 'fs'
import * as fsExtra from 'fs-extra'

const contractPath = 'contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol'
const gambitDir = 'gambit_out/'
const mutantsListFile = 'gambit_out/gambit_results.json'
const testItems = [
  'contracts',
  'lib',
  'foundry.toml',
  'node_modules',
  'remappings.txt',
  'test-foundry',
]

interface Mutant {
  description: string
  diff: string
  id: string
  name: string
  original: string
  sourceroot: string
}
interface TestResult {
  mutant: string
  status: string
}

const testResults: TestResult[] = []

runMutationTesting().catch(error => {
  console.error('Error during mutation testing:', error)
})

async function runMutationTesting() {
  // generate mutants
  execSync(
    `gambit mutate -n 3 --solc_remappings "@openzeppelin=node_modules/@openzeppelin" "@arbitrum=node_modules/@arbitrum" -f ${contractPath}`
  )

  // read mutants
  const mutants: Mutant[] = JSON.parse(fs.readFileSync(mutantsListFile, 'utf8'))

  // test mutants
  for (const mutant of mutants) {
    testMutant(mutant)
  }

  // Print summary
  console.log('Mutation Testing Results:')
  testResults.forEach(result => {
    console.log(`${result.mutant}: ${result.status}`)
  })
}

async function testMutant(mutant: Mutant) {
  const testDirectory = path.join(__dirname, `test_mutant`, mutant.id)

  console.log(`Testing mutant: ${mutant.id} in ${testDirectory}`)

  await fsExtra.ensureDir(testDirectory)
  for (const item of testItems) {
    const sourcePath = path.join(__dirname, item)
    const destPath = path.join(testDirectory, item)
    await fsExtra.copy(sourcePath, destPath)
  }

  // Replace original file with mutant
  copyFileSync(
    path.join(gambitDir, mutant.name),
    path.join(testDirectory, mutant.original)
  )

  // Re-build and test
  try {
    execSync(`forge build --root ${testDirectory}`)
    execSync(`forge test --root ${testDirectory}`)
    testResults.push({ mutant: mutant.id, status: 'Survived' })
  } catch (error) {
    testResults.push({ mutant: mutant.id, status: 'Killed' })
  }
}
