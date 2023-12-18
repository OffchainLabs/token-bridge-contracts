import { exec } from 'child_process'
import { copyFileSync } from 'fs'
import { promisify } from 'util'
import os from 'os'
import * as path from 'path'
import * as fs from 'fs'
import * as fsExtra from 'fs-extra'

const GAMBIT_OUT = 'gambit_out/'
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
  const mutants: Mutant[] = await _generateMutants()

  console.log('\n====== Test mutants')
  const results = await _testAllMutants(mutants)

  // Print summary
  console.log('\n====== Results\n')
  _printResults(results)

  // Delete test env
  await fsExtra.remove(path.join(__dirname, 'mutant_test_env'))
}

async function _generateMutants(): Promise<Mutant[]> {
  await execAsync(`gambit mutate --json test-mutation/config.json`)
  const mutants: Mutant[] = JSON.parse(
    fs.readFileSync(`${GAMBIT_OUT}/gambit_results.json`, 'utf8')
  )
  console.log(`Generated ${mutants.length} mutants in ${GAMBIT_OUT}`)

  return mutants
}

async function _testAllMutants(mutants: Mutant[]): Promise<TestResult[]> {
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
    path.join(GAMBIT_OUT, mutant.name),
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
  console.log('Mutant ID | File Name            | Status   ')
  console.log(separator)

  let lastFileName = ''
  let killedCount = 0
  let survivedCount = 0

  /// print table and count stats
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

    if (result.status === MutantStatus.KILLED) {
      killedCount++
    } else {
      survivedCount++
    }
  })

  // print totals
  const totalCount = results.length
  const killedPercentage = ((killedCount / totalCount) * 100).toFixed(2)
  const survivedPercentage = ((survivedCount / totalCount) * 100).toFixed(2)

  console.log(separator)
  console.log(`Total Mutants: ${totalCount}`)
  console.log(`Killed: ${killedCount} (${killedPercentage}%)`)
  console.log(`Survived: ${survivedCount} (${survivedPercentage}%)`)
}
