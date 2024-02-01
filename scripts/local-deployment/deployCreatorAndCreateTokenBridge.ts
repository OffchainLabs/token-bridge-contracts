import * as fs from 'fs'
import { setupTokenBridgeInLocalEnv } from './localDeploymentLib'

async function main() {
  const {
    l1Network,
    l2Network,
    l1TokenBridgeCreatorAddress: l1TokenBridgeCreator,
    retryableSenderAddress: retryableSender,
  } = await setupTokenBridgeInLocalEnv()

  const NETWORK_FILE = 'network.json'
  fs.writeFileSync(
    NETWORK_FILE,
    JSON.stringify(
      { l1Network, l2Network, l1TokenBridgeCreator, retryableSender },
      null,
      2
    )
  )
  console.log(NETWORK_FILE + ' updated')
}

main().then(() => console.log('Done.'))
