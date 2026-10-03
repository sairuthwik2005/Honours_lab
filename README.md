# RISC-V Based Reliable Digital Communication SoC

**Solo Honours Project — Y Sai Ruthwik**  
**Department of Electronics and Communication Engineering — Vasavi College of Engineering**

---

## 1. Project Overview

This project is the design and integration of a **RISC-V based SoC for reliable serial communication**.

The system is built around a **VeeR EL2 RISC-V processor** and an AXI4 memory-mapped interconnect. It takes payload bytes in over UART, builds a packet, protects it with **CRC-16**, sends it off-chip over **SPI**, reads it back, checks it, and **retransmits** if the data came back corrupted.

Dedicated hardware in the SoC:

- **CRC-16 accelerator** — error detection (CRC-16-CCITT-FALSE)
- **16 × 8 streaming TX FIFO** — buffers data between the CPU and SPI
- **SPI master** — moves the packet off-chip and reads it back
- **UART** — payload input and status reporting
- **Timer / GPIO** — timeout detection and status flags

Development is incremental: each IP is verified on its own first, then the processor is integrated, then the full SoC is verified.

---

## 2. Problem Statement

SPI has **no built-in error detection**. No parity, no acknowledge, no checksum.

Once a bit leaves the chip it travels over PCB traces and connectors, where crosstalk, ringing, EMI or timing skew can flip it. The receiver samples the wrong value and nothing in the link notices.

```text
   CPU builds correct packet
            |
            v
   SPI drives bits off-chip
            |
            v
   Noise on the wire flips one bit      <-- happens outside the chip
            |
            v
   Slave stores the wrong byte
            |
            v
   Without CRC: bad data looks exactly like good data
   With CRC:    mismatch detected -> packet rejected -> retransmit
```

The CPU never generates a bad packet. It keeps the correct copy (`tx_packet[]`) in data memory. Only the copy rebuilt on the far side of the wire can be corrupted, and CRC-16 is what tells the two apart.

---

## 3. Overall System Architecture

The planned system uses a **2 × 8 AXI4 interconnect**: two processor-side interfaces and eight memory-mapped destinations.

```text
                              +------------------+
                              |     VeeR EL2     |
                              |     RISC-V       |
                              +--------+---------+
                                       |
                              +--------+--------+
                              |                 |
                             IFU               LSU
                              |                 |
                              +--------+--------+
                                       |
                                       v
                            +----------------------+
                            |   AXI4 Interconnect  |
                            |        2 × 8         |
                            +----------+-----------+
                                       |
    +---------+---------+---------+----+----+---------+---------+---------+
    |         |         |         |         |         |         |         |
    v         v         v         v         v         v         v         v
  I-MEM     D-MEM     UART      Timer     GPIO     CRC-16    TX FIFO ---> SPI
                                                             (direct link)
```

All eight blocks are peer AXI destinations. The **FIFO → SPI read path is the only direct IP-to-IP connection** in the design. Every other transfer goes through the CPU over AXI.

---

## 4. Processor-Side Interfaces

VeeR EL2 exposes three AXI managers and one AXI slave. This project uses two managers.

| VeeR Interface | System Role | Used |
|----------------|-------------|:----:|
| `ifu_axi` | Master 0 — instruction fetch | ✅ |
| `lsu_axi` | Master 1 — load / store | ✅ |
| `sb_axi` | Debug system bus | ⬜ Tied off |
| `dma_axi` | AXI slave into VeeR | ⬜ Tied off |

Debug infrastructure is outside the scope of the project, so `sb_axi` is tied off and the interconnect is configured with `S_COUNT = 2`.

VeeR's AXI4 build exposes native AXI ports, so it connects straight to the interconnect. No extra AXI master module is needed between them.

---

## 5. Planned Memory Map

| Port | Region | Base Address |
|:----:|--------|--------------|
| M00 | Instruction Memory | `0x0000_0000` |
| M01 | Data Memory | `0x1000_0000` |
| M02 | UART | TBD |
| M03 | Timer | TBD |
| M04 | GPIO | TBD |
| M05 | CRC-16 Accelerator | TBD |
| M06 | TX FIFO | TBD |
| M07 | SPI Master | TBD |

