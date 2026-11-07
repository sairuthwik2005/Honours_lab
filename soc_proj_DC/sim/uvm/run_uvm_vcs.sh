#!/usr/bin/env bash
# run_uvm_vcs.sh - run a SoC-level UVM test (VIPs from uvm_full_tb_generator.py) with VCS
#
#   ./sim/uvm/run_uvm_vcs.sh <uvm_test> <c_test> [plusargs...]
#   ./sim/uvm/run_uvm_vcs.sh                                   # soc_uart_test + test_uart
#   ./sim/uvm/run_uvm_vcs.sh soc_uart_err_test test_uart       # negative test
#   ./sim/uvm/run_uvm_vcs.sh soc_spi_test test_spi
#   WAVES=1 ./sim/uvm/run_uvm_vcs.sh soc_uart_test test_uart   # + waveforms, opens Verdi
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

UVM_TEST="${1:-soc_uart_test}"; shift || true
C_TEST="${1:-test_uart}";       shift || true

export VCS_HOME="${VCS_HOME:-/home/student/snps_tools_target/vcs/U-2023.03}"
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-27021@14.139.1.126}"
export LM_LICENSE_FILE="${LM_LICENSE_FILE:-27021@14.139.1.126}"
export CROSS="${CROSS:-riscv32-unknown-elf-}"

WAVE_OPTS=""; RUN_OPTS=""; WAVE_FILE=""
if [ "${WAVES:-0}" = "1" ]; then
  if [ -z "$VERDI_HOME" ] && command -v verdi >/dev/null 2>&1; then
    VERDI_HOME="$(cd "$(dirname "$(command -v verdi)")/.." && pwd)"
  fi
  [ -z "$VERDI_HOME" ] && VERDI_HOME="$(ls -d /home/student/snps_tools_target/verdi/* 2>/dev/null | head -1)"
  export VERDI_HOME; [ -n "$VERDI_HOME" ] && export PATH="$VERDI_HOME/bin:$PATH"
  WAVE_OPTS="-debug_access+all -kdb -lca"
  PLI="$VERDI_HOME/share/PLI/VCS/LINUX64"
  if [ -n "$VERDI_HOME" ] && [ -f "$PLI/novas.tab" ] && [ -f "$PLI/pli.a" ]; then
    WAVE_OPTS="$WAVE_OPTS +define+FSDB -P $PLI/novas.tab $PLI/pli.a"
    WAVE_FILE="sim/uvm/out/tb_top.fsdb"
  else
    RUN_OPTS="+VCD"; WAVE_FILE="sim/uvm/out/tb_top.vcd"
  fi
fi

echo "=== 1. Build C test: $C_TEST ==="
make -C sw SIM=1 TEST="$C_TEST"

echo "=== 2. Compile SoC + UVM testbench ==="
mkdir -p sim/uvm/out
vcs -full64 -sverilog -ntb_opts uvm-1.2 -assert svaext -timescale=1ns/1ps \
    +define+RV_OPENSOURCE +lint=TFIPC-L \
    $WAVE_OPTS \
    -f sim/soc/soc.f -f uvm/soc_uvm.f \
    -top tb_top \
    -o sim/uvm/out/simv_uvm \
    -l sim/uvm/out/compile.log

echo "=== 3. Run $UVM_TEST with $C_TEST ==="
./sim/uvm/out/simv_uvm +UVM_TESTNAME="$UVM_TEST" +BOOT_HEX="sw/build/$C_TEST.hex" \
    +UVM_VERBOSITY=UVM_LOW $RUN_OPTS "$@" -l "sim/uvm/out/${UVM_TEST}.log"

if [ "${WAVES:-0}" = "1" ] && command -v verdi >/dev/null 2>&1; then
  verdi -ssf "$WAVE_FILE" -dbdir sim/uvm/out/simv_uvm.daidir &
fi
