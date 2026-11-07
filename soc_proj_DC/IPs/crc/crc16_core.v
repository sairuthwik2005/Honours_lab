/*
 * ============================================================================
 * File: crc16_core.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: CRC-16-CCITT-FALSE Hardware Accelerator Engine
 *              Polynomial: 0x1021 (x^16 + x^12 + x^5 + 1)
 *              Initial Value: 0xFFFF
 *              refin: false, refout: false, xorout: 0x0000
 *              1-cycle 8-bit parallel LFSR execution
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "crc_defines.vh"

module crc16_core (
    input  wire        clk,
    input  wire        rst_n,            // Active-low asynchronous reset

    // Control and Data Signals
    input  wire        crc_init,         // Loads CRC state with 0xFFFF
    input  wire [7:0]  crc_data,         // Next protected packet byte
    input  wire        crc_data_valid,   // Updates CRC using crc_data
    input  wire        crc_clear_status, // Clears result-valid status

    // Status and Result Signals
    output reg  [15:0] crc_result,       // Current/final CRC value
    output reg         crc_result_valid, // Result is valid after accepted update
    output wire        crc_busy          // Active during multi-cycle processing (0 here)
);

    assign crc_busy = 1'b0; // Single-cycle parallel computation, never stalls

    // 8-bit parallel CRC-16-CCITT-FALSE combinational function
    function [15:0] next_crc16;
        input [15:0] current_crc;
        input [7:0]  data_byte;
        reg   [15:0] c;
        integer      i;
        begin
            c = current_crc ^ {data_byte, 8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[15])
                    c = ((c << 1) ^ `CRC16_POLY);
                else
                    c = (c << 1);
            end
            next_crc16 = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_result       <= `CRC16_INIT_VAL;
            crc_result_valid <= 1'b0;
        end else begin
            if (crc_init) begin
                crc_result       <= `CRC16_INIT_VAL;
                crc_result_valid <= 1'b1;
            end else if (crc_data_valid) begin
                crc_result       <= next_crc16(crc_result, crc_data);
                crc_result_valid <= 1'b1;
            end else if (crc_clear_status) begin
                crc_result_valid <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
