const config = {
  "defaultNetwork": "hardhat",
  "paths": {
    "artifacts": "build/contracts"
  },
  "solidity": {
    "compilers": [
      {
        "version": "0.6.11",
        "settings": {
          "optimizer": {
            "enabled": true,
            "runs": 100
          }
        }
      },
      {
        "version": "0.8.7",
        "settings": {
          "optimizer": {
            "enabled": true,
            "runs": 100
          }
        }
      }
    ],
    "overrides": {}
  }
}

// this env variable can be used to set the path to which hardhat artifacts are written to
// its useful when consuming this externally as a library
if (process.env['HARDHAT_ARTIFACT_PATH'])
  config.paths.artifacts = process.env['HARDHAT_ARTIFACT_PATH']

module.exports = config
