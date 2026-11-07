# SoC UVM testbench (VIPs from uvm_full_tb_generator.py)

## Flow
```
csv/<vip>.csv --(gen/uvm_full_tb_generator.py)--> <vip>_uvm_tb/   11 skeleton files per VIP
                                                    + protocol logic filled in (below)
soc_env/   one env with the 3 agents + scoreboard + tests
top/       tb_top.sv: soc_top + uart_if + spi_if + gpio_if, uvm_config_db, run_test()
soc_uvm.f  file list        ../sim/uvm/run_uvm_vcs.sh  build C test, compile, run
```
`soc_top` is not changed. The `tb_top.sv` inside each `<vip>_uvm_tb/` is the generator's
standalone top and is not used; `top/tb_top.sv` is the SoC top.

## Generated files: what was changed

| VIP | Filled in (logic added) | Added | Left as generated |
| --- | --- | --- | --- |
| UART | item (byte, direction, error injection), driver (8N1 frames on uart_rx_i), monitor (decodes uart_tx_o and uart_rx_i), agent (gets is_active, exports ap), pkg (+seq_lib include) | uart_seq_lib.sv | if, sequencer, scoreboard, env, test, tb_top |
| SPI | item (frame: MOSI + MISO bytes), driver (mode-0 slave memory, MISO fault knob), monitor (one item per CS_n frame, SCLK idle check), agent, pkg (+seq_lib include) | spi_seq_lib.sv | if, sequencer, scoreboard, env, test, tb_top |
| GPIO | item (gpio_out_o value), monitor (one item per change), agent (passive in SoC env) | - | if, driver, sequencer, scoreboard, env, test, pkg, tb_top |

How the VIPs get the interfaces: `top/tb_top.sv` does
`uvm_config_db#(virtual uart_if)::set(null,"*","uart_vif",uart_vif)` (same for spi/gpio);
each driver/monitor does the matching `get` in build_phase.

## Tests (soc_env/soc_tests.sv)

| UVM test | C program | Checks |
| --- | --- | --- |
| soc_uart_test | test_uart | "UART OK" -> VIP sends 0x48 0x49 -> SoC prints "RX 48 49" + "PASS" |
| soc_uart_err_test | test_uart | VIP flips bit 1 of byte 2 (0x49 -> 0x4B) -> SoC must print "FAIL" |
| soc_spi_test | test_spi | write frame MOSI = 48 49 40 87, readback frame MISO = same, SoC prints "PASS" |
| soc_spi_err_test | test_spi | SPI VIP flips MISO bit 0 of byte 1 -> SoC must print "FAIL" |
| soc_gpio_test | test_gpio | GPIO VIP sees pins go 55 AA AF 0F 01, SoC prints "GPIO 55 AA AF 0F 01" + "PASS" |

All four pass (0 UVM_ERROR) on the full SoC with Verilator 5.052 + UVM 2020.
VCS uses UVM 1.2 (`-ntb_opts uvm-1.2`).

## Run on the lab PC
```bash
cd /home/student/Downloads/Ruthwik_171/soc_proj_DC
./sim/uvm/run_uvm_vcs.sh soc_uart_test     test_uart
./sim/uvm/run_uvm_vcs.sh soc_uart_err_test test_uart
./sim/uvm/run_uvm_vcs.sh soc_spi_test      test_spi
./sim/uvm/run_uvm_vcs.sh soc_spi_err_test  test_spi
./sim/uvm/run_uvm_vcs.sh soc_gpio_test      test_gpio
WAVES=1 ./sim/uvm/run_uvm_vcs.sh soc_uart_test test_uart     # waveforms in Verdi
```
Plusargs: `+UART_CPB=<n>` (UART clocks per bit, default 64), `+TIMEOUT_NS=<n>` (default 5 ms).
