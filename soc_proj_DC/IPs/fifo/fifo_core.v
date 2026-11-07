/*
 * ============================================================================
 * File: fifo_core.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: 16-entry x 8-bit Synchronous Transmit Streaming FIFO Core
 *              Synchronous read handshake with fifo_data_valid pulse.
 *              Sticky overflow and underflow detection.
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "fifo_defines.vh"

module fifo_core #(
    parameter integer DEPTH = `FIFO_DEPTH, // 16 entries
    parameter integer WIDTH = `FIFO_WIDTH  // 8 bits
)(
    input  wire             clk,
    input  wire             rst_n,            // Active-low asynchronous reset

    // Control and Status
    input  wire             fifo_clear,       // Clears pointers, count, contents
    input  wire             fifo_clear_status,// Clears overflow/underflow flags
    output wire             fifo_full,        // 16 entries occupied
    output wire             fifo_empty,       // 0 entries occupied
    output reg  [4:0]       fifo_level,       // Occupancy from 0 through 16
    output reg              fifo_overflow,    // Sticky write overflow flag
    output reg              fifo_underflow,   // Sticky read underflow flag

    // Write Port (CPU via AXI)
    input  wire             fifo_wr_en,       // Write enable
    input  wire [WIDTH-1:0] fifo_wr_data,     // Outgoing packet byte

    // Read Port (Direct synchronous stream to SPI Master)
    input  wire             fifo_rd_en,       // Read request from SPI
    output reg  [WIDTH-1:0] fifo_rd_data,     // Byte delivered to SPI
    output reg              fifo_data_valid   // Pulses high when fifo_rd_data is valid
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [3:0]       wr_ptr;
    reg [3:0]       rd_ptr;

    assign fifo_full  = (fifo_level == 5'd16);
    assign fifo_empty = (fifo_level == 5'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr          <= 4'd0;
            rd_ptr          <= 4'd0;
            fifo_level      <= 5'd0;
            fifo_overflow   <= 1'b0;
            fifo_underflow  <= 1'b0;
            fifo_rd_data    <= {WIDTH{1'b0}};
            fifo_data_valid <= 1'b0;
        end else begin
            // Default pulse clear
            fifo_data_valid <= 1'b0;

            if (fifo_clear_status) begin
                fifo_overflow  <= 1'b0;
                fifo_underflow <= 1'b0;
            end

            if (fifo_clear) begin
                wr_ptr          <= 4'd0;
                rd_ptr          <= 4'd0;
                fifo_level      <= 5'd0;
                fifo_rd_data    <= {WIDTH{1'b0}};
                fifo_data_valid <= 1'b0;
            end else begin
                case ({fifo_wr_en, fifo_rd_en})
                    2'b10: begin // Write only
                        if (!fifo_full) begin
                            mem[wr_ptr] <= fifo_wr_data;
                            wr_ptr      <= wr_ptr + 4'd1;
                            fifo_level  <= fifo_level + 5'd1;
                        end else begin
                            fifo_overflow <= 1'b1; // Illegal write while full
                        end
                    end

                    2'b01: begin // Read only
                        if (!fifo_empty) begin
                            fifo_rd_data    <= mem[rd_ptr];
                            fifo_data_valid <= 1'b1;
                            rd_ptr          <= rd_ptr + 4'd1;
                            fifo_level      <= fifo_level - 5'd1;
                        end else begin
                            fifo_underflow  <= 1'b1; // Illegal read while empty
                            fifo_data_valid <= 1'b0;
                        end
                    end

                    2'b11: begin // Simultaneous write and read
                        if (fifo_empty) begin
                            // Underflow on read, write succeeds
                            mem[wr_ptr]     <= fifo_wr_data;
                            wr_ptr          <= wr_ptr + 4'd1;
                            fifo_level      <= fifo_level + 5'd1;
                            fifo_underflow  <= 1'b1;
                            fifo_data_valid <= 1'b0;
                        end else if (fifo_full) begin
                            // Overflow on write, read succeeds
                            fifo_rd_data    <= mem[rd_ptr];
                            fifo_data_valid <= 1'b1;
                            rd_ptr          <= rd_ptr + 4'd1;
                            fifo_level      <= fifo_level - 5'd1;
                            fifo_overflow   <= 1'b1;
                        end else begin
                            // Normal simultaneous write and read: level unchanged
                            mem[wr_ptr]     <= fifo_wr_data;
                            wr_ptr          <= wr_ptr + 4'd1;
                            fifo_rd_data    <= mem[rd_ptr];
                            fifo_data_valid <= 1'b1;
                            rd_ptr          <= rd_ptr + 4'd1;
                        end
                    end

                    default: begin
                        // Idle
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
