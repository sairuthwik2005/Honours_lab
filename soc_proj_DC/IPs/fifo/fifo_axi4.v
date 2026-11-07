/*
 * ============================================================================
 * File: fifo_axi4.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Full AXI4 Subordinate Interface for 16x8 TX FIFO
 *              Base Address: 0x2000_4000 (Interconnect Slot M06)
 *              Rejects multi-beat burst attempts with SLVERR.
 *              Decoupled AW and W channels with ID reflection.
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "fifo_defines.vh"

module fifo_axi4 #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 8,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst,      // Active-high synchronous reset
    input  wire                  rst_n,    // Active-low reset

    // AXI4 Write Address Channel
    input  wire [ID_WIDTH-1:0]   s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [3:0]            s_axi_awcache,
    input  wire [2:0]            s_axi_awprot,
    input  wire [3:0]            s_axi_awqos,
    input  wire [3:0]            s_axi_awregion,
    input  wire                  s_axi_awvalid,
    output reg                   s_axi_awready,

    // AXI4 Write Data Channel
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,

    // AXI4 Write Response Channel
    output reg  [ID_WIDTH-1:0]   s_axi_bid,
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // AXI4 Read Address Channel
    input  wire [ID_WIDTH-1:0]   s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire                  s_axi_arlock,
    input  wire [3:0]            s_axi_arcache,
    input  wire [2:0]            s_axi_arprot,
    input  wire [3:0]            s_axi_arqos,
    input  wire [3:0]            s_axi_arregion,
    input  wire                  s_axi_arvalid,
    output reg                   s_axi_arready,

    // AXI4 Read Data Channel
    output reg  [ID_WIDTH-1:0]   s_axi_rid,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,

    // Core Control Interface
    output reg                   fifo_clear,
    output reg                   fifo_clear_status,
    output reg                   fifo_wr_en,
    output reg  [7:0]            fifo_wr_data,

    // Core Status Interface
    input  wire                  fifo_full,
    input  wire                  fifo_empty,
    input  wire [4:0]            fifo_level,
    input  wire                  fifo_overflow,
    input  wire                  fifo_underflow
);

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    wire reset = rst || (!rst_n);

    // Write Channel Logic
    reg                  aw_captured;
    reg [ID_WIDTH-1:0]   aw_id_reg;
    reg [ADDR_WIDTH-1:0] aw_addr_reg;
    reg                  aw_len_err;

    reg                  w_captured;
    reg [DATA_WIDTH-1:0] w_data_reg;

    wire [ADDR_WIDTH-1:0] eff_addr = aw_captured ? aw_addr_reg : s_axi_awaddr;
    wire [DATA_WIDTH-1:0] eff_data = w_captured  ? w_data_reg  : s_axi_wdata;
    wire                  eff_err  = aw_captured ? aw_len_err  : (s_axi_awlen != 8'd0);
    wire [ID_WIDTH-1:0]   eff_id   = aw_captured ? aw_id_reg   : s_axi_awid;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            s_axi_awready     <= 1'b1;
            s_axi_wready      <= 1'b1;
            s_axi_bvalid      <= 1'b0;
            s_axi_bid         <= {ID_WIDTH{1'b0}};
            s_axi_bresp       <= RESP_OKAY;
            aw_captured       <= 1'b0;
            w_captured        <= 1'b0;
            aw_id_reg         <= {ID_WIDTH{1'b0}};
            aw_addr_reg       <= {ADDR_WIDTH{1'b0}};
            aw_len_err        <= 1'b0;
            w_data_reg        <= {DATA_WIDTH{1'b0}};
            fifo_clear        <= 1'b0;
            fifo_clear_status <= 1'b0;
            fifo_wr_en        <= 1'b0;
            fifo_wr_data      <= 8'h00;
        end else begin
            // Default pulse clears
            fifo_clear        <= 1'b0;
            fifo_clear_status <= 1'b0;
            fifo_wr_en        <= 1'b0;

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Capture Write Address
            if (s_axi_awvalid && s_axi_awready) begin
                aw_captured   <= 1'b1;
                aw_id_reg     <= s_axi_awid;
                aw_addr_reg   <= s_axi_awaddr;
                aw_len_err    <= (s_axi_awlen != 8'd0); // Bursts unsupported
                s_axi_awready <= 1'b0;
            end

            // Capture Write Data
            if (s_axi_wvalid && s_axi_wready) begin
                w_captured   <= 1'b1;
                w_data_reg   <= s_axi_wdata;
                s_axi_wready <= 1'b0;
            end

            // Execute Write Transaction
            if ((aw_captured || (s_axi_awvalid && s_axi_awready)) &&
                (w_captured  || (s_axi_wvalid && s_axi_wready)) &&
                (!s_axi_bvalid || s_axi_bready)) begin

                s_axi_bid    <= eff_id;
                s_axi_bvalid <= 1'b1;

                if (eff_err) begin
                    s_axi_bresp <= RESP_SLVERR;
                end else begin
                    s_axi_bresp <= RESP_OKAY;
                    case (eff_addr[7:0])
                        `FIFO_REG_CTRL: begin
                            if (eff_data[`FIFO_CTRL_CLEAR_BIT])
                                fifo_clear <= 1'b1;
                            if (eff_data[`FIFO_CTRL_CLEAR_STAT_BIT])
                                fifo_clear_status <= 1'b1;
                        end
                        `FIFO_REG_DATA: begin
                            fifo_wr_data <= eff_data[7:0];
                            fifo_wr_en   <= 1'b1;
                        end
                        default: begin
                            // Reserved / Read-only registers
                        end
                    endcase
                end

                aw_captured   <= 1'b0;
                w_captured    <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end
        end
    end

    // Read Channel Logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rid     <= {ID_WIDTH{1'b0}};
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= RESP_OKAY;
            s_axi_rlast   <= 1'b0;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_rlast   <= 1'b0;
                s_axi_arready <= 1'b1;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid  <= 1'b1;
                s_axi_rid     <= s_axi_arid;
                s_axi_rlast   <= 1'b1; // Single-beat
                s_axi_arready <= 1'b0;

                if (s_axi_arlen != 8'd0) begin
                    // Bursts unsupported
                    s_axi_rresp <= RESP_SLVERR;
                    s_axi_rdata <= 32'hDEAD_BEEF;
                end else begin
                    s_axi_rresp <= RESP_OKAY;
                    case (s_axi_araddr[7:0])
                        `FIFO_REG_CTRL: begin
                            s_axi_rdata <= 32'h0;
                        end
                        `FIFO_REG_STATUS: begin
                            s_axi_rdata <= {28'h0, fifo_underflow, fifo_overflow, fifo_empty, fifo_full};
                        end
                        `FIFO_REG_LEVEL: begin
                            s_axi_rdata <= {27'h0, fifo_level};
                        end
                        `FIFO_REG_DATA: begin
                            s_axi_rdata <= 32'h0; // Write-only data port
                        end
                        default: begin
                            s_axi_rdata <= 32'h0;
                        end
                    endcase
                end
            end
        end
    end

endmodule

`default_nettype wire
