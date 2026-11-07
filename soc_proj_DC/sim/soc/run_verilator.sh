#!/usr/bin/env bash
# run_verilator.sh - same flow as run_vcs.sh but with Verilator 5.x (free)
#   ./sim/soc/run_verilator.sh test_uart [+WAVES] [+BUSTRACE]
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TEST="${1:-test_uart}"; shift || true

make -C sw SIM=1 TEST="$TEST"

mkdir -p sim/soc/out
if [ ! -x sim/soc/out/obj_dir/Vtb_soc ] || [ -n "$REBUILD" ]; then
  verilator --binary --timing -j 0 \
    -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
    -Wno-PINMISSING -Wno-TIMESCALEMOD \
    --top-module tb_soc -f sim/soc/soc.f \
    tb/soc/uart_pc_model.sv tb/soc/tb_soc.sv \
    --Mdir sim/soc/out/obj_dir -o Vtb_soc
fi
./sim/soc/out/obj_dir/Vtb_soc +BOOT_HEX="sw/build/$TEST.hex" "$@" | tee "sim/soc/out/$TEST.log"
