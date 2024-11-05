import * as path from 'path'
import * as fs from 'fs'

const NUM_OF_MUTANTS_PER_FILE = 4
const CONFIG_FOR_CI_FILE = 'config_for_github_ci.json'

genGambitConfigForCI().catch(error => {
  console.error('Error while generating Galbit config for CI:', error)
})

async function genGambitConfigForCI() {
  // Generate the JSON config file to config_for_github_ci.json
  await _generateConfigForGithubCI()

  // Move config to config.json
  const src = path.join(__dirname, CONFIG_FOR_CI_FILE)
  const dest = path.join(__dirname, 'config.json')
  await fs.promises.rename(src, dest)
  console.log(`Moved ${src} to ${dest}`)
}

async function _generateConfigForGithubCI() {
  const solidityDirs = [
    path.join(__dirname, '../contracts/tokenbridge/ethereum'),
    path.join(__dirname, '../contracts/tokenbridge/arbitrum'),
    path.join(__dirname, '../contracts/tokenbridge/libraries'),
  ]
  const solidityFiles = await _findSolidityFiles(solidityDirs)

  // Construct the JSON array
  const jsonConfig = solidityFiles.map(file => ({
    filename: file,
    sourceroot: '..',
    solc_remappings: [
      '@openzeppelin=../node_modules/@openzeppelin',
      '@arbitrum=../node_modules/@arbitrum',
    ],
    num_mutants: NUM_OF_MUTANTS_PER_FILE,
    random_seed: true,
  }))

  // Write the result to a JSON file
  const outputFilePath = path.join(__dirname, CONFIG_FOR_CI_FILE)
  await fs.promises.writeFile(
    outputFilePath,
    JSON.stringify(jsonConfig, null, 2),
    'utf-8'
  )
  console.log(`Generated JSON file: ${outputFilePath}`)
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
        const relativePath = path.relative(__dirname, fullPath)
        solidityFiles.push(relativePath)
      }
    }
  }

  for (const directory of directories) {
    await exploreDirectory(directory)
  }

  return solidityFiles
}
