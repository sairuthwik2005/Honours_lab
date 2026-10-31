/*
 * ============================================================================
 * File: soc_top.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Synthesizable SoC Top-Level Module
 *
 * Integrates:
 *   1. RISC-V VeeR-EL2 CPU Subsystem (unified 32-bit AXI4 master)
 *   2. axi_interconnect_wrap_1x8 (Full AXI4 1-Master x 8-Slave crossbar)
 *   3. M00: Instruction RAM (64 KiB @ 0x0000_0000)
 *   4. M01: Data RAM (64 KiB @ 0x1000_0000)
 *   5. M02: UART IP (4 KiB @ 0x2000_0000)
 *   6. M03: Timer IP (4 KiB @ 0x2000_1000)
 *   7. M04: GPIO IP (4 KiB @ 0x2000_2000) -> gpio_out_o[7:0]
 *   8. M05: CRC-16-CCITT-FALSE Accelerator (4 KiB @ 0x2000_3000)
 *   9. M06: 16x8 TX Streaming FIFO (4 KiB @ 0x2000_4000)
 *  10. M07: SPI Master IP (4 KiB @ 0x2000_5000)
 *  11. Direct streaming handshake between FIFO and SPI Master
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module soc_top #(
    parameter integer DATA_WIDTH    = 32,
    parameter integer ADDR_WIDTH    = 32,
    parameter integer ID_WIDTH      = 8,
    parameter integer STRB_WIDTH    = DATA_WIDTH / 8,
    parameter         BOOT_HEX_FILE = "" // Optional program image for Instruction RAM
)(
    // Global Clock and Active-Low Reset
    input  wire                  clk_i,
    input  wire                  rst_ni,

    // UART Serial Port
    input  wire                  uart_rx_i,
    output wire                  uart_tx_o,

    // SPI Master External Pins
    output wire                  spi_mosi_o,
    input  wire                  spi_miso_i,
    output wire                  spi_sclk_o,
    output wire                  spi_cs_no,

    // GPIO Sticky Status Outputs
    output wire [7:0]            gpio_out_o,

    // Optional Testbench BFM Override Ports (Tied low / unused in normal execution)
    input  wire                  tb_bypass_cpu,
    input  wire [ID_WIDTH-1:0]   tb_s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] tb_s_axi_awaddr,
    input  wire [7:0]            tb_s_axi_awlen,
    input  wire [2:0]            tb_s_axi_awsize,
    input  wire [1:0]            tb_s_axi_awburst,
    input  wire                  tb_s_axi_awlock,
    input  wire [3:0]            tb_s_axi_awcache,
    input  wire [2:0]            tb_s_axi_awprot,
    input  wire [3:0]            tb_s_axi_awqos,
    input  wire                  tb_s_axi_awvalid,
    output wire                  tb_s_axi_awready,
    input  wire [DATA_WIDTH-1:0] tb_s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] tb_s_axi_wstrb,
    input  wire                  tb_s_axi_wlast,
    input  wire                  tb_s_axi_wvalid,
    output wire                  tb_s_axi_wready,
    output wire [ID_WIDTH-1:0]   tb_s_axi_bid,
    output wire [1:0]            tb_s_axi_bresp,
    output wire                  tb_s_axi_bvalid,
    input  wire                  tb_s_axi_bready,
    input  wire [ID_WIDTH-1:0]   tb_s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] tb_s_axi_araddr,
    input  wire [7:0]            tb_s_axi_arlen,
    input  wire [2:0]            tb_s_axi_arsize,
    input  wire [1:0]            tb_s_axi_arburst,
    input  wire                  tb_s_axi_arlock,
    input  wire [3:0]            tb_s_axi_arcache,
    input  wire [2:0]            tb_s_axi_arprot,
    input  wire [3:0]            tb_s_axi_arqos,
    input  wire                  tb_s_axi_arvalid,
    output wire                  tb_s_axi_arready,
    output wire [ID_WIDTH-1:0]   tb_s_axi_rid,
    output wire [DATA_WIDTH-1:0] tb_s_axi_rdata,
    output wire [1:0]            tb_s_axi_rresp,
    output wire                  tb_s_axi_rlast,
    output wire                  tb_s_axi_rvalid,
    input  wire                  tb_s_axi_rready
);

    // Active-high reset for interconnect & synchronous blocks
    wire rst_high = ~rst_ni;

    // =========================================================================
    // CPU Master Interface Signals (From axi_cpu_subsystem to Interconnect S00)
    // =========================================================================
    wire [ID_WIDTH-1:0]   cpu_awid;
    wire [ADDR_WIDTH-1:0] cpu_awaddr;
    wire [7:0]            cpu_awlen;
    wire [2:0]            cpu_awsize;
    wire [1:0]            cpu_awburst;
    wire                  cpu_awlock;
    wire [3:0]            cpu_awcache;
    wire [2:0]            cpu_awprot;
    wire [3:0]            cpu_awqos;
    wire [3:0]            cpu_awregion;
    wire                  cpu_awvalid;
    wire                  cpu_awready;
    wire [DATA_WIDTH-1:0] cpu_wdata;
    wire [STRB_WIDTH-1:0] cpu_wstrb;
    wire                  cpu_wlast;
    wire                  cpu_wvalid;
    wire                  cpu_wready;
    wire [ID_WIDTH-1:0]   cpu_bid;
    wire [1:0]            cpu_bresp;
    wire                  cpu_bvalid;
    wire                  cpu_bready;
    wire [ID_WIDTH-1:0]   cpu_arid;
    wire [ADDR_WIDTH-1:0] cpu_araddr;
    wire [7:0]            cpu_arlen;
    wire [2:0]            cpu_arsize;
    wire [1:0]            cpu_arburst;
    wire                  cpu_arlock;
    wire [3:0]            cpu_arcache;
    wire [2:0]            cpu_arprot;
    wire [3:0]            cpu_arqos;
    wire [3:0]            cpu_arregion;
    wire                  cpu_arvalid;
    wire                  cpu_arready;
    wire [ID_WIDTH-1:0]   cpu_rid;
    wire [DATA_WIDTH-1:0] cpu_rdata;
    wire [1:0]            cpu_rresp;
    wire                  cpu_rlast;
    wire                  cpu_rvalid;
    wire                  cpu_rready;

    // Instantiate RISC-V VeeR-EL2 CPU Subsystem
    axi_cpu_subsystem u_cpu_subsystem (
        .clk             (clk_i),
        .rst_n           (rst_ni & ~tb_bypass_cpu),
        .m_axi_awid      (cpu_awid),
        .m_axi_awaddr    (cpu_awaddr),
        .m_axi_awlen     (cpu_awlen),
        .m_axi_awsize    (cpu_awsize),
        .m_axi_awburst   (cpu_awburst),
        .m_axi_awlock    (cpu_awlock),
        .m_axi_awcache   (cpu_awcache),
        .m_axi_awprot    (cpu_awprot),
        .m_axi_awqos     (cpu_awqos),
        .m_axi_awregion  (cpu_awregion),
        .m_axi_awvalid   (cpu_awvalid),
        .m_axi_awready   (cpu_awready),
        .m_axi_wdata     (cpu_wdata),
        .m_axi_wstrb     (cpu_wstrb),
        .m_axi_wlast     (cpu_wlast),
        .m_axi_wvalid    (cpu_wvalid),
        .m_axi_wready    (cpu_wready),
        .m_axi_bid       (cpu_bid),
        .m_axi_bresp     (cpu_bresp),
        .m_axi_bvalid    (cpu_bvalid),
        .m_axi_bready    (cpu_bready),
        .m_axi_arid      (cpu_arid),
        .m_axi_araddr    (cpu_araddr),
        .m_axi_arlen     (cpu_arlen),
        .m_axi_arsize    (cpu_arsize),
        .m_axi_arburst   (cpu_arburst),
        .m_axi_arlock    (cpu_arlock),
        .m_axi_arcache   (cpu_arcache),
        .m_axi_arprot    (cpu_arprot),
        .m_axi_arqos     (cpu_arqos),
        .m_axi_arregion  (cpu_arregion),
        .m_axi_arvalid   (cpu_arvalid),
        .m_axi_arready   (cpu_arready),
        .m_axi_rid       (cpu_rid),
        .m_axi_rdata     (cpu_rdata),
        .m_axi_rresp     (cpu_rresp),
        .m_axi_rlast     (cpu_rlast),
        .m_axi_rvalid    (cpu_rvalid),
        .m_axi_rready    (cpu_rready)
    );

    // Multiplex CPU vs Testbench BFM for Interconnect S00
    wire [ID_WIDTH-1:0]   s00_awid     = tb_bypass_cpu ? tb_s_axi_awid     : cpu_awid;
    wire [ADDR_WIDTH-1:0] s00_awaddr   = tb_bypass_cpu ? tb_s_axi_awaddr   : cpu_awaddr;
    wire [7:0]            s00_awlen    = tb_bypass_cpu ? tb_s_axi_awlen    : cpu_awlen;
    wire [2:0]            s00_awsize   = tb_bypass_cpu ? tb_s_axi_awsize   : cpu_awsize;
    wire [1:0]            s00_awburst  = tb_bypass_cpu ? tb_s_axi_awburst  : cpu_awburst;
    wire                  s00_awlock   = tb_bypass_cpu ? tb_s_axi_awlock   : cpu_awlock;
    wire [3:0]            s00_awcache  = tb_bypass_cpu ? tb_s_axi_awcache  : cpu_awcache;
    wire [2:0]            s00_awprot   = tb_bypass_cpu ? tb_s_axi_awprot   : cpu_awprot;
    wire [3:0]            s00_awqos    = tb_bypass_cpu ? tb_s_axi_awqos    : cpu_awqos;
    wire [3:0]            s00_awregion = tb_bypass_cpu ? 4'h0               : cpu_awregion;
    wire                  s00_awvalid  = tb_bypass_cpu ? tb_s_axi_awvalid  : cpu_awvalid;
    wire                  s00_awready;

    wire [DATA_WIDTH-1:0] s00_wdata    = tb_bypass_cpu ? tb_s_axi_wdata    : cpu_wdata;
    wire [STRB_WIDTH-1:0] s00_wstrb    = tb_bypass_cpu ? tb_s_axi_wstrb    : cpu_wstrb;
    wire                  s00_wlast    = tb_bypass_cpu ? tb_s_axi_wlast    : cpu_wlast;
    wire                  s00_wvalid   = tb_bypass_cpu ? tb_s_axi_wvalid   : cpu_wvalid;
    wire                  s00_wready;

    wire [ID_WIDTH-1:0]   s00_bid;
    wire [1:0]            s00_bresp;
    wire                  s00_bvalid;
    wire                  s00_bready   = tb_bypass_cpu ? tb_s_axi_bready   : cpu_bready;

    wire [ID_WIDTH-1:0]   s00_arid     = tb_bypass_cpu ? tb_s_axi_arid     : cpu_arid;
    wire [ADDR_WIDTH-1:0] s00_araddr   = tb_bypass_cpu ? tb_s_axi_araddr   : cpu_araddr;
    wire [7:0]            s00_arlen    = tb_bypass_cpu ? tb_s_axi_arlen    : cpu_arlen;
    wire [2:0]            s00_arsize   = tb_bypass_cpu ? tb_s_axi_arsize   : cpu_arsize;
    wire [1:0]            s00_arburst  = tb_bypass_cpu ? tb_s_axi_arburst  : cpu_arburst;
    wire                  s00_arlock   = tb_bypass_cpu ? tb_s_axi_arlock   : cpu_arlock;
    wire [3:0]            s00_arcache  = tb_bypass_cpu ? tb_s_axi_arcache  : cpu_arcache;
    wire [2:0]            s00_arprot   = tb_bypass_cpu ? tb_s_axi_arprot   : cpu_arprot;
    wire [3:0]            s00_arqos    = tb_bypass_cpu ? tb_s_axi_arqos    : cpu_arqos;
    wire [3:0]            s00_arregion = tb_bypass_cpu ? 4'h0               : cpu_arregion;
    wire                  s00_arvalid  = tb_bypass_cpu ? tb_s_axi_arvalid  : cpu_arvalid;
    wire                  s00_arready;

    wire [ID_WIDTH-1:0]   s00_rid;
    wire [DATA_WIDTH-1:0] s00_rdata;
    wire [1:0]            s00_rresp;
    wire                  s00_rlast;
    wire                  s00_rvalid;
    wire                  s00_rready   = tb_bypass_cpu ? tb_s_axi_rready   : cpu_rready;

    assign cpu_awready   = tb_bypass_cpu ? 1'b0        : s00_awready;
    assign cpu_wready    = tb_bypass_cpu ? 1'b0        : s00_wready;
    assign cpu_bid       = s00_bid;
    assign cpu_bresp     = s00_bresp;
    assign cpu_bvalid    = tb_bypass_cpu ? 1'b0        : s00_bvalid;
    assign cpu_arready   = tb_bypass_cpu ? 1'b0        : s00_arready;
    assign cpu_rid       = s00_rid;
    assign cpu_rdata     = s00_rdata;
    assign cpu_rresp     = s00_rresp;
    assign cpu_rlast     = s00_rlast;
    assign cpu_rvalid    = tb_bypass_cpu ? 1'b0        : s00_rvalid;

    assign tb_s_axi_awready = tb_bypass_cpu ? s00_awready : 1'b0;
    assign tb_s_axi_wready  = tb_bypass_cpu ? s00_wready  : 1'b0;
    assign tb_s_axi_bid     = s00_bid;
    assign tb_s_axi_bresp   = s00_bresp;
    assign tb_s_axi_bvalid  = tb_bypass_cpu ? s00_bvalid  : 1'b0;
    assign tb_s_axi_arready = tb_bypass_cpu ? s00_arready : 1'b0;
    assign tb_s_axi_rid     = s00_rid;
    assign tb_s_axi_rdata   = s00_rdata;
    assign tb_s_axi_rresp   = s00_rresp;
    assign tb_s_axi_rlast   = s00_rlast;
    assign tb_s_axi_rvalid  = tb_bypass_cpu ? s00_rvalid  : 1'b0;

    // =========================================================================
    // Interconnect M00..M07 Wires
    // =========================================================================
    // M00: Instruction RAM (0x0000_0000, 64KB)
    wire [ID_WIDTH-1:0]   m00_awid,    m01_awid,    m02_awid,    m03_awid,    m04_awid,    m05_awid,    m06_awid,    m07_awid;
    wire [ADDR_WIDTH-1:0] m00_awaddr,  m01_awaddr,  m02_awaddr,  m03_awaddr,  m04_awaddr,  m05_awaddr,  m06_awaddr,  m07_awaddr;
    wire [7:0]            m00_awlen,   m01_awlen,   m02_awlen,   m03_awlen,   m04_awlen,   m05_awlen,   m06_awlen,   m07_awlen;
    wire [2:0]            m00_awsize,  m01_awsize,  m02_awsize,  m03_awsize,  m04_awsize,  m05_awsize,  m06_awsize,  m07_awsize;
    wire [1:0]            m00_awburst, m01_awburst, m02_awburst, m03_awburst, m04_awburst, m05_awburst, m06_awburst, m07_awburst;
    wire                  m00_awlock,  m01_awlock,  m02_awlock,  m03_awlock,  m04_awlock,  m05_awlock,  m06_awlock,  m07_awlock;
    wire [3:0]            m00_awcache, m01_awcache, m02_awcache, m03_awcache, m04_awcache, m05_awcache, m06_awcache, m07_awcache;
    wire [2:0]            m00_awprot,  m01_awprot,  m02_awprot,  m03_awprot,  m04_awprot,  m05_awprot,  m06_awprot,  m07_awprot;
    wire [3:0]            m00_awqos,   m01_awqos,   m02_awqos,   m03_awqos,   m04_awqos,   m05_awqos,   m06_awqos,   m07_awqos;
    wire [3:0]            m00_awregion,m01_awregion,m02_awregion,m03_awregion,m04_awregion,m05_awregion,m06_awregion,m07_awregion;
    wire                  m00_awvalid, m01_awvalid, m02_awvalid, m03_awvalid, m04_awvalid, m05_awvalid, m06_awvalid, m07_awvalid;
    wire                  m00_awready, m01_awready, m02_awready, m03_awready, m04_awready, m05_awready, m06_awready, m07_awready;

    wire [DATA_WIDTH-1:0] m00_wdata,   m01_wdata,   m02_wdata,   m03_wdata,   m04_wdata,   m05_wdata,   m06_wdata,   m07_wdata;
    wire [STRB_WIDTH-1:0] m00_wstrb,   m01_wstrb,   m02_wstrb,   m03_wstrb,   m04_wstrb,   m05_wstrb,   m06_wstrb,   m07_wstrb;
    wire                  m00_wlast,   m01_wlast,   m02_wlast,   m03_wlast,   m04_wlast,   m05_wlast,   m06_wlast,   m07_wlast;
    wire                  m00_wvalid,  m01_wvalid,  m02_wvalid,  m03_wvalid,  m04_wvalid,  m05_wvalid,  m06_wvalid,  m07_wvalid;
    wire                  m00_wready,  m01_wready,  m02_wready,  m03_wready,  m04_wready,  m05_wready,  m06_wready,  m07_wready;

    wire [ID_WIDTH-1:0]   m00_bid,     m01_bid,     m02_bid,     m03_bid,     m04_bid,     m05_bid,     m06_bid,     m07_bid;
    wire [1:0]            m00_bresp,   m01_bresp,   m02_bresp,   m03_bresp,   m04_bresp,   m05_bresp,   m06_bresp,   m07_bresp;
    wire                  m00_bvalid,  m01_bvalid,  m02_bvalid,  m03_bvalid,  m04_bvalid,  m05_bvalid,  m06_bvalid,  m07_bvalid;
    wire                  m00_bready,  m01_bready,  m02_bready,  m03_bready,  m04_bready,  m05_bready,  m06_bready,  m07_bready;

    wire [ID_WIDTH-1:0]   m00_arid,    m01_arid,    m02_arid,    m03_arid,    m04_arid,    m05_arid,    m06_arid,    m07_arid;
    wire [ADDR_WIDTH-1:0] m00_araddr,  m01_araddr,  m02_araddr,  m03_araddr,  m04_araddr,  m05_araddr,  m06_araddr,  m07_araddr;
    wire [7:0]            m00_arlen,   m01_arlen,   m02_arlen,   m03_arlen,   m04_arlen,   m05_arlen,   m06_arlen,   m07_arlen;
    wire [2:0]            m00_arsize,  m01_arsize,  m02_arsize,  m03_arsize,  m04_arsize,  m05_arsize,  m06_arsize,  m07_arsize;
    wire [1:0]            m00_arburst, m01_arburst, m02_arburst, m03_arburst, m04_arburst, m05_arburst, m06_arburst, m07_arburst;
    wire                  m00_arlock,  m01_arlock,  m02_arlock,  m03_arlock,  m04_arlock,  m05_arlock,  m06_arlock,  m07_arlock;
    wire [3:0]            m00_arcache, m01_arcache, m02_arcache, m03_arcache, m04_arcache, m05_arcache, m06_arcache, m07_arcache;
    wire [2:0]            m00_arprot,  m01_arprot,  m02_arprot,  m03_arprot,  m04_arprot,  m05_arprot,  m06_arprot,  m07_arprot;
    wire [3:0]            m00_arqos,   m01_arqos,   m02_arqos,   m03_arqos,   m04_arqos,   m05_arqos,   m06_arqos,   m07_arqos;
    wire [3:0]            m00_arregion,m01_arregion,m02_arregion,m03_arregion,m04_arregion,m05_arregion,m06_arregion,m07_arregion;
    wire                  m00_arvalid, m01_arvalid, m02_arvalid, m03_arvalid, m04_arvalid, m05_arvalid, m06_arvalid, m07_arvalid;
    wire                  m00_arready, m01_arready, m02_arready, m03_arready, m04_arready, m05_arready, m06_arready, m07_arready;

    wire [ID_WIDTH-1:0]   m00_rid,     m01_rid,     m02_rid,     m03_rid,     m04_rid,     m05_rid,     m06_rid,     m07_rid;
    wire [DATA_WIDTH-1:0] m00_rdata,   m01_rdata,   m02_rdata,   m03_rdata,   m04_rdata,   m05_rdata,   m06_rdata,   m07_rdata;
    wire [1:0]            m00_rresp,   m01_rresp,   m02_rresp,   m03_rresp,   m04_rresp,   m05_rresp,   m06_rresp,   m07_rresp;
    wire                  m00_rlast,   m01_rlast,   m02_rlast,   m03_rlast,   m04_rlast,   m05_rlast,   m06_rlast,   m07_rlast;
    wire                  m00_rvalid,  m01_rvalid,  m02_rvalid,  m03_rvalid,  m04_rvalid,  m05_rvalid,  m06_rvalid,  m07_rvalid;
    wire                  m00_rready,  m01_rready,  m02_rready,  m03_rready,  m04_rready,  m05_rready,  m06_rready,  m07_rready;

    // Instantiate AXI4 1x8 Interconnect Wrapper
    axi_interconnect_wrap_1x8 #(
        .DATA_WIDTH       (DATA_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .STRB_WIDTH       (STRB_WIDTH),
        .ID_WIDTH         (ID_WIDTH),
        .FORWARD_ID       (1),
        .M_REGIONS        (1),

        // M00: Instruction Memory (64 KiB @ 0x0000_0000)
        .M00_BASE_ADDR    (32'h0000_0000),
        .M00_ADDR_WIDTH   (32'd16),
        .M00_CONNECT_READ (1'b1),
        .M00_CONNECT_WRITE(1'b1),

        // M01: Data Memory (64 KiB @ 0x1000_0000)
        .M01_BASE_ADDR    (32'h1000_0000),
        .M01_ADDR_WIDTH   (32'd16),
        .M01_CONNECT_READ (1'b1),
        .M01_CONNECT_WRITE(1'b1),

        // M02: UART (4 KiB @ 0x2000_0000)
        .M02_BASE_ADDR    (32'h2000_0000),
        .M02_ADDR_WIDTH   (32'd12),
        .M02_CONNECT_READ (1'b1),
        .M02_CONNECT_WRITE(1'b1),

        // M03: Timer (4 KiB @ 0x2000_1000)
        .M03_BASE_ADDR    (32'h2000_1000),
        .M03_ADDR_WIDTH   (32'd12),
        .M03_CONNECT_READ (1'b1),
        .M03_CONNECT_WRITE(1'b1),

        // M04: GPIO (4 KiB @ 0x2000_2000)
        .M04_BASE_ADDR    (32'h2000_2000),
        .M04_ADDR_WIDTH   (32'd12),
        .M04_CONNECT_READ (1'b1),
        .M04_CONNECT_WRITE(1'b1),

        // M05: CRC-16 (4 KiB @ 0x2000_3000)
        .M05_BASE_ADDR    (32'h2000_3000),
        .M05_ADDR_WIDTH   (32'd12),
        .M05_CONNECT_READ (1'b1),
        .M05_CONNECT_WRITE(1'b1),

        // M06: TX FIFO (4 KiB @ 0x2000_4000)
        .M06_BASE_ADDR    (32'h2000_4000),
        .M06_ADDR_WIDTH   (32'd12),
        .M06_CONNECT_READ (1'b1),
        .M06_CONNECT_WRITE(1'b1),

        // M07: SPI Master (4 KiB @ 0x2000_5000)
        .M07_BASE_ADDR    (32'h2000_5000),
        .M07_ADDR_WIDTH   (32'd12),
        .M07_CONNECT_READ (1'b1),
        .M07_CONNECT_WRITE(1'b1)
    ) u_interconnect (
        .clk              (clk_i),
        .rst              (rst_high),

        // Upstream S00 (CPU Master)
        .s00_axi_awid     (s00_awid),
        .s00_axi_awaddr   (s00_awaddr),
        .s00_axi_awlen    (s00_awlen),
        .s00_axi_awsize   (s00_awsize),
        .s00_axi_awburst  (s00_awburst),
        .s00_axi_awlock   (s00_awlock),
        .s00_axi_awcache  (s00_awcache),
        .s00_axi_awprot   (s00_awprot),
        .s00_axi_awqos    (s00_awqos),
        .s00_axi_awuser   (1'b0),
        .s00_axi_awvalid  (s00_awvalid),
        .s00_axi_awready  (s00_awready),
        .s00_axi_wdata    (s00_wdata),
        .s00_axi_wstrb    (s00_wstrb),
        .s00_axi_wlast    (s00_wlast),
        .s00_axi_wuser    (1'b0),
        .s00_axi_wvalid   (s00_wvalid),
        .s00_axi_wready   (s00_wready),
        .s00_axi_bid      (s00_bid),
        .s00_axi_bresp    (s00_bresp),
        .s00_axi_buser    (),
        .s00_axi_bvalid   (s00_bvalid),
        .s00_axi_bready   (s00_bready),
        .s00_axi_arid     (s00_arid),
        .s00_axi_araddr   (s00_araddr),
        .s00_axi_arlen    (s00_arlen),
        .s00_axi_arsize   (s00_arsize),
        .s00_axi_arburst  (s00_arburst),
        .s00_axi_arlock   (s00_arlock),
        .s00_axi_arcache  (s00_arcache),
        .s00_axi_arprot   (s00_arprot),
        .s00_axi_arqos    (s00_arqos),
        .s00_axi_aruser   (1'b0),
        .s00_axi_arvalid  (s00_arvalid),
        .s00_axi_arready  (s00_arready),
        .s00_axi_rid      (s00_rid),
        .s00_axi_rdata    (s00_rdata),
        .s00_axi_rresp    (s00_rresp),
        .s00_axi_rlast    (s00_rlast),
        .s00_axi_ruser    (),
        .s00_axi_rvalid   (s00_rvalid),
        .s00_axi_rready   (s00_rready),

        // Downstream M00..M07
        .m00_axi_awid     (m00_awid),     .m00_axi_awaddr   (m00_awaddr),
        .m00_axi_awlen    (m00_awlen),    .m00_axi_awsize   (m00_awsize),
        .m00_axi_awburst  (m00_awburst),  .m00_axi_awlock   (m00_awlock),
        .m00_axi_awcache  (m00_awcache),  .m00_axi_awprot   (m00_awprot),
        .m00_axi_awqos    (m00_awqos),    .m00_axi_awregion (m00_awregion),
        .m00_axi_awuser   (),             .m00_axi_awvalid  (m00_awvalid),
        .m00_axi_awready  (m00_awready),  .m00_axi_wdata    (m00_wdata),
        .m00_axi_wstrb    (m00_wstrb),    .m00_axi_wlast    (m00_wlast),
        .m00_axi_wuser    (),             .m00_axi_wvalid   (m00_wvalid),
        .m00_axi_wready   (m00_wready),   .m00_axi_bid      (m00_bid),
        .m00_axi_bresp    (m00_bresp),    .m00_axi_buser    (1'b0),
        .m00_axi_bvalid   (m00_bvalid),   .m00_axi_bready   (m00_bready),
        .m00_axi_arid     (m00_arid),     .m00_axi_araddr   (m00_araddr),
        .m00_axi_arlen    (m00_arlen),    .m00_axi_arsize   (m00_arsize),
        .m00_axi_arburst  (m00_arburst),  .m00_axi_arlock   (m00_arlock),
        .m00_axi_arcache  (m00_arcache),  .m00_axi_arprot   (m00_arprot),
        .m00_axi_arqos    (m00_arqos),    .m00_axi_arregion (m00_arregion),
        .m00_axi_aruser   (),             .m00_axi_arvalid  (m00_arvalid),
        .m00_axi_arready  (m00_arready),  .m00_axi_rid      (m00_rid),
        .m00_axi_rdata    (m00_rdata),    .m00_axi_rresp    (m00_rresp),
        .m00_axi_rlast    (m00_rlast),    .m00_axi_ruser    (1'b0),
        .m00_axi_rvalid   (m00_rvalid),   .m00_axi_rready   (m00_rready),

        .m01_axi_awid     (m01_awid),     .m01_axi_awaddr   (m01_awaddr),
        .m01_axi_awlen    (m01_awlen),    .m01_axi_awsize   (m01_awsize),
        .m01_axi_awburst  (m01_awburst),  .m01_axi_awlock   (m01_awlock),
        .m01_axi_awcache  (m01_awcache),  .m01_axi_awprot   (m01_awprot),
        .m01_axi_awqos    (m01_awqos),    .m01_axi_awregion (m01_awregion),
        .m01_axi_awuser   (),             .m01_axi_awvalid  (m01_awvalid),
        .m01_axi_awready  (m01_awready),  .m01_axi_wdata    (m01_wdata),
        .m01_axi_wstrb    (m01_wstrb),    .m01_axi_wlast    (m01_wlast),
        .m01_axi_wuser    (),             .m01_axi_wvalid   (m01_wvalid),
        .m01_axi_wready   (m01_wready),   .m01_axi_bid      (m01_bid),
        .m01_axi_bresp    (m01_bresp),    .m01_axi_buser    (1'b0),
        .m01_axi_bvalid   (m01_bvalid),   .m01_axi_bready   (m01_bready),
        .m01_axi_arid     (m01_arid),     .m01_axi_araddr   (m01_araddr),
        .m01_axi_arlen    (m01_arlen),    .m01_axi_arsize   (m01_arsize),
        .m01_axi_arburst  (m01_arburst),  .m01_axi_arlock   (m01_arlock),
        .m01_axi_arcache  (m01_arcache),  .m01_axi_arprot   (m01_arprot),
        .m01_axi_arqos    (m01_arqos),    .m01_axi_arregion (m01_arregion),
        .m01_axi_aruser   (),             .m01_axi_arvalid  (m01_arvalid),
        .m01_axi_arready  (m01_arready),  .m01_axi_rid      (m01_rid),
        .m01_axi_rdata    (m01_rdata),    .m01_axi_rresp    (m01_rresp),
        .m01_axi_rlast    (m01_rlast),    .m01_axi_ruser    (1'b0),
        .m01_axi_rvalid   (m01_rvalid),   .m01_axi_rready   (m01_rready),

        .m02_axi_awid     (m02_awid),     .m02_axi_awaddr   (m02_awaddr),
        .m02_axi_awlen    (m02_awlen),    .m02_axi_awsize   (m02_awsize),
        .m02_axi_awburst  (m02_awburst),  .m02_axi_awlock   (m02_awlock),
        .m02_axi_awcache  (m02_awcache),  .m02_axi_awprot   (m02_awprot),
        .m02_axi_awqos    (m02_awqos),    .m02_axi_awregion (m02_awregion),
        .m02_axi_awuser   (),             .m02_axi_awvalid  (m02_awvalid),
        .m02_axi_awready  (m02_awready),  .m02_axi_wdata    (m02_wdata),
        .m02_axi_wstrb    (m02_wstrb),    .m02_axi_wlast    (m02_wlast),
        .m02_axi_wuser    (),             .m02_axi_wvalid   (m02_wvalid),
        .m02_axi_wready   (m02_wready),   .m02_axi_bid      (m02_bid),
        .m02_axi_bresp    (m02_bresp),    .m02_axi_buser    (1'b0),
        .m02_axi_bvalid   (m02_bvalid),   .m02_axi_bready   (m02_bready),
        .m02_axi_arid     (m02_arid),     .m02_axi_araddr   (m02_araddr),
        .m02_axi_arlen    (m02_arlen),    .m02_axi_arsize   (m02_arsize),
        .m02_axi_arburst  (m02_arburst),  .m02_axi_arlock   (m02_arlock),
        .m02_axi_arcache  (m02_arcache),  .m02_axi_arprot   (m02_arprot),
        .m02_axi_arqos    (m02_arqos),    .m02_axi_arregion (m02_arregion),
        .m02_axi_aruser   (),             .m02_axi_arvalid  (m02_arvalid),
        .m02_axi_arready  (m02_arready),  .m02_axi_rid      (m02_rid),
        .m02_axi_rdata    (m02_rdata),    .m02_axi_rresp    (m02_rresp),
        .m02_axi_rlast    (m02_rlast),    .m02_axi_ruser    (1'b0),
        .m02_axi_rvalid   (m02_rvalid),   .m02_axi_rready   (m02_rready),

        .m03_axi_awid     (m03_awid),     .m03_axi_awaddr   (m03_awaddr),
        .m03_axi_awlen    (m03_awlen),    .m03_axi_awsize   (m03_awsize),
        .m03_axi_awburst  (m03_awburst),  .m03_axi_awlock   (m03_awlock),
        .m03_axi_awcache  (m03_awcache),  .m03_axi_awprot   (m03_awprot),
        .m03_axi_awqos    (m03_awqos),    .m03_axi_awregion (m03_awregion),
        .m03_axi_awuser   (),             .m03_axi_awvalid  (m03_awvalid),
        .m03_axi_awready  (m03_awready),  .m03_axi_wdata    (m03_wdata),
        .m03_axi_wstrb    (m03_wstrb),    .m03_axi_wlast    (m03_wlast),
        .m03_axi_wuser    (),             .m03_axi_wvalid   (m03_wvalid),
        .m03_axi_wready   (m03_wready),   .m03_axi_bid      (m03_bid),
        .m03_axi_bresp    (m03_bresp),    .m03_axi_buser    (1'b0),
        .m03_axi_bvalid   (m03_bvalid),   .m03_axi_bready   (m03_bready),
        .m03_axi_arid     (m03_arid),     .m03_axi_araddr   (m03_araddr),
        .m03_axi_arlen    (m03_arlen),    .m03_axi_arsize   (m03_arsize),
        .m03_axi_arburst  (m03_arburst),  .m03_axi_arlock   (m03_arlock),
        .m03_axi_arcache  (m03_arcache),  .m03_axi_arprot   (m03_arprot),
        .m03_axi_arqos    (m03_arqos),    .m03_axi_arregion (m03_arregion),
        .m03_axi_aruser   (),             .m03_axi_arvalid  (m03_arvalid),
        .m03_axi_arready  (m03_arready),  .m03_axi_rid      (m03_rid),
        .m03_axi_rdata    (m03_rdata),    .m03_axi_rresp    (m03_rresp),
        .m03_axi_rlast    (m03_rlast),    .m03_axi_ruser    (1'b0),
        .m03_axi_rvalid   (m03_rvalid),   .m03_axi_rready   (m03_rready),

        .m04_axi_awid     (m04_awid),     .m04_axi_awaddr   (m04_awaddr),
        .m04_axi_awlen    (m04_awlen),    .m04_axi_awsize   (m04_awsize),
        .m04_axi_awburst  (m04_awburst),  .m04_axi_awlock   (m04_awlock),
        .m04_axi_awcache  (m04_awcache),  .m04_axi_awprot   (m04_awprot),
        .m04_axi_awqos    (m04_awqos),    .m04_axi_awregion (m04_awregion),
        .m04_axi_awuser   (),             .m04_axi_awvalid  (m04_awvalid),
        .m04_axi_awready  (m04_awready),  .m04_axi_wdata    (m04_wdata),
        .m04_axi_wstrb    (m04_wstrb),    .m04_axi_wlast    (m04_wlast),
        .m04_axi_wuser    (),             .m04_axi_wvalid   (m04_wvalid),
        .m04_axi_wready   (m04_wready),   .m04_axi_bid      (m04_bid),
        .m04_axi_bresp    (m04_bresp),    .m04_axi_buser    (1'b0),
        .m04_axi_bvalid   (m04_bvalid),   .m04_axi_bready   (m04_bready),
        .m04_axi_arid     (m04_arid),     .m04_axi_araddr   (m04_araddr),
        .m04_axi_arlen    (m04_arlen),    .m04_axi_arsize   (m04_arsize),
        .m04_axi_arburst  (m04_arburst),  .m04_axi_arlock   (m04_arlock),
        .m04_axi_arcache  (m04_arcache),  .m04_axi_arprot   (m04_arprot),
        .m04_axi_arqos    (m04_arqos),    .m04_axi_arregion (m04_arregion),
        .m04_axi_aruser   (),             .m04_axi_arvalid  (m04_arvalid),
        .m04_axi_arready  (m04_arready),  .m04_axi_rid      (m04_rid),
        .m04_axi_rdata    (m04_rdata),    .m04_axi_rresp    (m04_rresp),
        .m04_axi_rlast    (m04_rlast),    .m04_axi_ruser    (1'b0),
        .m04_axi_rvalid   (m04_rvalid),   .m04_axi_rready   (m04_rready),

        .m05_axi_awid     (m05_awid),     .m05_axi_awaddr   (m05_awaddr),
        .m05_axi_awlen    (m05_awlen),    .m05_axi_awsize   (m05_awsize),
        .m05_axi_awburst  (m05_awburst),  .m05_axi_awlock   (m05_awlock),
        .m05_axi_awcache  (m05_awcache),  .m05_axi_awprot   (m05_awprot),
        .m05_axi_awqos    (m05_awqos),    .m05_axi_awregion (m05_awregion),
        .m05_axi_awuser   (),             .m05_axi_awvalid  (m05_awvalid),
        .m05_axi_awready  (m05_awready),  .m05_axi_wdata    (m05_wdata),
        .m05_axi_wstrb    (m05_wstrb),    .m05_axi_wlast    (m05_wlast),
        .m05_axi_wuser    (),             .m05_axi_wvalid   (m05_wvalid),
        .m05_axi_wready   (m05_wready),   .m05_axi_bid      (m05_bid),
        .m05_axi_bresp    (m05_bresp),    .m05_axi_buser    (1'b0),
        .m05_axi_bvalid   (m05_bvalid),   .m05_axi_bready   (m05_bready),
        .m05_axi_arid     (m05_arid),     .m05_axi_araddr   (m05_araddr),
        .m05_axi_arlen    (m05_arlen),    .m05_axi_arsize   (m05_arsize),
        .m05_axi_arburst  (m05_arburst),  .m05_axi_arlock   (m05_arlock),
        .m05_axi_arcache  (m05_arcache),  .m05_axi_arprot   (m05_arprot),
        .m05_axi_arqos    (m05_arqos),    .m05_axi_arregion (m05_arregion),
        .m05_axi_aruser   (),             .m05_axi_arvalid  (m05_arvalid),
        .m05_axi_arready  (m05_arready),  .m05_axi_rid      (m05_rid),
        .m05_axi_rdata    (m05_rdata),    .m05_axi_rresp    (m05_rresp),
        .m05_axi_rlast    (m05_rlast),    .m05_axi_ruser    (1'b0),
        .m05_axi_rvalid   (m05_rvalid),   .m05_axi_rready   (m05_rready),

        .m06_axi_awid     (m06_awid),     .m06_axi_awaddr   (m06_awaddr),
        .m06_axi_awlen    (m06_awlen),    .m06_axi_awsize   (m06_awsize),
        .m06_axi_awburst  (m06_awburst),  .m06_axi_awlock   (m06_awlock),
        .m06_axi_awcache  (m06_awcache),  .m06_axi_awprot   (m06_awprot),
        .m06_axi_awqos    (m06_awqos),    .m06_axi_awregion (m06_awregion),
        .m06_axi_awuser   (),             .m06_axi_awvalid  (m06_awvalid),
        .m06_axi_awready  (m06_awready),  .m06_axi_wdata    (m06_wdata),
        .m06_axi_wstrb    (m06_wstrb),    .m06_axi_wlast    (m06_wlast),
        .m06_axi_wuser    (),             .m06_axi_wvalid   (m06_wvalid),
        .m06_axi_wready   (m06_wready),   .m06_axi_bid      (m06_bid),
        .m06_axi_bresp    (m06_bresp),    .m06_axi_buser    (1'b0),
        .m06_axi_bvalid   (m06_bvalid),   .m06_axi_bready   (m06_bready),
        .m06_axi_arid     (m06_arid),     .m06_axi_araddr   (m06_araddr),
        .m06_axi_arlen    (m06_arlen),    .m06_axi_arsize   (m06_arsize),
        .m06_axi_arburst  (m06_arburst),  .m06_axi_arlock   (m06_arlock),
        .m06_axi_arcache  (m06_arcache),  .m06_axi_arprot   (m06_arprot),
        .m06_axi_arqos    (m06_arqos),    .m06_axi_arregion (m06_arregion),
        .m06_axi_aruser   (),             .m06_axi_arvalid  (m06_arvalid),
        .m06_axi_arready  (m06_arready),  .m06_axi_rid      (m06_rid),
        .m06_axi_rdata    (m06_rdata),    .m06_axi_rresp    (m06_rresp),
        .m06_axi_rlast    (m06_rlast),    .m06_axi_ruser    (1'b0),
        .m06_axi_rvalid   (m06_rvalid),   .m06_axi_rready   (m06_rready),

        .m07_axi_awid     (m07_awid),     .m07_axi_awaddr   (m07_awaddr),
        .m07_axi_awlen    (m07_awlen),    .m07_axi_awsize   (m07_awsize),
        .m07_axi_awburst  (m07_awburst),  .m07_axi_awlock   (m07_awlock),
        .m07_axi_awcache  (m07_awcache),  .m07_axi_awprot   (m07_awprot),
        .m07_axi_awqos    (m07_awqos),    .m07_axi_awregion (m07_awregion),
        .m07_axi_awuser   (),             .m07_axi_awvalid  (m07_awvalid),
        .m07_axi_awready  (m07_awready),  .m07_axi_wdata    (m07_wdata),
        .m07_axi_wstrb    (m07_wstrb),    .m07_axi_wlast    (m07_wlast),
        .m07_axi_wuser    (),             .m07_axi_wvalid   (m07_wvalid),
        .m07_axi_wready   (m07_wready),   .m07_axi_bid      (m07_bid),
        .m07_axi_bresp    (m07_bresp),    .m07_axi_buser    (1'b0),
        .m07_axi_bvalid   (m07_bvalid),   .m07_axi_bready   (m07_bready),
        .m07_axi_arid     (m07_arid),     .m07_axi_araddr   (m07_araddr),
        .m07_axi_arlen    (m07_arlen),    .m07_axi_arsize   (m07_arsize),
        .m07_axi_arburst  (m07_arburst),  .m07_axi_arlock   (m07_arlock),
        .m07_axi_arcache  (m07_arcache),  .m07_axi_arprot   (m07_arprot),
        .m07_axi_arqos    (m07_arqos),    .m07_axi_arregion (m07_arregion),
        .m07_axi_aruser   (),             .m07_axi_arvalid  (m07_arvalid),
        .m07_axi_arready  (m07_arready),  .m07_axi_rid      (m07_rid),
        .m07_axi_rdata    (m07_rdata),    .m07_axi_rresp    (m07_rresp),
        .m07_axi_rlast    (m07_rlast),    .m07_axi_ruser    (1'b0),
        .m07_axi_rvalid   (m07_rvalid),   .m07_axi_rready   (m07_rready)
    );

    // =========================================================================
    // SLAVE INSTANTIATIONS (M00 through M07)
    // =========================================================================

    // M00: Instruction Memory (64 KiB @ 0x0000_0000)
    axi_ram #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .ID_WIDTH      (ID_WIDTH),
        .STRB_WIDTH    (STRB_WIDTH),
        .MEM_ADDR_BITS (16), // 64 KiB
        .INIT_HEX_FILE (BOOT_HEX_FILE),
        .MEM_NAME      ("IMEM")
    ) u_imem (
        .clk           (clk_i),
        .rst           (rst_high),
        .s_axi_awid    (m00_awid),
        .s_axi_awaddr  (m00_awaddr),
        .s_axi_awlen   (m00_awlen),
        .s_axi_awsize  (m00_awsize),
        .s_axi_awburst (m00_awburst),
        .s_axi_awlock  (m00_awlock),
        .s_axi_awcache (m00_awcache),
        .s_axi_awprot  (m00_awprot),
        .s_axi_awqos   (m00_awqos),
        .s_axi_awregion(m00_awregion),
        .s_axi_awvalid (m00_awvalid),
        .s_axi_awready (m00_awready),
        .s_axi_wdata   (m00_wdata),
        .s_axi_wstrb   (m00_wstrb),
        .s_axi_wlast   (m00_wlast),
        .s_axi_wuser   (1'b0),
        .s_axi_wvalid  (m00_wvalid),
        .s_axi_wready  (m00_wready),
        .s_axi_bid     (m00_bid),
        .s_axi_bresp   (m00_bresp),
        .s_axi_bvalid  (m00_bvalid),
        .s_axi_bready  (m00_bready),
        .s_axi_arid    (m00_arid),
        .s_axi_araddr  (m00_araddr),
        .s_axi_arlen   (m00_arlen),
        .s_axi_arsize  (m00_arsize),
        .s_axi_arburst (m00_arburst),
        .s_axi_arlock  (m00_arlock),
        .s_axi_arcache (m00_arcache),
        .s_axi_arprot  (m00_arprot),
        .s_axi_arqos   (m00_arqos),
        .s_axi_arregion(m00_arregion),
        .s_axi_arvalid (m00_arvalid),
        .s_axi_arready (m00_arready),
        .s_axi_rid     (m00_rid),
        .s_axi_rdata   (m00_rdata),
        .s_axi_rresp   (m00_rresp),
        .s_axi_rlast   (m00_rlast),
        .s_axi_rvalid  (m00_rvalid),
        .s_axi_rready  (m00_rready)
    );

    // M01: Data Memory (64 KiB @ 0x1000_0000)
    axi_ram #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .ID_WIDTH      (ID_WIDTH),
        .STRB_WIDTH    (STRB_WIDTH),
        .MEM_ADDR_BITS (16), // 64 KiB
        .INIT_HEX_FILE (""),
        .MEM_NAME      ("DMEM")
    ) u_dmem (
        .clk           (clk_i),
        .rst           (rst_high),
        .s_axi_awid    (m01_awid),
        .s_axi_awaddr  (m01_awaddr),
        .s_axi_awlen   (m01_awlen),
        .s_axi_awsize  (m01_awsize),
        .s_axi_awburst (m01_awburst),
        .s_axi_awlock  (m01_awlock),
        .s_axi_awcache (m01_awcache),
        .s_axi_awprot  (m01_awprot),
        .s_axi_awqos   (m01_awqos),
        .s_axi_awregion(m01_awregion),
        .s_axi_awvalid (m01_awvalid),
        .s_axi_awready (m01_awready),
        .s_axi_wdata   (m01_wdata),
        .s_axi_wstrb   (m01_wstrb),
        .s_axi_wlast   (m01_wlast),
        .s_axi_wuser   (1'b0),
        .s_axi_wvalid  (m01_wvalid),
        .s_axi_wready  (m01_wready),
        .s_axi_bid     (m01_bid),
        .s_axi_bresp   (m01_bresp),
        .s_axi_bvalid  (m01_bvalid),
        .s_axi_bready  (m01_bready),
        .s_axi_arid    (m01_arid),
        .s_axi_araddr  (m01_araddr),
        .s_axi_arlen   (m01_arlen),
        .s_axi_arsize  (m01_arsize),
        .s_axi_arburst (m01_arburst),
        .s_axi_arlock  (m01_arlock),
        .s_axi_arcache (m01_arcache),
        .s_axi_arprot  (m01_arprot),
        .s_axi_arqos   (m01_arqos),
        .s_axi_arregion(m01_arregion),
        .s_axi_arvalid (m01_arvalid),
        .s_axi_arready (m01_arready),
        .s_axi_rid     (m01_rid),
        .s_axi_rdata   (m01_rdata),
        .s_axi_rresp   (m01_rresp),
        .s_axi_rlast   (m01_rlast),
        .s_axi_rvalid  (m01_rvalid),
        .s_axi_rready  (m01_rready)
    );

    // M02: UART IP (4 KiB @ 0x2000_0000)
    uart_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_uart (
        .clk           (clk_i),
        .rst           (rst_high),
        .rst_n         (rst_ni),
        .s_axi_awid    (m02_awid),
        .s_axi_awaddr  (m02_awaddr),
        .s_axi_awlen   (m02_awlen),
        .s_axi_awsize  (m02_awsize),
        .s_axi_awburst (m02_awburst),
        .s_axi_awlock  (m02_awlock),
        .s_axi_awcache (m02_awcache),
        .s_axi_awprot  (m02_awprot),
        .s_axi_awqos   (m02_awqos),
        .s_axi_awregion(m02_awregion),
        .s_axi_awvalid (m02_awvalid),
        .s_axi_awready (m02_awready),
        .s_axi_wdata   (m02_wdata),
        .s_axi_wstrb   (m02_wstrb),
        .s_axi_wlast   (m02_wlast),
        .s_axi_wvalid  (m02_wvalid),
        .s_axi_wready  (m02_wready),
        .s_axi_bid     (m02_bid),
        .s_axi_bresp   (m02_bresp),
        .s_axi_bvalid  (m02_bvalid),
        .s_axi_bready  (m02_bready),
        .s_axi_arid    (m02_arid),
        .s_axi_araddr  (m02_araddr),
        .s_axi_arlen   (m02_arlen),
        .s_axi_arsize  (m02_arsize),
        .s_axi_arburst (m02_arburst),
        .s_axi_arlock  (m02_arlock),
        .s_axi_arcache (m02_arcache),
        .s_axi_arprot  (m02_arprot),
        .s_axi_arqos   (m02_arqos),
        .s_axi_arregion(m02_arregion),
        .s_axi_arvalid (m02_arvalid),
        .s_axi_arready (m02_arready),
        .s_axi_rid     (m02_rid),
        .s_axi_rdata   (m02_rdata),
        .s_axi_rresp   (m02_rresp),
        .s_axi_rlast   (m02_rlast),
        .s_axi_rvalid  (m02_rvalid),
        .s_axi_rready  (m02_rready),
        .uart_rx_i     (uart_rx_i),
        .uart_tx_o     (uart_tx_o),
        .uart_irq_o    ()
    );

    // M03: Timer IP (4 KiB @ 0x2000_1000)
    timer_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_timer (
        .clk           (clk_i),
        .rst           (rst_high),
        .rst_n         (rst_ni),
        .s_axi_awid    (m03_awid),
        .s_axi_awaddr  (m03_awaddr),
        .s_axi_awlen   (m03_awlen),
        .s_axi_awsize  (m03_awsize),
        .s_axi_awburst (m03_awburst),
        .s_axi_awlock  (m03_awlock),
        .s_axi_awcache (m03_awcache),
        .s_axi_awprot  (m03_awprot),
        .s_axi_awqos   (m03_awqos),
        .s_axi_awregion(m03_awregion),
        .s_axi_awvalid (m03_awvalid),
        .s_axi_awready (m03_awready),
        .s_axi_wdata   (m03_wdata),
        .s_axi_wstrb   (m03_wstrb),
        .s_axi_wlast   (m03_wlast),
        .s_axi_wuser   (1'b0),
        .s_axi_wvalid  (m03_wvalid),
        .s_axi_wready  (m03_wready),
        .s_axi_bid     (m03_bid),
        .s_axi_bresp   (m03_bresp),
        .s_axi_buser   (),
        .s_axi_bvalid  (m03_bvalid),
        .s_axi_bready  (m03_bready),
        .s_axi_arid    (m03_arid),
        .s_axi_araddr  (m03_araddr),
        .s_axi_arlen   (m03_arlen),
        .s_axi_arsize  (m03_arsize),
        .s_axi_arburst (m03_arburst),
        .s_axi_arlock  (m03_arlock),
        .s_axi_arcache (m03_arcache),
        .s_axi_arprot  (m03_arprot),
        .s_axi_arqos   (m03_arqos),
        .s_axi_arregion(m03_arregion),
        .s_axi_aruser  (1'b0),
        .s_axi_arvalid (m03_arvalid),
        .s_axi_arready (m03_arready),
        .s_axi_rid     (m03_rid),
        .s_axi_rdata   (m03_rdata),
        .s_axi_rresp   (m03_rresp),
        .s_axi_rlast   (m03_rlast),
        .s_axi_ruser   (),
        .s_axi_rvalid  (m03_rvalid),
        .s_axi_rready  (m03_rready),
        .timer_irq_o   (),
        .timer_pwm_o   ()
    );

    // M04: GPIO IP (4 KiB @ 0x2000_2000)
    wire [31:0] gpio_core_out;
    gpio_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .GPIO_WIDTH (32)
    ) u_gpio (
        .clk           (clk_i),
        .rst           (rst_high),
        .rst_n         (rst_ni),
        .s_axi_awid    (m04_awid),
        .s_axi_awaddr  (m04_awaddr),
        .s_axi_awlen   (m04_awlen),
        .s_axi_awsize  (m04_awsize),
        .s_axi_awburst (m04_awburst),
        .s_axi_awlock  (m04_awlock),
        .s_axi_awcache (m04_awcache),
        .s_axi_awprot  (m04_awprot),
        .s_axi_awqos   (m04_awqos),
        .s_axi_awregion(m04_awregion),
        .s_axi_awuser  (1'b0),
        .s_axi_awvalid (m04_awvalid),
        .s_axi_awready (m04_awready),
        .s_axi_wdata   (m04_wdata),
        .s_axi_wstrb   (m04_wstrb),
        .s_axi_wlast   (m04_wlast),
        .s_axi_wuser   (1'b0),
        .s_axi_wvalid  (m04_wvalid),
        .s_axi_wready  (m04_wready),
        .s_axi_bid     (m04_bid),
        .s_axi_bresp   (m04_bresp),
        .s_axi_buser   (),
        .s_axi_bvalid  (m04_bvalid),
        .s_axi_bready  (m04_bready),
        .s_axi_arid    (m04_arid),
        .s_axi_araddr  (m04_araddr),
        .s_axi_arlen   (m04_arlen),
        .s_axi_arsize  (m04_arsize),
        .s_axi_arburst (m04_arburst),
        .s_axi_arlock  (m04_arlock),
        .s_axi_arcache (m04_arcache),
        .s_axi_arprot  (m04_arprot),
        .s_axi_arqos   (m04_arqos),
        .s_axi_arregion(m04_arregion),
        .s_axi_aruser  (1'b0),
        .s_axi_arvalid (m04_arvalid),
        .s_axi_arready (m04_arready),
        .s_axi_rid     (m04_rid),
        .s_axi_rdata   (m04_rdata),
        .s_axi_rresp   (m04_rresp),
        .s_axi_rlast   (m04_rlast),
        .s_axi_ruser   (),
        .s_axi_rvalid  (m04_rvalid),
        .s_axi_rready  (m04_rready),
        .gpio_i        (32'h0),
        .gpio_o        (gpio_core_out),
        .gpio_oe       (),
        .gpio_irq_o    ()
    );
    assign gpio_out_o = gpio_core_out[7:0];

    // M05: CRC-16-CCITT-FALSE Accelerator (4 KiB @ 0x2000_3000)
    crc_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_crc16 (
        .clk           (clk_i),
        .rst           (rst_high),
        .rst_n         (rst_ni),
        .s_axi_awid    (m05_awid),
        .s_axi_awaddr  (m05_awaddr),
        .s_axi_awlen   (m05_awlen),
        .s_axi_awsize  (m05_awsize),
        .s_axi_awburst (m05_awburst),
        .s_axi_awlock  (m05_awlock),
        .s_axi_awcache (m05_awcache),
        .s_axi_awprot  (m05_awprot),
        .s_axi_awqos   (m05_awqos),
        .s_axi_awregion(m05_awregion),
        .s_axi_awvalid (m05_awvalid),
        .s_axi_awready (m05_awready),
        .s_axi_wdata   (m05_wdata),
        .s_axi_wstrb   (m05_wstrb),
        .s_axi_wlast   (m05_wlast),
        .s_axi_wvalid  (m05_wvalid),
        .s_axi_wready  (m05_wready),
        .s_axi_bid     (m05_bid),
        .s_axi_bresp   (m05_bresp),
        .s_axi_bvalid  (m05_bvalid),
        .s_axi_bready  (m05_bready),
        .s_axi_arid    (m05_arid),
        .s_axi_araddr  (m05_araddr),
        .s_axi_arlen   (m05_arlen),
        .s_axi_arsize  (m05_arsize),
        .s_axi_arburst (m05_arburst),
        .s_axi_arlock  (m05_arlock),
        .s_axi_arcache (m05_arcache),
        .s_axi_arprot  (m05_arprot),
        .s_axi_arqos   (m05_arqos),
        .s_axi_arregion(m05_arregion),
        .s_axi_arvalid (m05_arvalid),
        .s_axi_arready (m05_arready),
        .s_axi_rid     (m05_rid),
        .s_axi_rdata   (m05_rdata),
        .s_axi_rresp   (m05_rresp),
        .s_axi_rlast   (m05_rlast),
        .s_axi_rvalid  (m05_rvalid),
        .s_axi_rready  (m05_rready)
    );

    // M06: 16x8 TX Streaming FIFO (4 KiB @ 0x2000_4000)
    // Directly connects to SPI Master!
    wire       fifo_to_spi_rd_en;
    wire [7:0] fifo_to_spi_rd_data;
    wire       fifo_to_spi_data_valid;
    wire       fifo_to_spi_empty;
    wire       fifo_full_flag;

    fifo_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_fifo (
        .clk             (clk_i),
        .rst             (rst_high),
        .rst_n           (rst_ni),
        .s_axi_awid      (m06_awid),
        .s_axi_awaddr    (m06_awaddr),
        .s_axi_awlen     (m06_awlen),
        .s_axi_awsize    (m06_awsize),
        .s_axi_awburst   (m06_awburst),
        .s_axi_awlock    (m06_awlock),
        .s_axi_awcache   (m06_awcache),
        .s_axi_awprot    (m06_awprot),
        .s_axi_awqos     (m06_awqos),
        .s_axi_awregion  (m06_awregion),
        .s_axi_awvalid   (m06_awvalid),
        .s_axi_awready   (m06_awready),
        .s_axi_wdata     (m06_wdata),
        .s_axi_wstrb     (m06_wstrb),
        .s_axi_wlast     (m06_wlast),
        .s_axi_wvalid    (m06_wvalid),
        .s_axi_wready    (m06_wready),
        .s_axi_bid       (m06_bid),
        .s_axi_bresp     (m06_bresp),
        .s_axi_bvalid    (m06_bvalid),
        .s_axi_bready    (m06_bready),
        .s_axi_arid      (m06_arid),
        .s_axi_araddr    (m06_araddr),
        .s_axi_arlen     (m06_arlen),
        .s_axi_arsize    (m06_arsize),
        .s_axi_arburst   (m06_arburst),
        .s_axi_arlock    (m06_arlock),
        .s_axi_arcache   (m06_arcache),
        .s_axi_arprot    (m06_arprot),
        .s_axi_arqos     (m06_arqos),
        .s_axi_arregion  (m06_arregion),
        .s_axi_arvalid   (m06_arvalid),
        .s_axi_arready   (m06_arready),
        .s_axi_rid       (m06_rid),
        .s_axi_rdata     (m06_rdata),
        .s_axi_rresp     (m06_rresp),
        .s_axi_rlast     (m06_rlast),
        .s_axi_rvalid    (m06_rvalid),
        .s_axi_rready    (m06_rready),
        .fifo_rd_en      (fifo_to_spi_rd_en),
        .fifo_rd_data    (fifo_to_spi_rd_data),
        .fifo_data_valid (fifo_to_spi_data_valid),
        .fifo_empty      (fifo_to_spi_empty),
        .fifo_full       (fifo_full_flag)
    );

    // M07: SPI Master IP (4 KiB @ 0x2000_5000)
    spi_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_spi (
        .clk             (clk_i),
        .rst             (rst_high),
        .rst_n           (rst_ni),
        .s_axi_awid      (m07_awid),
        .s_axi_awaddr    (m07_awaddr),
        .s_axi_awlen     (m07_awlen),
        .s_axi_awsize    (m07_awsize),
        .s_axi_awburst   (m07_awburst),
        .s_axi_awlock    (m07_awlock),
        .s_axi_awcache   (m07_awcache),
        .s_axi_awprot    (m07_awprot),
        .s_axi_awqos     (m07_awqos),
        .s_axi_awregion  (m07_awregion),
        .s_axi_awvalid   (m07_awvalid),
        .s_axi_awready   (m07_awready),
        .s_axi_wdata     (m07_wdata),
        .s_axi_wstrb     (m07_wstrb),
        .s_axi_wlast     (m07_wlast),
        .s_axi_wvalid    (m07_wvalid),
        .s_axi_wready    (m07_wready),
        .s_axi_bid       (m07_bid),
        .s_axi_bresp     (m07_bresp),
        .s_axi_bvalid    (m07_bvalid),
        .s_axi_bready    (m07_bready),
        .s_axi_arid      (m07_arid),
        .s_axi_araddr    (m07_araddr),
        .s_axi_arlen     (m07_arlen),
        .s_axi_arsize    (m07_arsize),
        .s_axi_arburst   (m07_arburst),
        .s_axi_arlock    (m07_arlock),
        .s_axi_arcache   (m07_arcache),
        .s_axi_arprot    (m07_arprot),
        .s_axi_arqos     (m07_arqos),
        .s_axi_arregion  (m07_arregion),
        .s_axi_arvalid   (m07_arvalid),
        .s_axi_arready   (m07_arready),
        .s_axi_rid       (m07_rid),
        .s_axi_rdata     (m07_rdata),
        .s_axi_rresp     (m07_rresp),
        .s_axi_rlast     (m07_rlast),
        .s_axi_rvalid    (m07_rvalid),
        .s_axi_rready    (m07_rready),
        .fifo_rd_en      (fifo_to_spi_rd_en),
        .fifo_rd_data    (fifo_to_spi_rd_data),
        .fifo_data_valid (fifo_to_spi_data_valid),
        .fifo_empty      (fifo_to_spi_empty),
        .spi_mosi_o      (spi_mosi_o),
        .spi_miso_i      (spi_miso_i),
        .spi_sclk_o      (spi_sclk_o),
        .spi_cs_no       (spi_cs_no)
    );

endmodule

`default_nettype wire
