/*
 * ============================================================================
 * File: crc_defines.vh
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Register definitions and bit masks for CRC-16-CCITT-FALSE IP
 * Base Address: 0x2000_3000 (Interconnect Slot M05, 4KB space)
 * ============================================================================
 */

`ifndef CRC_DEFINES_VH
`define CRC_DEFINES_VH

// Base Address in System Interconnect
`define CRC_BASE_ADDR            32'h2000_3000

// Register Byte Offsets (word-aligned)
`define CRC_REG_CTRL             8'h00   // [WO/RW] Control Register
`define CRC_REG_STATUS           8'h04   // [RO]    Status Register
`define CRC_REG_DATA             8'h08   // [WO]    Data Input Port (8-bit)
`define CRC_REG_RESULT           8'h0C   // [RO]    16-bit CRC Result

// CRC_REG_CTRL [0x00] Bit Definitions
`define CRC_CTRL_INIT_BIT        0       // 1 = Re-initialize CRC to 0xFFFF (auto-clears)
`define CRC_CTRL_CLEAR_STAT_BIT  1       // 1 = Clear result_valid status (auto-clears)

// CRC_REG_STATUS [0x04] Bit Definitions
`define CRC_STATUS_BUSY_BIT      0       // 1 = CRC engine busy (always 0 in single-cycle design)
`define CRC_STATUS_VALID_BIT     1       // 1 = CRC result is valid

// CRC-16-CCITT-FALSE Constants
`define CRC16_POLY               16'h1021 // x^16 + x^12 + x^5 + 1
`define CRC16_INIT_VAL           16'hFFFF // CCITT-FALSE initial seed

`endif // CRC_DEFINES_VH
