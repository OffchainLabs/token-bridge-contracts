#!/bin/bash

# Directory containing the Solidity files
DIR="./contracts"
EXCEPTIONS_FILE="./test/unused-errors/exceptions.txt"

# Temporary file to store errors and their corresponding files
ERRORS_FILE=$(mktemp)
UNUSED_ERRORS_FILE=$(mktemp)
exit_status=0

# Load exceptions into an array
exceptions=()
if [ -f "$EXCEPTIONS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        exceptions+=("$line")
    done < "$EXCEPTIONS_FILE"
fi

# Function to check if an error is in the exceptions list
is_exception() {
    local error="$1"
    for exception in "${exceptions[@]}"; do
        if [ "$exception" == "$error" ]; then
            return 0
        fi
    done
    return 1
}

# Find all error definitions and store them in a temporary file along with filenames
grep -rHo "error\s\+\w\+\s*(" $DIR | awk -F':' '{print $1 ": " $2}' | awk '{gsub(/error /, ""); gsub(/\(/, ""); print}' | sort -u > $ERRORS_FILE

# Loop through each error to check if it is used
while IFS=: read -r file error; do
    # Normalize file and error output
    error=$(echo $error | xargs)

    # Skip errors in the exception list
    if is_exception "$error"; then
        echo "Skipping: $error"
        continue
    fi

    # Count occurrences of each error in 'revert' statements
    count=$(grep -roh "revert\s\+$error" $DIR | wc -l)

    # If count is 0, the error is defined but never used
    if [ "$count" -eq 0 ]; then
        echo "$error" >> $UNUSED_ERRORS_FILE
        exit_status=1
    fi
done < $ERRORS_FILE

# Print the list of unused errors
if [ -s $UNUSED_ERRORS_FILE ]; then
    echo "These errors are defined, but never used:"
    cat $UNUSED_ERRORS_FILE
else
    echo "All defined errors are used."
fi

# Remove the temporary files
rm $ERRORS_FILE
rm $UNUSED_ERRORS_FILE

# Exit with the appropriate status
exit $exit_status
