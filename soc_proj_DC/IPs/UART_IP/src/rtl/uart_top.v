/*
 * ============================================================================
 * File: uart_top.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Top-Level UART Subsystem with Full AXI4 Interface
 *              Integrates:
 *                1. axi4_to_axi4lite_uart_adapter (decoupled AW/W deadlock fix)
 *                2. axi_uart_top (Core UART receiver & transmitter)
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module uart_top #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 8,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst,      // Active-high synchronous reset
    input  wire                  rst_n,    // Active-low reset (optional)

    // AXI4 Subordinate Interface (Connected to Interconnect M02)
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

    // External UART Serial Pins
    input  wire                  uart_rx_i,
    output wire                  uart_tx_o,
    output wire                  uart_irq_o
);

    wire sys_rst = rst || (!rst_n);
    wire sys_rst_n = !sys_rst;

    // Internal wires between adapter and axi_uart_top
    wire        u_arvalid;
    wire        u_arready;
    wire [11:0] u_arid;
    wire [4:0]  u_araddr;

    wire [11:0] u_rid;
    wire [31:0] u_rdata;
    wire [1:0]  u_rresp;
    wire        u_rvalid;
    wire        u_rready;

    wire        u_awvalid;
    wire        u_awready;
    wire [11:0] u_awid;
    wire [4:0]  u_awaddr;

    wire        u_wvalid;
    wire        u_wready;
    wire [31:0] u_wdata;
    wire [3:0]  u_wstrb;

    wire [11:0] u_bid;
    wire [1:0]  u_bresp;
    wire        u_bvalid;
    wire        u_bready;

    // Instantiate AXI4 to UART Adapter
    axi4_to_axi4lite_uart_adapter #(
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .STRB_WIDTH      (STRB_WIDTH),
        .S_ID_WIDTH      (ID_WIDTH),
        .UART_ID_WIDTH   (12),
        .UART_ADDR_WIDTH (5)
    ) u_adapter (
        .clk                (clk),
        .rst                (sys_rst),
        .s_axi_awid         (s_axi_awid),
        .s_axi_awaddr       (s_axi_awaddr),
        .s_axi_awlen        (s_axi_awlen),
        .s_axi_awsize       (s_axi_awsize),
        .s_axi_awburst      (s_axi_awburst),
        .s_axi_awlock       (s_axi_awlock),
        .s_axi_awcache      (s_axi_awcache),
        .s_axi_awprot       (s_axi_awprot),
        .s_axi_awqos        (s_axi_awqos),
        .s_axi_awregion     (s_axi_awregion),
        .s_axi_awvalid      (s_axi_awvalid),
        .s_axi_awready      (s_axi_awready),
        .s_axi_wdata        (s_axi_wdata),
        .s_axi_wstrb        (s_axi_wstrb),
        .s_axi_wlast        (s_axi_wlast),
        .s_axi_wvalid       (s_axi_wvalid),
        .s_axi_wready       (s_axi_wready),
        .s_axi_bid          (s_axi_bid),
        .s_axi_bresp        (s_axi_bresp),
        .s_axi_bvalid       (s_axi_bvalid),
        .s_axi_bready       (s_axi_bready),
        .s_axi_arid         (s_axi_arid),
        .s_axi_araddr       (s_axi_araddr),
        .s_axi_arlen        (s_axi_arlen),
        .s_axi_arsize       (s_axi_arsize),
        .s_axi_arburst      (s_axi_arburst),
        .s_axi_arlock       (s_axi_arlock),
        .s_axi_arcache      (s_axi_arcache),
        .s_axi_arprot       (s_axi_arprot),
        .s_axi_arqos        (s_axi_arqos),
        .s_axi_arregion     (s_axi_arregion),
        .s_axi_arvalid      (s_axi_arvalid),
        .s_axi_arready      (s_axi_arready),
        .s_axi_rid          (s_axi_rid),
        .s_axi_rdata        (s_axi_rdata),
        .s_axi_rresp        (s_axi_rresp),
        .s_axi_rlast        (s_axi_rlast),
        .s_axi_rvalid       (s_axi_rvalid),
        .s_axi_rready       (s_axi_rready),
        .axi_uart_arvalid_i (u_arvalid),
        .axi_uart_arready_o (u_arready),
        .axi_uart_arid_i    (u_arid),
        .axi_uart_araddr_i  (u_araddr),
        .axi_uart_rid_o     (u_rid),
        .axi_uart_rdata_o   (u_rdata),
        .axi_uart_rresp_o   (u_rresp),
        .axi_uart_rvalid_o  (u_rvalid),
        .axi_uart_rready_i  (u_rready),
        .axi_uart_awvalid_i (u_awvalid),
        .axi_uart_awready_o (u_awready),
        .axi_uart_awid_i    (u_awid),
        .axi_uart_awaddr_i  (u_awaddr),
        .axi_uart_wvalid_i  (u_wvalid),
        .axi_uart_wready_o  (u_wready),
        .axi_uart_wdata_i   (u_wdata),
        .axi_uart_wstrb_i   (u_wstrb),
        .axi_uart_bid_o     (u_bid),
        .axi_uart_bresp_o   (u_bresp),
        .axi_uart_bvalid_o  (u_bvalid),
        .axi_uart_bready_i  (u_bready)
    );

    // Instantiate Open-Source AXI UART Top
    axi_uart_top u_axi_uart_top (
        .fixed_clk_i      (clk),
        .axi_aclk_i       (clk),
        .axi_aresetn_i    (sys_rst_n),
        .axi_arid_i       (u_arid),
        .axi_araddr_i     (u_araddr),
        .axi_arvalid_i    (u_arvalid),
        .axi_arready_o    (u_arready),
        .axi_rid_o        (u_rid),
        .axi_rdata_o      (u_rdata),
        .axi_rresp_o      (u_rresp),
        .axi_rvalid_o     (u_rvalid),
        .axi_rready_i     (u_rready),
        .axi_awid_i       (u_awid),
        .axi_awaddr_i     (u_awaddr),
        .axi_awvalid_i    (u_awvalid),
        .axi_awready_o    (u_awready),
        .axi_wdata_i      (u_wdata),
        .axi_wstrb_i      (u_wstrb),
        .axi_wvalid_i     (u_wvalid),
        .axi_wready_o     (u_wready),
        .axi_bid_o        (u_bid),
        .axi_bresp_o      (u_bresp),
        .axi_bvalid_o     (u_bvalid),
        .axi_bready_i     (u_bready),
        .read_interrupt_o (uart_irq_o),
        .uart_rx_i        (uart_rx_i),
        .uart_tx_o        (uart_tx_o)
    );

endmodule

`default_nettype wire
