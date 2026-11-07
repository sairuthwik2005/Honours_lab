/*
 * ============================================================================
 * File: fifo_defines.vh
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Register definitions and bit masks for 16x8 TX FIFO IP Core
 * Base Address: 0x2000_4000 (Interconnect Slot M06, 4KB space)
 * ============================================================================
 */

`ifndef FIFO_DEFINES_VH
`define FIFO_DEFINES_VH

// Base Address in System Interconnect
`define FIFO_BASE_ADDR            32'h2000_4000

// Register Byte Offsets (word-aligned)
`define FIFO_REG_CTRL             8'h00   // [WO/RW] Control Register
`define FIFO_REG_STATUS           8'h04   // [RO]    Status Register
`define FIFO_REG_LEVEL            8'h08   // [RO]    Occupancy Level (0..16)
`define FIFO_REG_DATA             8'h0C   // [WO]    Data Write Port (8-bit)

// FIFO_REG_CTRL [0x00] Bit Definitions
`define FIFO_CTRL_CLEAR_BIT       0       // 1 = Clear FIFO pointers and contents
`define FIFO_CTRL_CLEAR_STAT_BIT  1       // 1 = Clear sticky overflow/underflow flags

// FIFO_REG_STATUS [0x04] Bit Definitions
`define FIFO_STATUS_FULL_BIT      0       // 1 = FIFO is full (16 entries)
`define FIFO_STATUS_EMPTY_BIT     1       // 1 = FIFO is empty (0 entries)
`define FIFO_STATUS_OVERFLOW_BIT  2       // 1 = Sticky write-overflow error
`define FIFO_STATUS_UNDERFLOW_BIT 3       // 1 = Sticky read-underflow error

// Parameters
`define FIFO_DEPTH                16
`define FIFO_WIDTH                8

`endif // FIFO_DEFINES_VH
