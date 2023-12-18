import { exec } from 'child_process'
import { copyFileSync } from 'fs'
import { promisify } from 'util'
import os from 'os'
import * as path from 'path'
import * as fs from 'fs'
import * as fsExtra from 'fs-extra'

const gambitDir = 'gambit_out/'
const mutantsListFile = 'gambit_out/gambit_results.json'
const testItems = [
  'contracts',
  'lib',
  'foundry.toml',
  'remappings.txt',
  'test-foundry',
  'node_modules/@openzeppelin',
  'node_modules/@arbitrum',
  'node_modules/@offchainlabs',
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
  mutantId: string
  fileName: string
  status: MutantStatus
}
enum MutantStatus {
  KILLED = 'KILLED',
  SURVIVED = 'SURVIVED',
}

runMutationTesting().catch(error => {
  console.error('Error during mutation testing:', error)
})

async function runMutationTesting() {
  console.log('====== Generating mutants')
  await _generateMutants()

  console.log('\n====== Test mutants')
  const results = await _testAllMutants()

  // Print summary
  console.log('\n====== Results\n')
  _printResults(results)

  // Delete test env
  await fsExtra.remove(path.join(__dirname, 'mutant_test_env'))
}

async function _generateMutants() {
  await execAsync(`gambit mutate --json test-mutation/config.json`)
}

async function _testAllMutants(): Promise<TestResult[]> {
  const mutants: Mutant[] = JSON.parse(fs.readFileSync(mutantsListFile, 'utf8'))
  const results: TestResult[] = []
  for (let i = 0; i < mutants.length; i += MAX_TASKS) {
    const currentBatch = mutants.slice(i, i + MAX_TASKS)
    console.log(`Testing mutant batch ${i}..${i + MAX_TASKS}`)

    const batchPromises = currentBatch.map(mutant => {
      return _testMutant(mutant)
    })

    // Wait for the current batch of tests to complete
    const batchResults = await Promise.all(batchPromises)
    results.push(...batchResults)
  }

  return results
}

async function _testMutant(mutant: Mutant): Promise<TestResult> {
  const testDirectory = path.join(__dirname, `mutant_test_env`, mutant.id)

  await fsExtra.ensureDir(testDirectory)
  for (const item of testItems) {
    const sourcePath = path.join(__dirname, '..', item)
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
    await execAsync(`forge build --root ${testDirectory}`)
    await execAsync(`forge test --root ${testDirectory}`)
    return {
      mutantId: mutant.id,
      fileName: path.basename(mutant.name),
      status: MutantStatus.SURVIVED,
    }
  } catch (error) {
    return {
      mutantId: mutant.id,
      fileName: path.basename(mutant.name),
      status: MutantStatus.KILLED,
    }
  }
}

function _printResults(results: TestResult[]) {
  const separator = '----------------------------------------------'
  console.log('Mutant ID | File Name             | Status   ')
  console.log(separator)

  let lastFileName = ''
  results.forEach(result => {
    if (result.fileName !== lastFileName) {
      console.log(separator)
      lastFileName = result.fileName
    }
    console.log(
      `${result.mutantId.padEnd(9)} | ${result.fileName.padEnd(20)} | ${
        result.status
      }`
    )
  })
}
