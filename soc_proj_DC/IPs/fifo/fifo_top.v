/*
 * ============================================================================
 * File: fifo_top.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Top-Level 16x8 TX Streaming FIFO IP Core
 *              Integrates:
 *                1. fifo_core (16x8 synchronous FIFO, level 0..16, overflow/underflow)
 *                2. fifo_axi4 (Full AXI4 Subordinate Interface, Slot M06)
 *                3. Direct streaming port to SPI Master (rd_en, rd_data, data_valid)
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "fifo_defines.vh"

module fifo_top #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 8,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
    parameter integer FIFO_DEPTH = `FIFO_DEPTH,
    parameter integer FIFO_WIDTH = `FIFO_WIDTH
)(
    input  wire                  clk,
    input  wire                  rst,      // Active-high synchronous reset
    input  wire                  rst_n,    // Active-low reset

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Interface (Connected to Interconnect M06)
    // ------------------------------------------------------------------------
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
    output wire                  s_axi_awready,

    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    output wire [ID_WIDTH-1:0]   s_axi_bid,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,

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
    output wire                  s_axi_arready,

    output wire [ID_WIDTH-1:0]   s_axi_rid,
    output wire [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rlast,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,

    // ------------------------------------------------------------------------
    // Direct Synchronous Streaming Read Port (to SPI Master)
    // ------------------------------------------------------------------------
    input  wire                  fifo_rd_en,      // Read pulse from SPI
    output wire [FIFO_WIDTH-1:0] fifo_rd_data,    // Transmit byte
    output wire                  fifo_data_valid, // Pulses when fifo_rd_data is valid
    output wire                  fifo_empty,      // SPI must not read when empty
    output wire                  fifo_full        // Exposed to top/status
);

    wire        fifo_clear;
    wire        fifo_clear_status;
    wire        fifo_wr_en;
    wire [7:0]  fifo_wr_data;
    wire [4:0]  fifo_level;
    wire        fifo_overflow;
    wire        fifo_underflow;

    wire eff_rst_n = rst_n & (~rst);

    // Instantiate FIFO Storage Core
    fifo_core #(
        .DEPTH (FIFO_DEPTH),
        .WIDTH (FIFO_WIDTH)
    ) u_fifo_core (
        .clk               (clk),
        .rst_n             (eff_rst_n),
        .fifo_clear        (fifo_clear),
        .fifo_clear_status (fifo_clear_status),
        .fifo_full         (fifo_full),
        .fifo_empty        (fifo_empty),
        .fifo_level        (fifo_level),
        .fifo_overflow     (fifo_overflow),
        .fifo_underflow    (fifo_underflow),
        .fifo_wr_en        (fifo_wr_en),
        .fifo_wr_data      (fifo_wr_data),
        .fifo_rd_en        (fifo_rd_en),
        .fifo_rd_data      (fifo_rd_data),
        .fifo_data_valid   (fifo_data_valid)
    );

    // Instantiate AXI4 Subordinate Interface
    fifo_axi4 #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .STRB_WIDTH (STRB_WIDTH)
    ) u_fifo_axi4 (
        .clk               (clk),
        .rst               (rst),
        .rst_n             (eff_rst_n),
        .s_axi_awid        (s_axi_awid),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awlen       (s_axi_awlen),
        .s_axi_awsize      (s_axi_awsize),
        .s_axi_awburst     (s_axi_awburst),
        .s_axi_awlock      (s_axi_awlock),
        .s_axi_awcache     (s_axi_awcache),
        .s_axi_awprot      (s_axi_awprot),
        .s_axi_awqos       (s_axi_awqos),
        .s_axi_awregion    (s_axi_awregion),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wlast       (s_axi_wlast),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        .s_axi_bid         (s_axi_bid),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        .s_axi_bready      (s_axi_bready),
        .s_axi_arid        (s_axi_arid),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arlen       (s_axi_arlen),
        .s_axi_arsize      (s_axi_arsize),
        .s_axi_arburst     (s_axi_arburst),
        .s_axi_arlock      (s_axi_arlock),
        .s_axi_arcache     (s_axi_arcache),
        .s_axi_arprot      (s_axi_arprot),
        .s_axi_arqos       (s_axi_arqos),
        .s_axi_arregion    (s_axi_arregion),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        .s_axi_rid         (s_axi_rid),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rlast       (s_axi_rlast),
        .s_axi_rvalid      (s_axi_rvalid),
        .s_axi_rready      (s_axi_rready),
        .fifo_clear        (fifo_clear),
        .fifo_clear_status (fifo_clear_status),
        .fifo_wr_en        (fifo_wr_en),
        .fifo_wr_data      (fifo_wr_data),
        .fifo_full         (fifo_full),
        .fifo_empty        (fifo_empty),
        .fifo_level        (fifo_level),
        .fifo_overflow     (fifo_overflow),
        .fifo_underflow    (fifo_underflow)
    );

endmodule

`default_nettype wire
