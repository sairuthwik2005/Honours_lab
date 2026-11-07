/*
 * ============================================================================
 * File: spi_top.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Top-Level SPI Master IP Core
 *              Integrates:
 *                1. spi_core (Mode 0 Master, FIFO drain, MISO capture, safety rule)
 *                2. spi_axi4 (Full AXI4 Subordinate Interface, Slot M07)
 *                3. Direct streaming handshake to TX FIFO
 *                4. Physical SPI pins (SCLK, CS_N, MOSI, MISO)
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "spi_defines.vh"

module spi_top #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 8,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst,      // Active-high synchronous reset
    input  wire                  rst_n,    // Active-low reset

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Interface (Connected to Interconnect M07)
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
    // Direct TX FIFO Streaming Interface
    // ------------------------------------------------------------------------
    output wire                  fifo_rd_en,      // Read request from SPI to FIFO
    input  wire [7:0]            fifo_rd_data,    // Packet byte from FIFO
    input  wire                  fifo_data_valid, // Byte valid pulse from FIFO
    input  wire                  fifo_empty,      // FIFO empty indication

    // ------------------------------------------------------------------------
    // External Physical SPI Pins
    // ------------------------------------------------------------------------
    output wire                  spi_mosi_o,      // Serial Data Out
    input  wire                  spi_miso_i,      // Serial Data In
    output wire                  spi_sclk_o,      // Serial Clock (Mode 0)
    output wire                  spi_cs_no        // Active-Low Chip Select
);

    wire        spi_enable;
    wire        spi_start;
    wire        spi_mode;
    wire [15:0] spi_length;
    wire [15:0] spi_clk_div;
    wire        spi_abort;
    wire        spi_clear_status;
    wire        rx_read_pulse;
    wire        spi_busy;
    wire        spi_done;
    wire [7:0]  spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_rx_overrun;

    wire eff_rst_n = rst_n & (~rst);

    // Instantiate SPI Protocol Core
    spi_core u_spi_core (
        .clk              (clk),
        .rst_n            (eff_rst_n),
        .spi_enable       (spi_enable),
        .spi_start        (spi_start),
        .spi_mode         (spi_mode),
        .spi_length       (spi_length),
        .spi_clk_div      (spi_clk_div),
        .spi_abort        (spi_abort),
        .spi_clear_status (spi_clear_status),
        .rx_read_pulse    (rx_read_pulse),
        .spi_busy         (spi_busy),
        .spi_done         (spi_done),
        .spi_rx_data      (spi_rx_data),
        .spi_rx_valid     (spi_rx_valid),
        .spi_rx_overrun   (spi_rx_overrun),
        .fifo_rd_en       (fifo_rd_en),
        .fifo_rd_data     (fifo_rd_data),
        .fifo_data_valid  (fifo_data_valid),
        .fifo_empty       (fifo_empty),
        .spi_mosi_o       (spi_mosi_o),
        .spi_miso_i       (spi_miso_i),
        .spi_sclk_o       (spi_sclk_o),
        .spi_cs_no        (spi_cs_no)
    );

    // Instantiate AXI4 Subordinate Interface
    spi_axi4 #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .STRB_WIDTH (STRB_WIDTH)
    ) u_spi_axi4 (
        .clk              (clk),
        .rst              (rst),
        .rst_n            (eff_rst_n),
        .s_axi_awid       (s_axi_awid),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awlen      (s_axi_awlen),
        .s_axi_awsize     (s_axi_awsize),
        .s_axi_awburst    (s_axi_awburst),
        .s_axi_awlock     (s_axi_awlock),
        .s_axi_awcache    (s_axi_awcache),
        .s_axi_awprot     (s_axi_awprot),
        .s_axi_awqos      (s_axi_awqos),
        .s_axi_awregion   (s_axi_awregion),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wlast      (s_axi_wlast),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bid        (s_axi_bid),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_arid       (s_axi_arid),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arlen      (s_axi_arlen),
        .s_axi_arsize     (s_axi_arsize),
        .s_axi_arburst    (s_axi_arburst),
        .s_axi_arlock     (s_axi_arlock),
        .s_axi_arcache    (s_axi_arcache),
        .s_axi_arprot     (s_axi_arprot),
        .s_axi_arqos      (s_axi_arqos),
        .s_axi_arregion   (s_axi_arregion),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rid        (s_axi_rid),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rlast      (s_axi_rlast),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        .spi_enable       (spi_enable),
        .spi_start        (spi_start),
        .spi_mode         (spi_mode),
        .spi_length       (spi_length),
        .spi_clk_div      (spi_clk_div),
        .spi_abort        (spi_abort),
        .spi_clear_status (spi_clear_status),
        .rx_read_pulse    (rx_read_pulse),
        .spi_busy         (spi_busy),
        .spi_done         (spi_done),
        .spi_rx_data      (spi_rx_data),
        .spi_rx_valid     (spi_rx_valid),
        .spi_rx_overrun   (spi_rx_overrun)
    );

endmodule

`default_nettype wire
