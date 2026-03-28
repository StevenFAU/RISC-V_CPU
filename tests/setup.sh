#!/bin/bash
# Setup script for RISC-V compliance tests
# Downloads and arranges riscv-tests sources needed by the compliance Makefile

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -d "isa" ]; then
    echo "tests/isa/ already exists — skipping setup"
    exit 0
fi

echo "Cloning riscv-tests (with submodules for env/encoding.h)..."
git clone --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/riscv-software-src/riscv-tests.git .tmp

echo "Extracting test sources..."
mv .tmp/isa isa

# Get encoding.h from the test environment (needed by test macros)
if [ ! -f env/encoding.h ] && [ -f .tmp/env/encoding.h ]; then
    cp .tmp/env/encoding.h env/encoding.h
fi

echo "Cleaning up..."
rm -rf .tmp

echo "Done. Run 'make run-all' to execute all 37 rv32ui compliance tests."