Peripheral addresses will be finalized during integration.

> **Note:** the interconnect passes the full address to each slave without stripping the region base. Every slave decodes only its low address bits.

---

## 6. SoC Boundary — Top-Level Pins

Nine pins in total.

| Pin | Dir | Width | Connected To | Carries |
|-----|:---:|:-----:|--------------|---------|
| `clk_i` | in | 1 | clock source | system clock |
| `rst_ni` | in | 1 | reset source | active-low reset |
| `uart_rx_i` | in | 1 | UART source model | payload bytes |
| `spi_miso_i` | in | 1 | SPI slave model | readback bits |
| `uart_tx_o` | out | 1 | UART monitor | status messages |
| `spi_mosi_o` | out | 1 | SPI slave model | packet bits, then 0x00 dummies |
| `spi_sclk_o` | out | 1 | SPI slave model | Mode-0 clock |
| `spi_cs_no` | out | 1 | SPI slave model | active-low chip select |
| `gpio_out_o[7:0]` | out | 8 | status monitor | sticky status bits |

Only **two pins carry data into the chip**: `uart_rx_i` and `spi_miso_i`. Corruption can only enter through those.

---

## 7. AXI4 Interconnect

The AXI interconnect is the main communication fabric of the SoC.

| Item | Status |
|------|:------:|
| AXI interconnect RTL | ✅ Present |
| Arbiter / priority encoder | ✅ Present |
| 1 × 8 wrapper | ✅ Elaborates |
| Master → interconnect → slaves test | ✅ Passing |
| 2 × 8 configuration for VeeR | 🚧 In progress |
| Final address map | ⬜ Pending |

### 7.1 Supporting AXI blocks

| Block | Purpose | Status |
|-------|---------|:------:|
| `axi4_slave_regif.v` | Generic AXI4 slave → simple register bus. Front end for every custom IP | ✅ Verified |
| `axi4_master.v` | AXI4 master with a command interface, used as a bus driver in testbenches | ✅ Verified |
| `axi_slave_mem.v` | AXI4 memory slave (FIXED / INCR / WRAP bursts) | ✅ Verified |

`axi4_slave_regif` tests: single beat, INCR bursts (len 8 and 16), back-to-back IDs, byte strobes, address aliasing.

---

## 8. UART

The UART brings the payload into the SoC at runtime (no hard-coded data) and prints the pass / fail result.

It is based on an open-source AXI-Lite UART IP, wrapped for the AXI4 system.

```text
   AXI4 interconnect
          |
          v
 +--------------------+
 | axi4_to_uart_lite  |   AXI4 -> AXI-Lite bridge
 +---------+----------+
           |
           v
 +--------------------+
 |   UART IP core     |
 +----+----------+----+
      |          |
   uart_rx_i  uart_tx_o
```

### 8.1 Issues found and fixed

| Issue | Fix |
|-------|-----|
| The IP holds `AWREADY` low until `WVALID` is already high. A normal AXI master that sends the address first waits forever (deadlock). | Bridge captures AW and W separately, then presents both to the IP together |
| `LSR[0]` (data ready) is ANDed with the interrupt-enable bit inside the IP. Polling for RX data never works unless `IER = 1`. | Firmware must write `IER = 1` before polling |

### UART status

| Item | Status |
|------|:------:|
| `axi4_to_uart_lite.v` bridge | ✅ |
| `uart_subsystem.v` wrapper | ✅ |
| Standalone verification | ✅ |
| AXI system integration | ⬜ |

---

## 9. CRC-16 Accelerator

The CRC-16 accelerator is the **error-detection engine** of the project.

### 9.1 Parameters (CRC-16-CCITT-FALSE)

| poly | init | refin | refout | xorout |
|:----:|:----:|:-----:|:------:|:------:|
| `0x1021` | `0xFFFF` | false | false | `0x0000` |

Generator polynomial: x¹⁶ + x¹² + x⁵ + 1

