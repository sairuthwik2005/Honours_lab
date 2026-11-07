#!/usr/bin/env bash
# ============================================================================
# Script: run_sim.sh
# Project: Reliable Data Transport System SoC - Timer IP Core
# Description: Compiles and runs the self-checking testbench using Synopsys VCS.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Set up Synopsys VCS environment
export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
export LM_LICENSE_FILE="27021@14.139.1.126"

echo "=== Compiling Timer IP Core with Synopsys VCS (64-bit) ==="
vcs -full64 -sverilog +incdir+. \
    timer_core.v \
    timer_top.v \
    timer_axi4lite.v \
    tb_timer.v \
    -o simv_timer \
    -l compile_timer.log

echo "=== Running Timer IP Simulation ==="
./simv_timer -l sim_timer.log
