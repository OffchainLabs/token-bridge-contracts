# Mutation testing using Certora's Gambit framework

[Gambit tool](https://docs.certora.com/en/latest/docs/gambit/gambit.html) takes Solidity file or list of files as input and it will generate "mutants" as output. Those are copies of original file, but each with an atomic modification of original file, ie. flipped operator, mutated 'if' condition etc. Next step is running the test suite against the mutant. If all tests still pass, mutant survived, that's bad - either there's faulty test or there is missing coverage. If some test(s) fail, mutant's been killed, that's good.

## How to install Gambit
To build from source (assumes Rust and Cargo are installed), clone the Gambit repo
```
git clone git@github.com:Certora/gambit.git
```

Then run
```
cargo install --path .
```

Alternatively, prebuilt binaries can be used - more info [here](https://docs.certora.com/en/latest/docs/gambit/gambit.html#installation).


## Using Gambit
CLI command `gambit mutate` is used to generated mutants. It can take single file as an input, ie. let's say we want to generate mutants for file `L1ERC20Gateway.sol`:
```
gambit mutate --solc_remappings "@openzeppelin=node_modules/@openzeppelin" "@arbitrum=node_modules/@arbitrum" -f contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol
```

Command will output `gambit_out` folder containing list of mutants (modified Solidity files) and `gambit_results.json` which contains info about all the generated mutants. Another way to view the mutant info is to run:
```
gambit summary
```

Gambit can also take set of Solidity files as input in JSON format, ie:
```
gambit mutate --json test-mutation/config.json
```

List of all configuration options for the JSON file can be found [here](https://docs.certora.com/en/latest/docs/gambit/gambit.html#configuration-files).  
  
Gambit only generates the mutants, it will not execute any tests. To check if mutant gets killed or survives, we need to copy modified Solidity file over the original one, re-compile the project and re-run the test suite. This process has been automated and described in next chapter.

## Gambit integration with Foundry
To get the most benefits from Gambit, we have integrated it with Foundry and automated testing and reporting process. This is how `gambitTester` script works:
- generates mutants for files specified in test-mutation/config.json
- for each mutant do in parallel (in batches):
    - replace original file with mutant
    - re-compile and run foundry suite
    - track results
- report results
  
Here are practical steps to run mutation test over the set of Arbitrum token bridge contracts. First we need to update `test-mutation/config.json` with the list of solidity files to be tested. In this case we use config file that was prepared in advance:
```
cp test-mutation/all-configs/config.tokenbridge-ethereum.json test-mutation/config.json
``` 

Now run the script, it will generate mutants and start compiling/testing them in parallel:
```
yarn run test:mutation
```

It will take some time for script to execute (depends on the underlying HW).

Script output looks like this:
```
❯ yarn run test:mutation

yarn run v1.22.19
$ ts-node test-mutation/gambitTester.ts
====== Generating mutants
Generated 209 mutants in gambit_out/

====== Test mutants
Testing mutant batch 0..7
Testing mutant batch 7..14
Testing mutant batch 14..21
Testing mutant batch 21..28
Testing mutant batch 28..35
Testing mutant batch 35..42
Testing mutant batch 42..49
Testing mutant batch 49..56
Testing mutant batch 56..63
Testing mutant batch 63..70
Testing mutant batch 70..77
Testing mutant batch 77..84
Testing mutant batch 84..91
Testing mutant batch 91..98
Testing mutant batch 98..105
Testing mutant batch 105..112
Testing mutant batch 112..119
Testing mutant batch 119..126
Testing mutant batch 126..133
Testing mutant batch 133..140
Testing mutant batch 140..147
Testing mutant batch 147..154
Testing mutant batch 154..161
Testing mutant batch 161..168
Testing mutant batch 168..175
Testing mutant batch 175..182
Testing mutant batch 182..189
Testing mutant batch 189..196
Testing mutant batch 196..203
Testing mutant batch 203..210

====== Results

Mutant ID | File Name            | Status
----------------------------------------------
----------------------------------------------
1         | L1ArbitrumMessenger.sol | SURVIVED
2         | L1ArbitrumMessenger.sol | SURVIVED
3         | L1ArbitrumMessenger.sol | KILLED
----------------------------------------------
4         | L1ArbitrumExtendedGateway.sol | KILLED
5         | L1ArbitrumExtendedGateway.sol | KILLED
6         | L1ArbitrumExtendedGateway.sol | KILLED
7         | L1ArbitrumExtendedGateway.sol | KILLED
8         | L1ArbitrumExtendedGateway.sol | KILLED
9         | L1ArbitrumExtendedGateway.sol | KILLED
10        | L1ArbitrumExtendedGateway.sol | KILLED
11        | L1ArbitrumExtendedGateway.sol | KILLED

...

205       | L1WethGateway.sol    | SURVIVED
206       | L1WethGateway.sol    | SURVIVED
207       | L1WethGateway.sol    | SURVIVED
208       | L1WethGateway.sol    | SURVIVED
209       | L1WethGateway.sol    | SURVIVED
----------------------------------------------
Total Mutants: 209
Killed: 133 (63.64%)
Survived: 76 (36.36%)

====== Done in 20.91 min
```

We're insterested to analyze the mutants which survived. The 1st column in output, `Mutant ID`, can be used to find the exact mutation that was applied by looking into the matching entry in the `gambit_results.json` file.

## Other considerations
Mutation testing script is time-intensive due to all the re-compiling work. For that reason, list of input files should be optimized to give the most benefit for the limited time period available for testing. Ie. single Solidity files can be targeted and tested manually, and the broader scope of files can be tested overnight.

Other params that can be adjusted are type of mutations to use, number of mutants to be generated, randomness seed to use in generation, etc. 