### 9.2 Coverage

```text
+--------+------+--------+-------------+---------+---------+
| Header | Type | Length |   Payload   | CRC Hi  | CRC Lo  |
+--------+------+--------+-------------+---------+---------+
|<---------- protected by CRC -------->|<- appended, high ->|
                                                byte first
```

The receiver recomputes the CRC over the same bytes and compares it with the two received CRC bytes.

### 9.3 What it catches

| Error type | Detected |
|------------|:--------:|
| Any single-bit error | ✅ |
| Any odd number of bit errors | ✅ |
| Any burst up to 16 bits | ✅ |
| Longer bursts | ~1 in 65,536 escape |

CRC detects errors. It cannot locate or fix them. **Retransmission is the recovery.**

### Current state

| Work | Status |
|------|:------:|
| `crc16_ccitt.v` RTL | ✅ |
| Verification (9 tests, reference vectors, exhaustive single-bit error detection on a 56-bit message) | ✅ |
| AXI register wrapper | ⬜ |
| SoC integration | ⬜ |

---

## 10. TX FIFO (16 × 8)

The FIFO absorbs the speed gap between the CPU (system clock) and SPI (divided SCLK), so the CPU does not stall on every byte.

```text
   CPU (via AXI)                         SPI master (direct)
        |                                        ^
   fifo_wr_en, fifo_wr_data             fifo_rd_en |  fifo_rd_data,
        |                                        |  fifo_data_valid
        v                                        |
   +-----------------------------------------------+
   |              16 x 8 TX FIFO                   |
   |  level / overflow / underflow flags to CPU    |
   +-----------------------------------------------+
```

Packets may be longer than 16 bytes. The CPU fills while SPI drains, so it works as a streaming buffer.

| Work | Status |
|------|:------:|
| `fifo_16x8.v` RTL | ✅ |
| Verification (10 tests: ordering, full / empty, overflow / underflow) | ✅ |
| AXI register wrapper | ⬜ |
| SoC integration | ⬜ |

---

## 11. SPI Master

The SPI master is the only block that drives data off the chip.

- **WRITE:** drains the FIFO and shifts each byte out on MOSI (Mode 0, MSB first)
- **READBACK:** clocks out `0x00` dummy bytes and captures MISO into `spi_rx_data`

Planned registers: `spi_mode`, `spi_length`, `spi_clk_div`, `spi_start`, `spi_abort`, `spi_busy`, `spi_done`, `spi_rx_data`, `spi_rx_valid`.

| Block | Owns | Does not own |
|-------|------|--------------|
| CRC-16 | integrity value | movement, storage |
| FIFO | rate matching, ordering | integrity, serialization |
| SPI master | serialization, off-chip drive | integrity, storage |

| Work | Status |
|------|:------:|
| Register map | ✅ Defined |
| RTL | ⬜ Not started |
| IP-level timing verification | ⬜ Not started |
| SoC integration | ⬜ Pending |

---

## 12. Memory, Timer and GPIO

### 12.1 Memory

| Memory | Base Address | Holds |
|--------|--------------|-------|
| Instruction Memory | `0x0000_0000` | program image |
| Data Memory | `0x1000_0000` | `tx_packet[]`, `rx_packet[]`, retry count, variables |

`tx_packet[]` is kept unchanged across retries. It is the source for retransmission.

### 12.2 Timer

Counts up to `timer_limit` and sets a sticky `timer_timeout` flag. The CPU polls it. There is no wire from the timer to SPI — on timeout, software writes `spi_abort`.

### 12.3 GPIO status bits

| Bit | Meaning |
|:---:|---------|
| 0 | transmission complete |
| 1 | CRC pass |
| 2 | CRC fail |
| 3 | FIFO overflow |
| 4 | FIFO underflow |
| 5 | SPI timeout |
| 6 | retry active |
| 7 | failed after three attempts |

| Block | Status |
|-------|:------:|
| AXI memory slave | ✅ Verified (`axi_slave_mem.v`) |
| Instruction / data memory integration | ⬜ Pending |
| Timer RTL | ⬜ Not started |
| GPIO RTL | ⬜ Not started |

