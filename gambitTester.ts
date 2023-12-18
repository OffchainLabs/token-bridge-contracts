import { exec } from 'child_process'
import { copyFileSync } from 'fs'
import { promisify } from 'util'
import os from 'os'
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
const MAX_TASKS = os.cpus().length
const execAsync = promisify(exec)

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

runMutationTesting().catch(error => {
  console.error('Error during mutation testing:', error)
})

async function runMutationTesting() {
  // generate mutants
  await execAsync(
    `gambit mutate --solc_remappings "@openzeppelin=node_modules/@openzeppelin" "@arbitrum=node_modules/@arbitrum" -f ${contractPath}`
  )

  // test mutants
  const mutants: Mutant[] = JSON.parse(fs.readFileSync(mutantsListFile, 'utf8'))
  const results: TestResult[] = []
  for (let i = 0; i < mutants.length; i += MAX_TASKS) {
    const currentBatch = mutants.slice(i, i + MAX_TASKS)
    const batchPromises = currentBatch.map(mutant => {
      return testMutant(mutant)
    })

    // Wait for the current batch of tests to complete
    const batchResults = await Promise.all(batchPromises)
    console.log('Batch results:', batchResults)
    results.push(...batchResults)
  }

  // Print summary
  console.log('Mutation Testing Results:')
  results.forEach(result => {
    console.log(`${result.mutant}: ${result.status}`)
  })
}

async function testMutant(mutant: Mutant): Promise<TestResult> {
  const testDirectory = path.join(__dirname, `test_mutant`, mutant.id)

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
    console.log(`Building and testing mutant ${mutant.id} in ${testDirectory}`)
    await execAsync(`forge build --root ${testDirectory}`)
    await execAsync(`forge test --root ${testDirectory}`)
    return { mutant: mutant.id, status: 'Survived' }
  } catch (error) {
    return { mutant: mutant.id, status: 'Killed' }
  }
}
