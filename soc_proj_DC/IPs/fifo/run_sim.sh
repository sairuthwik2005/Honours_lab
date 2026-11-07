#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
export LM_LICENSE_FILE="27021@14.139.1.126"

echo "=== Compiling 16x8 TX FIFO IP Core with Synopsys VCS ==="
vcs -full64 -sverilog +incdir+. \
    fifo_core.v \
    fifo_axi4.v \
    fifo_top.v \
    tb_fifo.v \
    -o simv_fifo \
    -l compile.log

echo "=== Running 16x8 TX FIFO Simulation ==="
./simv_fifo -l sim.log
