import { task } from "hardhat/config";
import { ethers } from "ethers";
import "@nomiclabs/hardhat-etherscan"
import { Bytecode } from "@nomiclabs/hardhat-etherscan/dist/src/solc/bytecode"
import { TASK_VERIFY_GET_CONTRACT_INFORMATION, TASK_VERIFY_GET_COMPILER_VERSIONS, TASK_VERIFY_GET_LIBRARIES } from "@nomiclabs/hardhat-etherscan/dist/src/constants"
import fs from "fs";

task("compareBytecode", "Compares deployed bytecode with local builds")
    .addParam("contractAddrs", "A comma-separated list of deployed contract addresses")
    .setAction(async ({ contractAddrs }, hre) => {
        const addresses = contractAddrs.split(',');

        // Get all local contract artifact paths
        const artifactPaths = await hre.artifacts.getArtifactPaths();

        for (const contractAddr of addresses) {

            // Fetch deployed contract bytecode
            const deployedBytecode = await hre.ethers.provider.getCode(contractAddr.trim());
            const deployedCodeHash = ethers.utils.keccak256(deployedBytecode);
            let matchFound = false;

            for (const artifactPath of artifactPaths) {
                const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
                if (artifact.deployedBytecode) {
                    const localCodeHash = ethers.utils.keccak256(artifact.deployedBytecode);

                    // Compare codehashes
                    if (deployedCodeHash === localCodeHash) {
                        console.log(`Contract Address ${contractAddr.trim()} matches with ${artifact.contractName}`);
                        matchFound = true;
                        break;
                    }
                }
            }

            if (!matchFound) {
                const deployedBytecodeHex = deployedBytecode.startsWith("0x")
                    ? deployedBytecode.slice(2)
                    : deployedBytecode;
                try {
                    const info = await hre.run(TASK_VERIFY_GET_CONTRACT_INFORMATION, {
                        deployedBytecode: new Bytecode(deployedBytecodeHex),
                        matchingCompilerVersions: await hre.run(
                            TASK_VERIFY_GET_COMPILER_VERSIONS
                        ),
                        libraries: await hre.run(TASK_VERIFY_GET_LIBRARIES),
                    })
                    console.log(`Contract Address ${contractAddr.trim()} matches with ${info.contractName} without checking constructor arguments`);
                } catch (error) {
                    console.log(`No matching contract found for address ${contractAddr.trim()}`);
                }
            }
        }
    });

export default {};
