#!/bin/bash

# usage: ./test/util/forge-inspect.bash <outputDir> <inspectType>

contracts=$(./scripts/template/print-contracts.bash)
if [[ $? != "0" ]]; then
    echo "Failed to get contracts"
    exit 1
fi

outputDir=$1
inspectType=$2

CHANGED=0

for contractName in $contracts; do
    echo "Checking for $inspectType changes in $contractName"

    # if the file doesn't exist, create it
    if [ ! -f "$outputDir/$contractName" ]; then
        forge inspect "$contractName" "$inspectType" > "$outputDir/$contractName"
        CHANGED=1
    # if the file does exist, compare it        
    else
        mv "$outputDir/$contractName" "$outputDir/$contractName-old"
        forge inspect "$contractName" "$inspectType" > "$outputDir/$contractName"
        diff "$outputDir/$contractName-old" "$outputDir/$contractName"
        if [[ $? != "0" ]]; then
            CHANGED=1
        fi
    fi
done

rm -f "$outputDir"/*-old

# Remove files for contracts that no longer exist
for existingFile in "$outputDir"/*; do
    filename=$(basename "$existingFile")

    # skip files with extensions
    if [[ "$filename" == *.* ]]; then
        continue
    fi
    
    # if the file doesn't exist in the contracts list, remove it
    if ! echo "$contracts" | grep -qx "$filename"; then
        rm -f "$existingFile"
        CHANGED=1
    fi
done

exit $CHANGED
