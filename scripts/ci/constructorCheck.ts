import * as fs from 'fs'
import * as path from 'path'

const projectRoot = path.join(__dirname, '../../')
const artifactsDir = path.join(
  projectRoot,
  'build',
  'contracts',
  'contracts',
  'tokenbridge',
  'arbitrum',
  'gateway'
)

const contractName = 'L2GatewayRouter'

const artifactPath = path.join(
  artifactsDir,
  `${contractName}.sol`,
  `${contractName}.json`
)

// Read the artifact file
const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))

// remove '0x' prefix
const completeBytecode = artifact.bytecode.substring(2)
const deployedBytecode = artifact.deployedBytecode.substring(2)

// Extracting the constructor prefix
const constructorPrefix = completeBytecode.replace(deployedBytecode, '')

console.log('Constructor Prefix:', constructorPrefix)
