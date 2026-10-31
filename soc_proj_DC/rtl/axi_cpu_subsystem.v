/*
 * ============================================================================
 * File: axi_cpu_subsystem.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: RISC-V VeeR-EL2 CPU Subsystem
 *              Integrates:
 *                1. el2_veer_wrapper (RV32IMC RISC-V Core)
 *                2. 64-to-32 bit adapters for IFU and LSU
 *                3. axi_crossbar_wrap_2x1 (Merges IFU & LSU into 1 unified master)
 *              Outputs:
 *                Single 32-bit Full AXI4 Master port (ID_WIDTH=8, DATA_WIDTH=32)
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "common_defines.vh"

module axi_cpu_subsystem
import el2_pkg::*;
#(
`include "el2_param.vh"
)(
    input  wire                  clk,
    input  wire                  rst_n,      // Active-low system reset

    // Unified 32-bit AXI4 CPU Master Output (to axi_interconnect_wrap_1x8 S00)
    output wire [7:0]            m_axi_awid,
    output wire [31:0]           m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_awlock,
    output wire [3:0]            m_axi_awcache,
    output wire [2:0]            m_axi_awprot,
    output wire [3:0]            m_axi_awqos,
    output wire [3:0]            m_axi_awregion,
    output wire                  m_axi_awvalid,
    input  wire                  m_axi_awready,

    output wire [31:0]           m_axi_wdata,
    output wire [3:0]            m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,

    input  wire [7:0]            m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,

    output wire [7:0]            m_axi_arid,
    output wire [31:0]           m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arlock,
    output wire [3:0]            m_axi_arcache,
    output wire [2:0]            m_axi_arprot,
    output wire [3:0]            m_axi_arqos,
    output wire [3:0]            m_axi_arregion,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,

    input  wire [7:0]            m_axi_rid,
    input  wire [31:0]           m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready
);

    // VeeR LSU AXI Wires (64-bit)
    wire                      lsu_awvalid;
    wire                      lsu_awready;
    wire [pt.LSU_BUS_TAG-1:0] lsu_awid;
    wire [31:0]               lsu_awaddr;
    wire [3:0]                lsu_awregion;
    wire [7:0]                lsu_awlen;
    wire [2:0]                lsu_awsize;
    wire [1:0]                lsu_awburst;
    wire                      lsu_awlock;
    wire [3:0]                lsu_awcache;
    wire [2:0]                lsu_awprot;
    wire [3:0]                lsu_awqos;

    wire                      lsu_wvalid;
    wire                      lsu_wready;
    wire [63:0]               lsu_wdata;
    wire [7:0]                lsu_wstrb;
    wire                      lsu_wlast;

    wire                      lsu_bvalid;
    wire                      lsu_bready;
    wire [1:0]                lsu_bresp;
    wire [pt.LSU_BUS_TAG-1:0] lsu_bid;

    wire                      lsu_arvalid;
    wire                      lsu_arready;
    wire [pt.LSU_BUS_TAG-1:0] lsu_arid;
    wire [31:0]               lsu_araddr;
    wire [3:0]                lsu_arregion;
    wire [7:0]                lsu_arlen;
    wire [2:0]                lsu_arsize;
    wire [1:0]                lsu_arburst;
    wire                      lsu_arlock;
    wire [3:0]                lsu_arcache;
    wire [2:0]                lsu_arprot;
    wire [3:0]                lsu_arqos;

    wire                      lsu_rvalid;
    wire                      lsu_rready;
    wire [pt.LSU_BUS_TAG-1:0] lsu_rid;
    wire [63:0]               lsu_rdata;
    wire [1:0]                lsu_rresp;
    wire                      lsu_rlast;

    // VeeR IFU AXI Wires (64-bit)
    wire                      ifu_awvalid;
    wire                      ifu_awready;
    wire [pt.IFU_BUS_TAG-1:0] ifu_awid;
    wire [31:0]               ifu_awaddr;
    wire [3:0]                ifu_awregion;
    wire [7:0]                ifu_awlen;
    wire [2:0]                ifu_awsize;
    wire [1:0]                ifu_awburst;
    wire                      ifu_awlock;
    wire [3:0]                ifu_awcache;
    wire [2:0]                ifu_awprot;
    wire [3:0]                ifu_awqos;

    wire                      ifu_wvalid;
    wire                      ifu_wready;
    wire [63:0]               ifu_wdata;
    wire [7:0]                ifu_wstrb;
    wire                      ifu_wlast;

    wire                      ifu_bvalid;
    wire                      ifu_bready;
    wire [1:0]                ifu_bresp;
    wire [pt.IFU_BUS_TAG-1:0] ifu_bid;

    wire                      ifu_arvalid;
    wire                      ifu_arready;
    wire [pt.IFU_BUS_TAG-1:0] ifu_arid;
    wire [31:0]               ifu_araddr;
    wire [3:0]                ifu_arregion;
    wire [7:0]                ifu_arlen;
    wire [2:0]                ifu_arsize;
    wire [1:0]                ifu_arburst;
    wire                      ifu_arlock;
    wire [3:0]                ifu_arcache;
    wire [2:0]                ifu_arprot;
    wire [3:0]                ifu_arqos;

    wire                      ifu_rvalid;
    wire                      ifu_rready;
    wire [pt.IFU_BUS_TAG-1:0] ifu_rid;
    wire [63:0]               ifu_rdata;
    wire [1:0]                ifu_rresp;
    wire                      ifu_rlast;

    // VeeR memory export interface. ICCM, DCCM and I-cache are disabled in the
    // 'soc' snapshot, so no SRAM macros are attached; the interface only has to exist.
    el2_mem_if u_mem_if ();

    // Instantiate VeeR-EL2 Core Top
    el2_veer_wrapper u_veer (
        .clk                     (clk),
        .rst_l                   (rst_n),
        .dbg_rst_l               (rst_n),
        .rst_vec                 (31'h0000_0000), // Boot from 0x0000_0000 (IMEM)
        .nmi_int                 (1'b0),
        .nmi_vec                 (31'h0000_0000),
        .jtag_id                 (31'h0000_0001),

        .trace_rv_i_insn_ip      (),
        .trace_rv_i_address_ip   (),
        .trace_rv_i_valid_ip     (),
        .trace_rv_i_exception_ip (),
        .trace_rv_i_ecause_ip    (),
        .trace_rv_i_interrupt_ip (),
        .trace_rv_i_tval_ip      (),

        // LSU AXI
        .lsu_axi_awvalid         (lsu_awvalid),
        .lsu_axi_awready         (lsu_awready),
        .lsu_axi_awid            (lsu_awid),
        .lsu_axi_awaddr          (lsu_awaddr),
        .lsu_axi_awregion        (lsu_awregion),
        .lsu_axi_awlen           (lsu_awlen),
        .lsu_axi_awsize          (lsu_awsize),
        .lsu_axi_awburst         (lsu_awburst),
        .lsu_axi_awlock          (lsu_awlock),
        .lsu_axi_awcache         (lsu_awcache),
        .lsu_axi_awprot          (lsu_awprot),
        .lsu_axi_awqos           (lsu_awqos),
        .lsu_axi_wvalid          (lsu_wvalid),
        .lsu_axi_wready          (lsu_wready),
        .lsu_axi_wdata           (lsu_wdata),
        .lsu_axi_wstrb           (lsu_wstrb),
        .lsu_axi_wlast           (lsu_wlast),
        .lsu_axi_bvalid          (lsu_bvalid),
        .lsu_axi_bready          (lsu_bready),
        .lsu_axi_bresp           (lsu_bresp),
        .lsu_axi_bid             (lsu_bid),
        .lsu_axi_arvalid         (lsu_arvalid),
        .lsu_axi_arready         (lsu_arready),
        .lsu_axi_arid            (lsu_arid),
        .lsu_axi_araddr          (lsu_araddr),
        .lsu_axi_arregion        (lsu_arregion),
        .lsu_axi_arlen           (lsu_arlen),
        .lsu_axi_arsize          (lsu_arsize),
        .lsu_axi_arburst         (lsu_arburst),
        .lsu_axi_arlock          (lsu_arlock),
        .lsu_axi_arcache         (lsu_arcache),
        .lsu_axi_arprot          (lsu_arprot),
        .lsu_axi_arqos           (lsu_arqos),
        .lsu_axi_rvalid          (lsu_rvalid),
        .lsu_axi_rready          (lsu_rready),
        .lsu_axi_rid             (lsu_rid),
        .lsu_axi_rdata           (lsu_rdata),
        .lsu_axi_rresp           (lsu_rresp),
        .lsu_axi_rlast           (lsu_rlast),

        // IFU AXI
        .ifu_axi_awvalid         (ifu_awvalid),
        .ifu_axi_awready         (ifu_awready),
        .ifu_axi_awid            (ifu_awid),
        .ifu_axi_awaddr          (ifu_awaddr),
        .ifu_axi_awregion        (ifu_awregion),
        .ifu_axi_awlen           (ifu_awlen),
        .ifu_axi_awsize          (ifu_awsize),
        .ifu_axi_awburst         (ifu_awburst),
        .ifu_axi_awlock          (ifu_awlock),
        .ifu_axi_awcache         (ifu_awcache),
        .ifu_axi_awprot          (ifu_awprot),
        .ifu_axi_awqos           (ifu_awqos),
        .ifu_axi_wvalid          (ifu_wvalid),
        .ifu_axi_wready          (ifu_wready),
        .ifu_axi_wdata           (ifu_wdata),
        .ifu_axi_wstrb           (ifu_wstrb),
        .ifu_axi_wlast           (ifu_wlast),
        .ifu_axi_bvalid          (ifu_bvalid),
        .ifu_axi_bready          (ifu_bready),
        .ifu_axi_bresp           (ifu_bresp),
        .ifu_axi_bid             (ifu_bid),
        .ifu_axi_arvalid         (ifu_arvalid),
        .ifu_axi_arready         (ifu_arready),
        .ifu_axi_arid            (ifu_arid),
        .ifu_axi_araddr          (ifu_araddr),
        .ifu_axi_arregion        (ifu_arregion),
        .ifu_axi_arlen           (ifu_arlen),
        .ifu_axi_arsize          (ifu_arsize),
        .ifu_axi_arburst         (ifu_arburst),
        .ifu_axi_arlock          (ifu_arlock),
        .ifu_axi_arcache         (ifu_arcache),
        .ifu_axi_arprot          (ifu_arprot),
        .ifu_axi_arqos           (ifu_arqos),
        .ifu_axi_rvalid          (ifu_rvalid),
        .ifu_axi_rready          (ifu_rready),
        .ifu_axi_rid             (ifu_rid),
        .ifu_axi_rdata           (ifu_rdata),
        .ifu_axi_rresp           (ifu_rresp),
        .ifu_axi_rlast           (ifu_rlast),

        // SB AXI (Tied off)
        .sb_axi_awvalid          (),
        .sb_axi_awready          (1'b0),
        .sb_axi_awid             (),
        .sb_axi_awaddr           (),
        .sb_axi_awregion         (),
        .sb_axi_awlen            (),
        .sb_axi_awsize           (),
        .sb_axi_awburst          (),
        .sb_axi_awlock           (),
        .sb_axi_awcache          (),
        .sb_axi_awprot           (),
        .sb_axi_awqos            (),
        .sb_axi_wvalid           (),
        .sb_axi_wready           (1'b0),
        .sb_axi_wdata            (),
        .sb_axi_wstrb            (),
        .sb_axi_wlast            (),
        .sb_axi_bvalid           (1'b0),
        .sb_axi_bready           (),
        .sb_axi_bresp            (2'b00),
        .sb_axi_bid              ('0),
        .sb_axi_arvalid          (),
        .sb_axi_arready          (1'b0),
        .sb_axi_arid             (),
        .sb_axi_araddr           (),
        .sb_axi_arregion         (),
        .sb_axi_arlen            (),
        .sb_axi_arsize           (),
        .sb_axi_arburst          (),
        .sb_axi_arlock           (),
        .sb_axi_arcache          (),
        .sb_axi_arprot           (),
        .sb_axi_arqos            (),
        .sb_axi_rvalid           (1'b0),
        .sb_axi_rready           (),
        .sb_axi_rid              ('0),
        .sb_axi_rdata            ('0),
        .sb_axi_rresp            (2'b00),
        .sb_axi_rlast            (1'b0),

        // DMA AXI (Tied off)
        .dma_axi_awvalid         (1'b0),
        .dma_axi_awready         (),
        .dma_axi_awid            ('0),
        .dma_axi_awaddr          ('0),
        .dma_axi_awsize          ('0),
        .dma_axi_awprot          ('0),
        .dma_axi_awlen           ('0),
        .dma_axi_awburst         ('0),
        .dma_axi_wvalid          (1'b0),
        .dma_axi_wready          (),
        .dma_axi_wdata           ('0),
        .dma_axi_wstrb           ('0),
        .dma_axi_wlast           (1'b0),
        .dma_axi_bvalid          (),
        .dma_axi_bready          (1'b1),
        .dma_axi_bresp           (),
        .dma_axi_bid             (),
        .dma_axi_arvalid         (1'b0),
        .dma_axi_arready         (),
        .dma_axi_arid            ('0),
        .dma_axi_araddr          ('0),
        .dma_axi_arsize          ('0),
        .dma_axi_arprot          ('0),
        .dma_axi_arlen           ('0),
        .dma_axi_arburst         ('0),
        .dma_axi_rvalid          (),
        .dma_axi_rready          (1'b1),
        .dma_axi_rid             (),
        .dma_axi_rdata           (),
        .dma_axi_rresp           (),
        .dma_axi_rlast           (),

        .lsu_bus_clk_en          (1'b1),
        .ifu_bus_clk_en          (1'b1),
        .dbg_bus_clk_en          (1'b0),
        .dma_bus_clk_en          (1'b0),
        .timer_int               (1'b0),
        .extintsrc_req           ('0),
        .dec_tlu_perfcnt0        (),
        .dec_tlu_perfcnt1        (),
        .dec_tlu_perfcnt2        (),
        .dec_tlu_perfcnt3        (),
        .mpc_debug_halt_req      (1'b0),
        .mpc_debug_run_req       (1'b0),
        .mpc_reset_run_req       (1'b1),
        .mpc_debug_halt_ack      (),
        .mpc_debug_run_ack       (),
        .debug_brkpt_status      (),
        .i_cpu_halt_req          (1'b0),
        .i_cpu_run_req           (1'b0),
        .o_cpu_halt_ack          (),
        .o_cpu_halt_status       (),
        .o_cpu_run_ack           (),
        .o_debug_mode_status     (),
        // (no core_sleep_o port on this VeeR version)
        // Memory export interfaces (no ICCM/DCCM/I-cache in this SoC)
        .el2_mem_export          (u_mem_if.veer_sram_src),
        .el2_icache_export       (u_mem_if.veer_icache_src),
        // ECC status (unused)
        .iccm_ecc_single_error   (),
        .iccm_ecc_double_error   (),
        .dccm_ecc_single_error   (),
        .dccm_ecc_double_error   (),
        .dccm_write_readback_error(),
        // JTAG debug port: not used, held inactive
        .jtag_tck                (1'b0),
        .jtag_tms                (1'b0),
        .jtag_tdi                (1'b0),
        .jtag_trst_n             (1'b0),
        .jtag_tdo                (),
        .jtag_tdoEn              (),
        // Misc core inputs
        .soft_int                (1'b0),
        .core_id                 (28'h0),
        .scan_mode               (1'b0),
        .mbist_mode              (1'b0),
        // Debug module interface: core enabled, no uncore
        .dmi_core_enable         (1'b1),
        .dmi_uncore_enable       (1'b0),
        .dmi_uncore_en           (),
        .dmi_uncore_wr_en        (),
        .dmi_uncore_addr         (),
        .dmi_uncore_wdata        (),
        .dmi_uncore_rdata        (32'h0),
        .dmi_active              ()
    );

    // -------------------------------------------------------------------------
    // Adapters: 64-bit to 32-bit (S_ID=pt.BUS_TAG=3 -> M_ID=7)
    // -------------------------------------------------------------------------
    wire [6:0]  ifu32_awid,    lsu32_awid;
    wire [31:0] ifu32_awaddr,  lsu32_awaddr;
    wire [7:0]  ifu32_awlen,   lsu32_awlen;
    wire [2:0]  ifu32_awsize,  lsu32_awsize;
    wire [1:0]  ifu32_awburst, lsu32_awburst;
    wire        ifu32_awlock,  lsu32_awlock;
    wire [3:0]  ifu32_awcache, lsu32_awcache;
    wire [2:0]  ifu32_awprot,  lsu32_awprot;
    wire [3:0]  ifu32_awqos,   lsu32_awqos;
    wire [3:0]  ifu32_awregion,lsu32_awregion;
    wire        ifu32_awvalid, lsu32_awvalid;
    wire        ifu32_awready, lsu32_awready;

    wire [31:0] ifu32_wdata,   lsu32_wdata;
    wire [3:0]  ifu32_wstrb,   lsu32_wstrb;
    wire        ifu32_wlast,   lsu32_wlast;
    wire        ifu32_wvalid,  lsu32_wvalid;
    wire        ifu32_wready,  lsu32_wready;

    wire [6:0]  ifu32_bid,     lsu32_bid;
    wire [1:0]  ifu32_bresp,   lsu32_bresp;
    wire        ifu32_bvalid,  lsu32_bvalid;
    wire        ifu32_bready,  lsu32_bready;

    wire [6:0]  ifu32_arid,    lsu32_arid;
    wire [31:0] ifu32_araddr,  lsu32_araddr;
    wire [7:0]  ifu32_arlen,   lsu32_arlen;
    wire [2:0]  ifu32_arsize,  lsu32_arsize;
    wire [1:0]  ifu32_arburst, lsu32_arburst;
    wire        ifu32_arlock,  lsu32_arlock;
    wire [3:0]  ifu32_arcache, lsu32_arcache;
    wire [2:0]  ifu32_arprot,  lsu32_arprot;
    wire [3:0]  ifu32_arqos,   lsu32_arqos;
    wire [3:0]  ifu32_arregion,lsu32_arregion;
    wire        ifu32_arvalid, lsu32_arvalid;
    wire        ifu32_arready, lsu32_arready;

    wire [6:0]  ifu32_rid,     lsu32_rid;
    wire [31:0] ifu32_rdata,   lsu32_rdata;
    wire [1:0]  ifu32_rresp,   lsu32_rresp;
    wire        ifu32_rlast,   lsu32_rlast;
    wire        ifu32_rvalid,  lsu32_rvalid;
    wire        ifu32_rready,  lsu32_rready;

    axi4_64_to_32_adapter #(
        .SLAVE_ID_WIDTH  (pt.IFU_BUS_TAG),
        .MASTER_ID_WIDTH (7),
        .ADDR_WIDTH      (32)
    ) u_ifu_adapter (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awid      (ifu_awid),
        .s_axi_awaddr    (ifu_awaddr),
        .s_axi_awlen     (ifu_awlen),
        .s_axi_awsize    (ifu_awsize),
        .s_axi_awburst   (ifu_awburst),
        .s_axi_awlock    (ifu_awlock),
        .s_axi_awcache   (ifu_awcache),
        .s_axi_awprot    (ifu_awprot),
        .s_axi_awqos     (ifu_awqos),
        .s_axi_awregion  (ifu_awregion),
        .s_axi_awvalid   (ifu_awvalid),
        .s_axi_awready   (ifu_awready),
        .s_axi_wdata     (ifu_wdata),
        .s_axi_wstrb     (ifu_wstrb),
        .s_axi_wlast     (ifu_wlast),
        .s_axi_wvalid    (ifu_wvalid),
        .s_axi_wready    (ifu_wready),
        .s_axi_bid       (ifu_bid),
        .s_axi_bresp     (ifu_bresp),
        .s_axi_bvalid    (ifu_bvalid),
        .s_axi_bready    (ifu_bready),
        .s_axi_arid      (ifu_arid),
        .s_axi_araddr    (ifu_araddr),
        .s_axi_arlen     (ifu_arlen),
        .s_axi_arsize    (ifu_arsize),
        .s_axi_arburst   (ifu_arburst),
        .s_axi_arlock    (ifu_arlock),
        .s_axi_arcache   (ifu_arcache),
        .s_axi_arprot    (ifu_arprot),
        .s_axi_arqos     (ifu_arqos),
        .s_axi_arregion  (ifu_arregion),
        .s_axi_arvalid   (ifu_arvalid),
        .s_axi_arready   (ifu_arready),
        .s_axi_rid       (ifu_rid),
        .s_axi_rdata     (ifu_rdata),
        .s_axi_rresp     (ifu_rresp),
        .s_axi_rlast     (ifu_rlast),
        .s_axi_rvalid    (ifu_rvalid),
        .s_axi_rready    (ifu_rready),
        .m_axi_awid      (ifu32_awid),
        .m_axi_awaddr    (ifu32_awaddr),
        .m_axi_awlen     (ifu32_awlen),
        .m_axi_awsize    (ifu32_awsize),
        .m_axi_awburst   (ifu32_awburst),
        .m_axi_awlock    (ifu32_awlock),
        .m_axi_awcache   (ifu32_awcache),
        .m_axi_awprot    (ifu32_awprot),
        .m_axi_awqos     (ifu32_awqos),
        .m_axi_awregion  (ifu32_awregion),
        .m_axi_awvalid   (ifu32_awvalid),
        .m_axi_awready   (ifu32_awready),
        .m_axi_wdata     (ifu32_wdata),
        .m_axi_wstrb     (ifu32_wstrb),
        .m_axi_wlast     (ifu32_wlast),
        .m_axi_wvalid    (ifu32_wvalid),
        .m_axi_wready    (ifu32_wready),
        .m_axi_bid       (ifu32_bid),
        .m_axi_bresp     (ifu32_bresp),
        .m_axi_bvalid    (ifu32_bvalid),
        .m_axi_bready    (ifu32_bready),
        .m_axi_arid      (ifu32_arid),
        .m_axi_araddr    (ifu32_araddr),
        .m_axi_arlen     (ifu32_arlen),
        .m_axi_arsize    (ifu32_arsize),
        .m_axi_arburst   (ifu32_arburst),
        .m_axi_arlock    (ifu32_arlock),
        .m_axi_arcache   (ifu32_arcache),
        .m_axi_arprot    (ifu32_arprot),
        .m_axi_arqos     (ifu32_arqos),
        .m_axi_arregion  (ifu32_arregion),
        .m_axi_arvalid   (ifu32_arvalid),
        .m_axi_arready   (ifu32_arready),
        .m_axi_rid       (ifu32_rid),
        .m_axi_rdata     (ifu32_rdata),
        .m_axi_rresp     (ifu32_rresp),
        .m_axi_rlast     (ifu32_rlast),
        .m_axi_rvalid    (ifu32_rvalid),
        .m_axi_rready    (ifu32_rready)
    );

    axi4_64_to_32_adapter #(
        .SLAVE_ID_WIDTH  (pt.LSU_BUS_TAG),
        .MASTER_ID_WIDTH (7),
        .ADDR_WIDTH      (32)
    ) u_lsu_adapter (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awid      (lsu_awid),
        .s_axi_awaddr    (lsu_awaddr),
        .s_axi_awlen     (lsu_awlen),
        .s_axi_awsize    (lsu_awsize),
        .s_axi_awburst   (lsu_awburst),
        .s_axi_awlock    (lsu_awlock),
        .s_axi_awcache   (lsu_awcache),
        .s_axi_awprot    (lsu_awprot),
        .s_axi_awqos     (lsu_awqos),
        .s_axi_awregion  (lsu_awregion),
        .s_axi_awvalid   (lsu_awvalid),
        .s_axi_awready   (lsu_awready),
        .s_axi_wdata     (lsu_wdata),
        .s_axi_wstrb     (lsu_wstrb),
        .s_axi_wlast     (lsu_wlast),
        .s_axi_wvalid    (lsu_wvalid),
        .s_axi_wready    (lsu_wready),
        .s_axi_bid       (lsu_bid),
        .s_axi_bresp     (lsu_bresp),
        .s_axi_bvalid    (lsu_bvalid),
        .s_axi_bready    (lsu_bready),
        .s_axi_arid      (lsu_arid),
        .s_axi_araddr    (lsu_araddr),
        .s_axi_arlen     (lsu_arlen),
        .s_axi_arsize    (lsu_arsize),
        .s_axi_arburst   (lsu_arburst),
        .s_axi_arlock    (lsu_arlock),
        .s_axi_arcache   (lsu_arcache),
        .s_axi_arprot    (lsu_arprot),
        .s_axi_arqos     (lsu_arqos),
        .s_axi_arregion  (lsu_arregion),
        .s_axi_arvalid   (lsu_arvalid),
        .s_axi_arready   (lsu_arready),
        .s_axi_rid       (lsu_rid),
        .s_axi_rdata     (lsu_rdata),
        .s_axi_rresp     (lsu_rresp),
        .s_axi_rlast     (lsu_rlast),
        .s_axi_rvalid    (lsu_rvalid),
        .s_axi_rready    (lsu_rready),
        .m_axi_awid      (lsu32_awid),
        .m_axi_awaddr    (lsu32_awaddr),
        .m_axi_awlen     (lsu32_awlen),
        .m_axi_awsize    (lsu32_awsize),
        .m_axi_awburst   (lsu32_awburst),
        .m_axi_awlock    (lsu32_awlock),
        .m_axi_awcache   (lsu32_awcache),
        .m_axi_awprot    (lsu32_awprot),
        .m_axi_awqos     (lsu32_awqos),
        .m_axi_awregion  (lsu32_awregion),
        .m_axi_awvalid   (lsu32_awvalid),
        .m_axi_awready   (lsu32_awready),
        .m_axi_wdata     (lsu32_wdata),
        .m_axi_wstrb     (lsu32_wstrb),
        .m_axi_wlast     (lsu32_wlast),
        .m_axi_wvalid    (lsu32_wvalid),
        .m_axi_wready    (lsu32_wready),
        .m_axi_bid       (lsu32_bid),
        .m_axi_bresp     (lsu32_bresp),
        .m_axi_bvalid    (lsu32_bvalid),
        .m_axi_bready    (lsu32_bready),
        .m_axi_arid      (lsu32_arid),
        .m_axi_araddr    (lsu32_araddr),
        .m_axi_arlen     (lsu32_arlen),
        .m_axi_arsize    (lsu32_arsize),
        .m_axi_arburst   (lsu32_arburst),
        .m_axi_arlock    (lsu32_arlock),
        .m_axi_arcache   (lsu32_arcache),
        .m_axi_arprot    (lsu32_arprot),
        .m_axi_arqos     (lsu32_arqos),
        .m_axi_arregion  (lsu32_arregion),
        .m_axi_arvalid   (lsu32_arvalid),
        .m_axi_arready   (lsu32_arready),
        .m_axi_rid       (lsu32_rid),
        .m_axi_rdata     (lsu32_rdata),
        .m_axi_rresp     (lsu32_rresp),
        .m_axi_rlast     (lsu32_rlast),
        .m_axi_rvalid    (lsu32_rvalid),
        .m_axi_rready    (lsu32_rready)
    );

    // -------------------------------------------------------------------------
    // 2x1 AXI Crossbar: Merges IFU (S00) and LSU (S01) into 1 Unified Master (M00)
    // S_ID_WIDTH = 7 -> M_ID_WIDTH = 8
    // -------------------------------------------------------------------------
    axi_crossbar_wrap_2x1 #(
        .S_COUNT       (2),
        .M_COUNT       (1),
        .DATA_WIDTH    (32),
        .ADDR_WIDTH    (32),
        .STRB_WIDTH    (4),
        .S_ID_WIDTH    (7),
        .M_ID_WIDTH    (8),
        .M00_ADDR_WIDTH(32)
    ) u_crossbar_2x1 (
        .clk             (clk),
        .rst             (!rst_n),

        // S00: IFU
        .s00_axi_awid    (ifu32_awid),
        .s00_axi_awaddr  (ifu32_awaddr),
        .s00_axi_awlen   (ifu32_awlen),
        .s00_axi_awsize  (ifu32_awsize),
        .s00_axi_awburst (ifu32_awburst),
        .s00_axi_awlock  (ifu32_awlock),
        .s00_axi_awcache (ifu32_awcache),
        .s00_axi_awprot  (ifu32_awprot),
        .s00_axi_awqos   (ifu32_awqos),
        .s00_axi_awuser  (1'b0),
        .s00_axi_awvalid (ifu32_awvalid),
        .s00_axi_awready (ifu32_awready),
        .s00_axi_wdata   (ifu32_wdata),
        .s00_axi_wstrb   (ifu32_wstrb),
        .s00_axi_wlast   (ifu32_wlast),
        .s00_axi_wuser   (1'b0),
        .s00_axi_wvalid  (ifu32_wvalid),
        .s00_axi_wready  (ifu32_wready),
        .s00_axi_bid     (ifu32_bid),
        .s00_axi_bresp   (ifu32_bresp),
        .s00_axi_buser   (),
        .s00_axi_bvalid  (ifu32_bvalid),
        .s00_axi_bready  (ifu32_bready),
        .s00_axi_arid    (ifu32_arid),
        .s00_axi_araddr  (ifu32_araddr),
        .s00_axi_arlen   (ifu32_arlen),
        .s00_axi_arsize  (ifu32_arsize),
        .s00_axi_arburst (ifu32_arburst),
        .s00_axi_arlock  (ifu32_arlock),
        .s00_axi_arcache (ifu32_arcache),
        .s00_axi_arprot  (ifu32_arprot),
        .s00_axi_arqos   (ifu32_arqos),
        .s00_axi_aruser  (1'b0),
        .s00_axi_arvalid (ifu32_arvalid),
        .s00_axi_arready (ifu32_arready),
        .s00_axi_rid     (ifu32_rid),
        .s00_axi_rdata   (ifu32_rdata),
        .s00_axi_rresp   (ifu32_rresp),
        .s00_axi_rlast   (ifu32_rlast),
        .s00_axi_ruser   (),
        .s00_axi_rvalid  (ifu32_rvalid),
        .s00_axi_rready  (ifu32_rready),

        // S01: LSU
        .s01_axi_awid    (lsu32_awid),
        .s01_axi_awaddr  (lsu32_awaddr),
        .s01_axi_awlen   (lsu32_awlen),
        .s01_axi_awsize  (lsu32_awsize),
        .s01_axi_awburst (lsu32_awburst),
        .s01_axi_awlock  (lsu32_awlock),
        .s01_axi_awcache (lsu32_awcache),
        .s01_axi_awprot  (lsu32_awprot),
        .s01_axi_awqos   (lsu32_awqos),
        .s01_axi_awuser  (1'b0),
        .s01_axi_awvalid (lsu32_awvalid),
        .s01_axi_awready (lsu32_awready),
        .s01_axi_wdata   (lsu32_wdata),
        .s01_axi_wstrb   (lsu32_wstrb),
        .s01_axi_wlast   (lsu32_wlast),
        .s01_axi_wuser   (1'b0),
        .s01_axi_wvalid  (lsu32_wvalid),
        .s01_axi_wready  (lsu32_wready),
        .s01_axi_bid     (lsu32_bid),
        .s01_axi_bresp   (lsu32_bresp),
        .s01_axi_buser   (),
        .s01_axi_bvalid  (lsu32_bvalid),
        .s01_axi_bready  (lsu32_bready),
        .s01_axi_arid    (lsu32_arid),
        .s01_axi_araddr  (lsu32_araddr),
        .s01_axi_arlen   (lsu32_arlen),
        .s01_axi_arsize  (lsu32_arsize),
        .s01_axi_arburst (lsu32_arburst),
        .s01_axi_arlock  (lsu32_arlock),
        .s01_axi_arcache (lsu32_arcache),
        .s01_axi_arprot  (lsu32_arprot),
        .s01_axi_arqos   (lsu32_arqos),
        .s01_axi_aruser  (1'b0),
        .s01_axi_arvalid (lsu32_arvalid),
        .s01_axi_arready (lsu32_arready),
        .s01_axi_rid     (lsu32_rid),
        .s01_axi_rdata   (lsu32_rdata),
        .s01_axi_rresp   (lsu32_rresp),
        .s01_axi_rlast   (lsu32_rlast),
        .s01_axi_ruser   (),
        .s01_axi_rvalid  (lsu32_rvalid),
        .s01_axi_rready  (lsu32_rready),

        // M00 Output (Single Unified 32-bit Master, ID_WIDTH=8)
        .m00_axi_awid    (m_axi_awid),
        .m00_axi_awaddr  (m_axi_awaddr),
        .m00_axi_awlen   (m_axi_awlen),
        .m00_axi_awsize  (m_axi_awsize),
        .m00_axi_awburst (m_axi_awburst),
        .m00_axi_awlock  (m_axi_awlock),
        .m00_axi_awcache (m_axi_awcache),
        .m00_axi_awprot  (m_axi_awprot),
        .m00_axi_awqos   (m_axi_awqos),
        .m00_axi_awregion(m_axi_awregion),
        .m00_axi_awuser  (),
        .m00_axi_awvalid (m_axi_awvalid),
        .m00_axi_awready (m_axi_awready),
        .m00_axi_wdata   (m_axi_wdata),
        .m00_axi_wstrb   (m_axi_wstrb),
        .m00_axi_wlast   (m_axi_wlast),
        .m00_axi_wuser   (),
        .m00_axi_wvalid  (m_axi_wvalid),
        .m00_axi_wready  (m_axi_wready),
        .m00_axi_bid     (m_axi_bid),
        .m00_axi_bresp   (m_axi_bresp),
        .m00_axi_buser   (1'b0),
        .m00_axi_bvalid  (m_axi_bvalid),
        .m00_axi_bready  (m_axi_bready),
        .m00_axi_arid    (m_axi_arid),
        .m00_axi_araddr  (m_axi_araddr),
        .m00_axi_arlen   (m_axi_arlen),
        .m00_axi_arsize  (m_axi_arsize),
        .m00_axi_arburst (m_axi_arburst),
        .m00_axi_arlock  (m_axi_arlock),
        .m00_axi_arcache (m_axi_arcache),
        .m00_axi_arprot  (m_axi_arprot),
        .m00_axi_arqos   (m_axi_arqos),
        .m00_axi_arregion(m_axi_arregion),
        .m00_axi_aruser  (),
        .m00_axi_arvalid (m_axi_arvalid),
        .m00_axi_arready (m_axi_arready),
        .m00_axi_rid     (m_axi_rid),
        .m00_axi_rdata   (m_axi_rdata),
        .m00_axi_rresp   (m_axi_rresp),
        .m00_axi_rlast   (m_axi_rlast),
        .m00_axi_ruser   (1'b0),
        .m00_axi_rvalid  (m_axi_rvalid),
        .m00_axi_rready  (m_axi_rready)
    );

endmodule

`default_nettype wire
