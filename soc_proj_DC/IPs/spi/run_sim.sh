#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
export LM_LICENSE_FILE="27021@14.139.1.126"

echo "=== Compiling SPI Master IP Core with Synopsys VCS ==="
vcs -full64 -sverilog +incdir+. \
    spi_core.v \
    spi_axi4.v \
    spi_top.v \
    tb_spi.v \
    -o simv_spi \
    -l compile.log

echo "=== Running SPI Master Simulation ==="
./simv_spi -l sim.log
