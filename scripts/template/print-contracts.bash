#!/bin/bash

# search for all contracts defined in the contracts directory and print them

# need to build with this flag to get AST output
# could keep an eye on this issue to optimize this: https://github.com/foundry-rs/foundry/issues/7212
forge build --build-info > /dev/null

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

OUTPUT_PATH="out/"
SOURCE_PATH="contracts/"

# find all json files in the out directory
FILES=$(find $OUTPUT_PATH -name "*.json")

# Initialize an empty array to collect all contract names
declare -a all_contract_names=()

# for each file, print the absolutePath
for file in $FILES; do
    sol_path=$(cat "$file" | jq '.ast.absolutePath' -r)
    
    # make sure the path is in the source path and exclude test directory
    if [[ $sol_path == $SOURCE_PATH* ]] && [[ $sol_path != *"contracts/tokenbridge/test/"* ]]; then
        # Read contract names into an array and append them to the all_contract_names array
        while IFS= read -r name; do
            all_contract_names+=("$name")
        done < <(cat $file | jq '.ast.nodes[] | select(.nodeType == "ContractDefinition" and .contractKind == "contract" and .abstract == false).name' -r)
    fi
done

# if we have no contracts, exit with an error
if [ ${#all_contract_names[@]} -eq 0 ]; then
    echo "No contracts found"
    exit 1
fi

# Print unique contract names, removing duplicates
printf "%s\n" "${all_contract_names[@]}" | sort | uniq
