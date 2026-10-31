#!/bin/bash

# Define the execution script and input file paths
PYTHON_SCRIPT="$1"   # Change to your script file name
INPUT_FILE="$2"  # Path to the large test case

# Ensure the Python script and input file exist
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo "Script file not found: $PYTHON_SCRIPT"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Input file not found: $INPUT_FILE"
    exit 1
fi

# Measure the time taken to execute the Python script
echo "Starting execution..."
time python "$PYTHON_SCRIPT" < "$INPUT_FILE"

