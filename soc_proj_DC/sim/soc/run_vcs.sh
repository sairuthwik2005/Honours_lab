#!/usr/bin/env bash
# run_vcs.sh - build and run a C test on the full SoC with Synopsys VCS
#   ./sim/soc/run_vcs.sh                 # runs test_uart
#   ./sim/soc/run_vcs.sh test_uart       # same
#   WAVES=1 ./sim/soc/run_vcs.sh test_uart   # also dump FSDB and open Verdi
#   ./sim/soc/run_vcs.sh test_uart +VCD       # plain VCD (GTKWave / any viewer)
#   ./sim/soc/run_vcs.sh test_uart +BUSTRACE  # print CPU bus accesses
# Run from anywhere; paths are resolved from soc_proj_DC/.
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TEST="${1:-test_uart}"; shift || true

# --- lab tool setup (same as the IP run_sim.sh scripts) ---
export VCS_HOME="${VCS_HOME:-/home/student/snps_tools_target/vcs/U-2023.03}"
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-27021@14.139.1.126}"
export LM_LICENSE_FILE="${LM_LICENSE_FILE:-27021@14.139.1.126}"

WAVE_OPTS=""
RUN_OPTS=""
WAVE_FILE=""
if [ "${WAVES:-0}" = "1" ]; then
  # Find Verdi: $VERDI_HOME, else from 'which verdi', else next to VCS
  if [ -z "$VERDI_HOME" ] && command -v verdi >/dev/null 2>&1; then
    VERDI_HOME="$(cd "$(dirname "$(command -v verdi)")/.." && pwd)"
  fi
  if [ -z "$VERDI_HOME" ]; then
    VERDI_HOME="$(ls -d /home/student/snps_tools_target/verdi/* 2>/dev/null | head -1)"
  fi
  export VERDI_HOME
  [ -n "$VERDI_HOME" ] && export PATH="$VERDI_HOME/bin:$PATH"
  echo "VERDI_HOME = ${VERDI_HOME:-<not found>}"

  WAVE_OPTS="-debug_access+all -kdb -lca"
  PLI="$VERDI_HOME/share/PLI/VCS/LINUX64"
  if [ -n "$VERDI_HOME" ] && [ -f "$PLI/novas.tab" ] && [ -f "$PLI/pli.a" ]; then
    # FSDB dumper available: fastest, native Verdi format
    WAVE_OPTS="$WAVE_OPTS +define+FSDB -P $PLI/novas.tab $PLI/pli.a"
    WAVE_FILE="sim/soc/out/tb_soc.fsdb"
  else
    # No FSDB dumper found: dump VCD instead (Verdi and GTKWave can open it)
    RUN_OPTS="+VCD"
    WAVE_FILE="sim/soc/out/tb_soc.vcd"
  fi
fi

echo "=== 1. Build C test: $TEST ==="
make -C sw SIM=1 TEST="$TEST"

echo "=== 2. Compile SoC + testbench with VCS ==="
mkdir -p sim/soc/out
vcs -full64 -sverilog -assert svaext -timescale=1ns/1ps \
    +define+RV_OPENSOURCE +lint=TFIPC-L \
    $WAVE_OPTS \
    -f sim/soc/soc.f \
    tb/soc/uart_pc_model.sv tb/soc/tb_soc.sv \
    -top tb_soc \
    -o sim/soc/out/simv_soc \
    -l sim/soc/out/compile.log

echo "=== 3. Run ==="
./sim/soc/out/simv_soc +BOOT_HEX="sw/build/$TEST.hex" $RUN_OPTS "$@" -l "sim/soc/out/$TEST.log"

if [ "${WAVES:-0}" = "1" ]; then
  echo "=== 4. Waveform: $WAVE_FILE ==="
  if command -v verdi >/dev/null 2>&1; then
    verdi -ssf "$WAVE_FILE" -dbdir sim/soc/out/simv_soc.daidir &
  else
    echo "Verdi not found in PATH. Open $WAVE_FILE with: gtkwave $WAVE_FILE &"
  fi
fi