---

## 13. Functional Data Flow

This is the **planned end-to-end flow**, not the RTL hierarchy.

```text
          UART source
              |
         uart_rx_i
              v
     +-----------------+
     |    VeeR EL2     |  1. receive payload
     |   (firmware)    |  2. build tx_packet[] in data memory
     +--------+--------+
              |
              v
     +-----------------+
     |     CRC-16      |  3. compute CRC, append 2 bytes
     +--------+--------+
              |
              v
     +-----------------+
     |    TX FIFO      |  4. stream packet bytes
     +--------+--------+
              |
              v
     +-----------------+       spi_mosi_o      +------------------+
     |   SPI master    | --------------------> |  SPI slave model |
     |                 |                       |  slave_packet[]  |
     |                 | <-------------------- |                  |
     +--------+--------+       spi_miso_i      +--------+---------+
              |                                          ^
              | 6. READBACK -> rx_packet[]               | 5. error injector
              v                                          |    may flip 1 bit
     +-----------------+
     |     CRC-16      |  7. recompute and compare
     +--------+--------+
              |
     +--------+---------+
     |                  |
   match            mismatch
     |                  |
     v                  v
  UART "PASS"     resend tx_packet[]  (max 3 attempts)
  GPIO bit 1      GPIO bit 2 / 6
                  3rd failure -> GPIO bit 7
```

---

## 14. Error Injection

RTL simulation has no voltages or noise, so the testbench reproduces the **effect** instead of the physics.

After the SPI WRITE and before the READBACK, the testbench flips:

```text
slave_packet[error_byte_index][error_bit_index]
```

when `error_inject_enable` is set.

These controls live **only in the testbench**. They never appear on the SoC pins.

The SPI slave model is **store-and-forward** (it keeps the packet and returns it on READBACK), not a simple MOSI → MISO wire loop. This mirrors a real SPI flash and gives a stronger demonstration.

---

## 15. System Integration Strategy

### Integration order

| Stage | Work |
|:----:|------|
| 1 | Verify individual IPs (FIFO, CRC, UART, AXI blocks) |
| 2 | Verify AXI interconnect |
| 3 | Build and verify SPI master, timer, GPIO |
| 4 | Wrap CRC / FIFO / SPI / timer / GPIO with AXI register interfaces |
| 5 | Integrate VeeR EL2 with the 2 × 8 interconnect |
| 6 | Integrate instruction / data memory |
| 7 | Verify processor-to-peripheral transactions |
| 8 | Write firmware for the packet / CRC / retry flow |
| 9 | Build SoC testbench (UART models, SPI slave, error injector) |
| 10 | Full SoC verification |

---

## 16. Current Development Focus

The immediate work is **SPI master + AXI wrappers + VeeR integration foundation**.

### Immediate sequence

```text
1. Write and verify SPI master (with direct FIFO read port)
          ↓
2. Add AXI register wrappers for CRC-16, FIFO, SPI
          ↓
3. Write timer and GPIO
          ↓
4. Configure 2 × 8 interconnect with final address map
          ↓
5. Connect VeeR EL2 + memories
          ↓
6. Verify VeeR → AXI → Memory / UART
          ↓
7. Firmware + full SoC testbench
```

---

## 17. Repository Structure

Planned layout:

```text
Honours_lab/
├── rtl/
│   ├── axi/          interconnect, arbiter, priority encoder, slave regif, master
│   ├── uart/         UART IP, AXI4 -> AXI-Lite bridge, subsystem wrapper
│   ├── crc/          crc16_ccitt
│   ├── fifo/         fifo_16x8
│   ├── spi/          SPI master
│   ├── periph/       timer, GPIO
│   └── soc_top.v
├── tb/               IP-level and SoC-level testbenches
├── sw/               firmware for VeeR EL2
├── sim/              VCS / Verdi run scripts
└── docs/             architecture document, diagrams, waveforms
```

---

## 18. Tools

