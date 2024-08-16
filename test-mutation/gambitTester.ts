import { exec } from 'child_process'
import { copyFileSync } from 'fs'
import { promisify } from 'util'
import os from 'os'
import * as path from 'path'
import * as fs from 'fs'
import * as fsExtra from 'fs-extra'
import { readdir } from 'node:fs/promises'

const GAMBIT_OUT = 'gambit_out/'
const CONTRACTS_DIR = 'contracts'
const TEST_ITEMS = [
  'contracts',
  'foundry.toml',
  'remappings.txt',
  'test-foundry',
]
const MAX_TASKS = Math.max(1, os.cpus().length - 2)

const execAsync = promisify(exec)
const symlink = promisify(fs.symlink)

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
  const startTime = Date.now()

  console.log('====== Generating mutants')
  const mutants: Mutant[] = await _generateMutants()

  console.log('\n====== Testing mutants')
  const results = await _testAllMutants(mutants)

  // Print summary
  console.log('\n====== Results\n')
  _printResults(results)

  // Delete test env
  await fsExtra.remove(path.join(__dirname, 'mutant_test_env'))

  // Print time testing took
  const endTime = Date.now()
  console.log(
    `\n====== Done in ${((endTime - startTime) / (60 * 1000)).toFixed(2)} min`
  )

  // Exit with non-zero if any mutants survived
  if (results.some(result => result.status === MutantStatus.SURVIVED)) {
    process.exit(1)
  }
}

async function _generateMutants(): Promise<Mutant[]> {
  await execAsync(`gambit mutate --json test-mutation/config.json`)
  const mutants: Mutant[] = JSON.parse(
    fs.readFileSync(`${GAMBIT_OUT}/gambit_results.json`, 'utf8')
  )
  console.log(`Generated ${mutants.length} mutants in ${GAMBIT_OUT}`)
  console.log('----------------------------------------------')
  console.log('Mutants overview:')
  console.log(fs.readFileSync(`${GAMBIT_OUT}/mutants.log`, 'utf8'))

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

  // copy necessary files
  for (const item of TEST_ITEMS) {
    const sourcePath = path.join(__dirname, '..', item)
    const destPath = path.join(testDirectory, item)
    await fsExtra.copy(sourcePath, destPath)
  }

  // link lib and node_modules
  await symlink(
    path.join(__dirname, '..', 'lib'),
    path.join(testDirectory, 'lib')
  )
  await symlink(
    path.join(__dirname, '..', 'node_modules'),
    path.join(testDirectory, 'node_modules')
  )

  // Replace original file with mutant
  copyFileSync(
    path.join(GAMBIT_OUT, mutant.name),
    path.join(testDirectory, mutant.original)
  )

  // Re-build and test
  let mutantStatus: MutantStatus
  try {
    await execAsync(`forge build --root ${testDirectory}`)
    await execAsync(
      `forge test --fail-fast --gas-limit 50000000 --no-match-contract AtomicTokenBridgeCreatorTest --root ${testDirectory}`
    )
    mutantStatus = MutantStatus.SURVIVED
  } catch (error) {
    mutantStatus = MutantStatus.KILLED
  }

  // delete test folder
  await fsExtra.remove(path.join(testDirectory))

  return {
    mutantId: mutant.id,
    fileName: path.basename(mutant.name),
    status: mutantStatus!,
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
    } else if (result.status === MutantStatus.SURVIVED) {
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

async function _generateConfigForGithubCI() {
  const solidityDirs = [
    path.join(__dirname, '../contracts/tokenbridge/ethereum'),
    path.join(__dirname, '../contracts/tokenbridge/arbitrum'),
    path.join(__dirname, '../contracts/tokenbridge/libraries'),
  ]
  const solidityFiles = await _findSolidityFiles(solidityDirs)

  console.log(solidityFiles)
}

async function _findSolidityFiles(directories: string[]): Promise<string[]> {
  const solidityFiles: string[] = []

  async function exploreDirectory(dir: string): Promise<void> {
    const entries = await fs.promises.readdir(dir, { withFileTypes: true })

    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name)
      if (entry.isDirectory()) {
        // Recursively explore subdirectory
        await exploreDirectory(fullPath)
      } else if (entry.isFile() && path.extname(fullPath) === '.sol') {
        // If it's a .sol file, add to the list
        solidityFiles.push(fullPath)
      }
    }
  }

  for (const directory of directories) {
    await exploreDirectory(directory)
  }

  return solidityFiles
}
