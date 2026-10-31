#!/bin/bash

# Define the cpp binary and input file paths
CPP_SCRIPT="$1"   # Change to your Python script name
INPUT_FILE="$2"  # Path to the large test case

# Ensure the cpp binary and input file exist
if [[ ! -f "$CPP_SCRIPT" ]]; then
    echo "cpp file not found: $CPP_SCRIPT"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Input file not found: $INPUT_FILE"
    exit 1
fi

# Measure the time taken to execute the Python script
echo "Starting execution..."
time "$CPP_SCRIPT" < "$INPUT_FILE"

