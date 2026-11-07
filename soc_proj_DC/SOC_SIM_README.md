# SoC C-test flow (VeeR EL2 + interconnect + IPs)

## Run the UART C test

```bash
cd /home/student/Downloads/Ruthwik_171/soc_proj_DC
./sim/soc/run_vcs.sh test_uart            # VCS (lab)
./sim/soc/run_verilator.sh test_uart      # Verilator 5.x (if installed)
```
Add `+WAVES` for a VCD dump or `+BUSTRACE` to print every CPU access to DMEM/peripherals.

Expected end of the log:
```
UART RX from SoC: "UART OK"
PC model sends 0x48 0x49 ("HI")
UART RX from SoC: "RX 48 49"
UART RX from SoC: "PASS"
 *** UART C TEST PASSED ***
```

Needs a RISC-V GCC (`riscv64-unknown-elf-gcc` or set `CROSS=riscv32-unknown-elf-`).

## What changed

| File | Change |
| --- | --- |
| `rtl/axi_cpu_subsystem.v` | Connected the VeeR wrapper ports that were missing: memory export interfaces (`el2_mem_export`, `el2_icache_export`), JTAG pins (held inactive), `soft_int`, `core_id`, `scan_mode`, `mbist_mode`, DMI pins. Without these the design does not elaborate. |
| `rtl/axi4_64_to_32_adapter.sv` | AWVALID is now dropped on AWREADY in every state. Before, if the address was accepted after the data phase began, AWVALID stayed high and the write could repeat or hang. |
| `RISC-V-VeeR-EL2/snapshots/soc/` | New VeeR configuration: reset vector 0x0, ICCM/DCCM/I-cache off, so all fetches and loads/stores go over AXI to IMEM/DMEM. |
| `sim/soc/soc.f` | One file list for the whole SoC. |
| `sim/soc/run_vcs.sh`, `run_verilator.sh` | Build the C test, compile, run. |
| `tb/soc/tb_soc.sv` | SoC testbench: clock, reset, loads `+BOOT_HEX`, timeout, optional bus trace. |
| `tb/soc/uart_pc_model.sv` | Plays the PC: prints what the SoC sends, sends "HI", ends the run on PASS/FAIL. |
| `sw/` | `common/` (crt0.S, link.ld, soc.h, uart.c/h, bin2hex.py), `tests/test_uart.c`, `Makefile`. |

## Address map (from rtl/soc_top.v)

| Slave | Base | Size |
| --- | --- | --- |
| IMEM | 0x0000_0000 | 64 KiB |
| DMEM | 0x1000_0000 | 64 KiB |
| UART | 0x2000_0000 | 4 KiB |
| Timer | 0x2000_1000 | 4 KiB |
| GPIO | 0x2000_2000 | 4 KiB |
| CRC-16 | 0x2000_3000 | 4 KiB |
| FIFO | 0x2000_4000 | 4 KiB |
| SPI | 0x2000_5000 | 4 KiB |

## UART registers (IPs/UART_IP)

| Offset | Name | Access | Notes |
| --- | --- | --- | --- |
| 0x00 | RBR / THR | R / W | read pops RX FIFO, write pushes TX FIFO (DLAB=0) |
| 0x04 | IER | W | bit0 must be 1, otherwise LSR.DR never sets |
| 0x08 | DIV | W | baud divisor, only when LCR.DLAB=1; bit time = DIV+1 clocks |
| 0x0C | LCR | W | bit7 DLAB, bit2 2 stop bits, bit3 parity enable |
| 0x14 | LSR | R | bit0 DR (data ready), bit5 THRE (TX FIFO has space) |

## Known issues (not fixed yet)

- Reading UART IER, DIV or LCR gets no AXI response and the CPU hangs. Firmware only reads RBR and LSR.
- No interrupt lines reach VeeR yet (`uart_irq_o`, `timer_irq_o`, GPIO, SPI are left open). Tests use polling.
- `sw/Makefile` SIM=1 uses UART divisor 63 for a short sim; `tb/soc/tb_soc.sv` UART_DIV must match.
