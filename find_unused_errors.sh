#!/bin/bash

# Directory containing the Solidity files
DIR="./contracts"

# Temporary file to store errors
ERRORS_FILE=$(mktemp)

# Find all error definitions and store them in a temporary file
grep -rho "error\s\+\w\+\s*(" $DIR | awk '{gsub(/error /, ""); gsub(/\(/, ""); print}' | sort -u > $ERRORS_FILE

# Loop through each error to check if it is used
while read -r error; do
    # Count occurrences of each error in 'revert' statements
    # Looking for the pattern "revert ErrorName" with potential spaces before a parenthesis or semicolon
    count=$(grep -roh "revert\s\+$error" $DIR | grep -c "$error")

    # If count is 0, the error is defined but never used
    if [ "$count" -eq 0 ]; then
        echo "Error '$error' is defined but never used."
    fi
done < $ERRORS_FILE

# Remove the temporary file
rm $ERRORS_FILE
