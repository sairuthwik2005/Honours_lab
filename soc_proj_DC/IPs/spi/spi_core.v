/*
 * ============================================================================
 * File: spi_core.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: SPI Mode 0 Master Core with Direct TX FIFO Interface
 *              Mode 0: CPOL=0, CPHA=0 (SCLK idles low, sample on rising edge)
 *              WRITE Mode: Drains TX FIFO and serializes to MOSI
 *              READBACK Mode: Transmits 0x00 dummy bytes, captures MISO,
 *                             observes RX backpressure safety rule
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "spi_defines.vh"

module spi_core (
    input  wire        clk,
    input  wire        rst_n,            // Active-low asynchronous reset

    // Register Configuration
    input  wire        spi_enable,       // Controller enable
    input  wire        spi_start,        // Start transaction pulse
    input  wire        spi_mode,         // 0=WRITE, 1=READBACK
    input  wire [15:0] spi_length,       // Transfer byte count
    input  wire [15:0] spi_clk_div,      // Half-period clock divisor
    input  wire        spi_abort,        // Emergency transaction abort
    input  wire        spi_clear_status, // Clear done / error status
    input  wire        rx_read_pulse,    // Reading RX_DATA clears spi_rx_valid

    // Status Outputs
    output reg         spi_busy,         // Active during transfer
    output reg         spi_done,         // Asserted upon completion
    output reg  [7:0]  spi_rx_data,      // Most recently received byte
    output reg         spi_rx_valid,     // Byte available flag
    output reg         spi_rx_overrun,   // Latched overrun error flag

    // Direct TX FIFO Streaming Interface
    output reg         fifo_rd_en,       // Read pulse to FIFO
    input  wire [7:0]  fifo_rd_data,     // Byte from FIFO
    input  wire        fifo_data_valid,  // Asserted by FIFO when rd_data valid
    input  wire        fifo_empty,       // FIFO empty flag

    // External SPI Physical Pins
    output reg         spi_mosi_o,       // Serial Master Out Slave In
    input  wire        spi_miso_i,       // Serial Master In Slave Out
    output reg         spi_sclk_o,       // Serial Clock (Mode 0)
    output reg         spi_cs_no         // Active-Low Chip Select
);

    // FSM States
    localparam [2:0] S_IDLE       = 3'd0;
    localparam [2:0] S_GET_BYTE   = 3'd1;
    localparam [2:0] S_WAIT_FIFO  = 3'd2;
    localparam [2:0] S_PAUSE_RX   = 3'd3;
    localparam [2:0] S_SHIFT      = 3'd4;
    localparam [2:0] S_DONE       = 3'd5;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [15:0] bytes_transferred;
    reg [2:0]  bit_idx; // 7 down to 0
    reg [7:0]  tx_shift;
    reg [7:0]  rx_shift;
    reg        sclk_phase; // 0 = low half, 1 = high half

    // SCLK divider minimum guard (at least 1 clock per half-cycle)
    wire [15:0] div_val = (spi_clk_div == 16'd0) ? 16'd1 : spi_clk_div;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            spi_busy          <= 1'b0;
            spi_done          <= 1'b0;
            spi_rx_data       <= 8'h00;
            spi_rx_valid      <= 1'b0;
            spi_rx_overrun    <= 1'b0;
            fifo_rd_en        <= 1'b0;
            spi_mosi_o        <= 1'b0;
            spi_sclk_o        <= 1'b0;
            spi_cs_no         <= 1'b1;
            clk_cnt           <= 16'd0;
            bytes_transferred <= 16'd0;
            bit_idx           <= 3'd7;
            tx_shift          <= 8'h00;
            rx_shift          <= 8'h00;
            sclk_phase        <= 1'b0;
        end else begin
            // Pulse clears
            fifo_rd_en <= 1'b0;

            if (rx_read_pulse) begin
                spi_rx_valid <= 1'b0;
            end

            if (spi_clear_status) begin
                spi_done       <= 1'b0;
                spi_rx_overrun <= 1'b0;
            end

            if (spi_abort) begin
                state      <= S_IDLE;
                spi_busy   <= 1'b0;
                spi_cs_no  <= 1'b1;
                spi_sclk_o <= 1'b0;
                spi_mosi_o <= 1'b0;
                clk_cnt    <= 16'd0;
            end else begin
                case (state)
                    S_IDLE: begin
                        spi_cs_no  <= 1'b1;
                        spi_sclk_o <= 1'b0;
                        spi_mosi_o <= 1'b0;
                        clk_cnt    <= 16'd0;

                        if (spi_enable && spi_start && (spi_length > 16'd0)) begin
                            spi_busy          <= 1'b1;
                            spi_done          <= 1'b0;
                            spi_cs_no         <= 1'b0; // Assert CS
                            bytes_transferred <= 16'd0;

                            if (spi_mode == 1'b0) begin
                                // WRITE mode: request first byte from FIFO
                                state <= S_GET_BYTE;
                            end else begin
                                // READBACK mode: check RX safety backpressure
                                state <= S_PAUSE_RX;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // WRITE Mode: Fetch byte from FIFO
                    // ---------------------------------------------------------
                    S_GET_BYTE: begin
                        if (!fifo_empty) begin
                            fifo_rd_en <= 1'b1;
                            state      <= S_WAIT_FIFO;
                        end
                        // If empty, wait until CPU writes byte into FIFO
                    end

                    S_WAIT_FIFO: begin
                        if (fifo_data_valid) begin
                            tx_shift   <= fifo_rd_data;
                            spi_mosi_o <= fifo_rd_data[7]; // Setup MSB before clock
                            bit_idx    <= 3'd7;
                            clk_cnt    <= 16'd0;
                            sclk_phase <= 1'b0;
                            state      <= S_SHIFT;
                        end
                    end

                    // ---------------------------------------------------------
                    // READBACK Mode: Safety Rule Check (Pause if RX not read)
                    // ---------------------------------------------------------
                    S_PAUSE_RX: begin
                        if (!spi_rx_valid || rx_read_pulse) begin
                            tx_shift   <= 8'h00; // Automatic 0x00 dummy byte
                            spi_mosi_o <= 1'b0;
                            rx_shift   <= 8'h00;
                            bit_idx    <= 3'd7;
                            clk_cnt    <= 16'd0;
                            sclk_phase <= 1'b0;
                            state      <= S_SHIFT;
                        end
                    end

                    // ---------------------------------------------------------
                    // Shift Data Bits (Mode 0: SCLK low -> SCLK high -> SCLK low)
                    // ---------------------------------------------------------
                    S_SHIFT: begin
                        if (clk_cnt < div_val - 16'd1) begin
                            clk_cnt <= clk_cnt + 16'd1;
                        end else begin
                            clk_cnt <= 16'd0;
                            if (sclk_phase == 1'b0) begin
                                // Low-to-High transition: SCLK rises, sample MISO
                                spi_sclk_o <= 1'b1;
                                sclk_phase <= 1'b1;
                                if (spi_mode == 1'b1) begin
                                    // In READBACK, sample incoming bit MSB-first
                                    rx_shift <= {rx_shift[6:0], spi_miso_i};
                                end
                            end else begin
                                // High-to-Low transition: SCLK falls, shift next MOSI bit
                                spi_sclk_o <= 1'b0;
                                sclk_phase <= 1'b0;

                                if (bit_idx > 3'd0) begin
                                    bit_idx    <= bit_idx - 3'd1;
                                    tx_shift   <= {tx_shift[6:0], 1'b0};
                                    spi_mosi_o <= tx_shift[6];
                                end else begin
                                    // Byte transfer complete!
                                    bytes_transferred <= bytes_transferred + 16'd1;

                                    if (spi_mode == 1'b1) begin
                                        // Store READBACK byte
                                        spi_rx_data <= rx_shift;
                                        if (spi_rx_valid && !rx_read_pulse)
                                            spi_rx_overrun <= 1'b1;
                                        spi_rx_valid <= 1'b1;
                                    end

                                    if (bytes_transferred + 16'd1 == spi_length) begin
                                        // All bytes finished
                                        state <= S_DONE;
                                    end else begin
                                        // Prepare next byte
                                        if (spi_mode == 1'b0)
                                            state <= S_GET_BYTE;
                                        else
                                            state <= S_PAUSE_RX;
                                    end
                                end
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // Transaction Completed
                    // ---------------------------------------------------------
                    S_DONE: begin
                        spi_cs_no  <= 1'b1; // Deassert CS
                        spi_sclk_o <= 1'b0;
                        spi_mosi_o <= 1'b0;
                        spi_busy   <= 1'b0;
                        spi_done   <= 1'b1;
                        state      <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
