/*
 * ============================================================================
 * File: spi_defines.vh
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Register definitions and bit masks for SPI Master IP Core
 * Base Address: 0x2000_5000 (Interconnect Slot M07, 4KB space)
 * ============================================================================
 */

`ifndef SPI_DEFINES_VH
`define SPI_DEFINES_VH

// Base Address in System Interconnect
`define SPI_BASE_ADDR            32'h2000_5000

// Register Byte Offsets (word-aligned)
`define SPI_REG_CTRL             8'h00   // [R/W] Control Register
`define SPI_REG_STATUS           8'h04   // [RO]  Status Register
`define SPI_REG_LENGTH           8'h08   // [R/W] Transfer Byte Length Register
`define SPI_REG_CLK_DIV          8'h0C   // [R/W] Clock Divisor Register
`define SPI_REG_RX_DATA          8'h10   // [RO]  Received Byte Data Port (read clears rx_valid)

// SPI_REG_CTRL [0x00] Bit Definitions
`define SPI_CTRL_ENABLE_BIT      0       // 1 = Enable SPI Controller
`define SPI_CTRL_START_BIT       1       // 1 = Start transaction (auto-clears)
`define SPI_CTRL_MODE_BIT        2       // 0 = WRITE mode, 1 = READBACK mode
`define SPI_CTRL_ABORT_BIT       3       // 1 = Abort transaction (auto-clears)
`define SPI_CTRL_CLEAR_STAT_BIT  4       // 1 = Clear done/error flags (auto-clears)

// SPI_REG_STATUS [0x04] Bit Definitions
`define SPI_STATUS_BUSY_BIT      0       // 1 = SPI transfer active
`define SPI_STATUS_DONE_BIT      1       // 1 = SPI transfer completed
`define SPI_STATUS_RX_VALID_BIT  2       // 1 = READBACK byte available in RX_DATA
`define SPI_STATUS_RX_OVERRUN_BIT 3      // 1 = RX overrun error (unconsumed byte)

// Default Configuration Values
`define SPI_DEFAULT_CLK_DIV      16'd2   // 100MHz / (2 * (2 + 1)) = 16.6 MHz or counter threshold

`endif // SPI_DEFINES_VH