| Area | Tool / Technology |
|------|-------------------|
| RTL | Verilog / SystemVerilog |
| Processor | VeeR EL2 (RISC-V) |
| Bus | AXI4 / AXI4-Lite |
| Simulation | Synopsys VCS U-2023.03 |
| Waveform Debug | Synopsys Verdi / FSDB |
| Quick checks | Icarus Verilog |
| Version Control | Git / GitHub |
| Development Environment | Rocky Linux 8 |

### Running a testbench

```bash
vcs -full64 -debug_access+all -kdb -o simv tb_fifo_16x8.v fifo_16x8.v -l comp.log
./simv -l sim.log
verdi -ssf wave.fsdb &
```

Every testbench is self-checking and ends with `*** ALL TESTS PASSED ***`.

---

## 19. Project Status

| Area | Status | Current Position |
|------|:------:|------------------|
| Architecture / pins / GPIO map | ✅ | Defined |
| TX FIFO 16 × 8 | ✅ | RTL done, 10 tests passing |
| CRC-16-CCITT-FALSE | ✅ | RTL done, 9 tests passing |
| AXI4 slave register interface | ✅ | Verified |
| AXI4 master (TB driver) | ✅ | Verified |
| AXI memory slave | ✅ | Verified |
| UART bridge + subsystem | ✅ | Verified, deadlock fixed |
| AXI interconnect 1 × 8 | ✅ | Elaborates, routing test passing |
| AXI interconnect 2 × 8 | 🚧 | Being configured for VeeR |
| VeeR EL2 integration | 🚧 | Interfaces identified, `sb_axi` tied off |
| SPI master | ⬜ | Register map defined, RTL pending |
| Timer / GPIO | ⬜ | Not started |
| AXI wrappers for CRC / FIFO / SPI | ⬜ | Pending |
| Firmware | ⬜ | Not started |
| SoC testbench + error injector | ⬜ | Pending |
| Full SoC verification | ⬜ | Pending |

### Status Legend

- ✅ Completed / Verified
- 🚧 Currently in progress
- ⬜ Pending / Not started

---

## 20. Remaining Work

| Priority | Area | Remaining Work |
|:--------:|------|----------------|
| 1 | SPI | Design and verify SPI master (WRITE / READBACK, abort) |
| 2 | AXI | AXI register wrappers for CRC, FIFO, SPI, timer, GPIO |
| 3 | Peripherals | Timer and GPIO RTL |
| 4 | VeeR + AXI | 2 × 8 interconnect, final address map, VeeR connection |
| 5 | Memory | Instruction / data memory integration |
| 6 | Firmware | UART RX, packet build, CRC, SPI write / readback, compare, retry, status |
| 7 | Testbench | UART source / monitor, store-and-forward SPI slave, error injector, GPIO monitor |
| 8 | Verification | AXI decode, clean loopback, single-bit error → retry → pass, persistent error → bit 7, SPI timeout, FIFO overflow / underflow |
| 9 | Documentation | Waveforms, results, final report |

---

## 21. Final Project Goal

The completed project should demonstrate:

- RISC-V (VeeR EL2) processor integration
- AXI4-based SoC interconnect
- Memory-mapped peripheral access
- UART payload input and status output
- Hardware CRC-16 generation and checking
- FIFO-buffered SPI transmission and readback
- Detection of injected bit errors
- Automatic retransmission, up to three attempts
- Status reporting through GPIO and UART
- Deterministic, self-checking RTL simulation

Scope: **simulation only**. No FPGA or board.

---

## Project Snapshot

> **Current milestone:** SPI master + VeeR / AXI 2 × 8 integration foundation  
>
> **Completed:** TX FIFO, CRC-16, AXI4 slave / master / memory, UART bridge and subsystem, 1 × 8 interconnect routing test  
>
> **In progress:** 2 × 8 interconnect configuration and VeeR integration  
>
> **Next:** SPI master → AXI wrappers → timer / GPIO → VeeR + memory  
>
> **Later:** Firmware → SoC testbench with error injection → full SoC verification
