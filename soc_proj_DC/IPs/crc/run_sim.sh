#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
export LM_LICENSE_FILE="27021@14.139.1.126"

echo "=== Compiling CRC-16 IP Core with Synopsys VCS ==="
vcs -full64 -sverilog +incdir+. \
    crc16_core.v \
    crc16_axi4.v \
    crc_top.v \
    tb_crc_top.v \
    -o simv_crc \
    -l compile.log

echo "=== Running CRC-16 Simulation ==="
./simv_crc -l sim.log
