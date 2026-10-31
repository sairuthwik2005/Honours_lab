/*
 * ============================================================================
 * File: axi4_64_to_32_adapter.sv
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: AXI4 64-bit to 32-bit Data Width Adapter
 *              Supports:
 *                1. 64-bit transfers (AxSIZE=3): splits into two 32-bit beats
 *                   and reassembles read data.
 *                2. 32-bit or narrower single-beat transfers (AxSIZE<=2, AxLEN=0):
 *                   passes through without lengthening AxLEN, preserving the
 *                   single-beat constraint for peripheral registers!
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi4_64_to_32_adapter #(
    parameter integer SLAVE_ID_WIDTH  = 4,
    parameter integer MASTER_ID_WIDTH = 7,
    parameter integer ADDR_WIDTH      = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,      // Active-low reset

    // ------------------------------------------------------------------------
    // Slave Side (Connected to VeeR-EL2 LSU or IFU, 64-bit)
    // ------------------------------------------------------------------------
    input  wire [SLAVE_ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]        s_axi_awaddr,
    input  wire [7:0]                   s_axi_awlen,
    input  wire [2:0]                   s_axi_awsize,
    input  wire [1:0]                   s_axi_awburst,
    input  wire                         s_axi_awlock,
    input  wire [3:0]                   s_axi_awcache,
    input  wire [2:0]                   s_axi_awprot,
    input  wire [3:0]                   s_axi_awqos,
    input  wire [3:0]                   s_axi_awregion,
    input  wire                         s_axi_awvalid,
    output reg                          s_axi_awready,

    input  wire [63:0]                  s_axi_wdata,
    input  wire [7:0]                   s_axi_wstrb,
    input  wire                         s_axi_wlast,
    input  wire                         s_axi_wvalid,
    output reg                          s_axi_wready,

    output reg  [SLAVE_ID_WIDTH-1:0]    s_axi_bid,
    output reg  [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,

    input  wire [SLAVE_ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]        s_axi_araddr,
    input  wire [7:0]                   s_axi_arlen,
    input  wire [2:0]                   s_axi_arsize,
    input  wire [1:0]                   s_axi_arburst,
    input  wire                         s_axi_arlock,
    input  wire [3:0]                   s_axi_arcache,
    input  wire [2:0]                   s_axi_arprot,
    input  wire [3:0]                   s_axi_arqos,
    input  wire [3:0]                   s_axi_arregion,
    input  wire                         s_axi_arvalid,
    output reg                          s_axi_arready,

    output reg  [SLAVE_ID_WIDTH-1:0]    s_axi_rid,
    output reg  [63:0]                  s_axi_rdata,
    output reg  [1:0]                   s_axi_rresp,
    output reg                          s_axi_rlast,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    // ------------------------------------------------------------------------
    // Master Side (Connected to 32-bit AXI Interconnect, 32-bit)
    // ------------------------------------------------------------------------
    output reg  [MASTER_ID_WIDTH-1:0]   m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]        m_axi_awaddr,
    output reg  [7:0]                   m_axi_awlen,
    output reg  [2:0]                   m_axi_awsize,
    output reg  [1:0]                   m_axi_awburst,
    output reg                          m_axi_awlock,
    output reg  [3:0]                   m_axi_awcache,
    output reg  [2:0]                   m_axi_awprot,
    output reg  [3:0]                   m_axi_awqos,
    output reg  [3:0]                   m_axi_awregion,
    output reg                          m_axi_awvalid,
    input  wire                         m_axi_awready,

    output reg  [31:0]                  m_axi_wdata,
    output reg  [3:0]                   m_axi_wstrb,
    output reg                          m_axi_wlast,
    output reg                          m_axi_wvalid,
    input  wire                         m_axi_wready,

    input  wire [MASTER_ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output reg                          m_axi_bready,

    output reg  [MASTER_ID_WIDTH-1:0]   m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]        m_axi_araddr,
    output reg  [7:0]                   m_axi_arlen,
    output reg  [2:0]                   m_axi_arsize,
    output reg  [1:0]                   m_axi_arburst,
    output reg                          m_axi_arlock,
    output reg  [3:0]                   m_axi_arcache,
    output reg  [2:0]                   m_axi_arprot,
    output reg  [3:0]                   m_axi_arqos,
    output reg  [3:0]                   m_axi_arregion,
    output reg                          m_axi_arvalid,
    input  wire                         m_axi_arready,

    input  wire [MASTER_ID_WIDTH-1:0]   m_axi_rid,
    input  wire [31:0]                  m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output reg                          m_axi_rready
);

    wire rst = !rst_n;

    // =========================================================================
    // Write Path
    // =========================================================================
    localparam [1:0] W_IDLE     = 2'd0;
    localparam [1:0] W_ADDR     = 2'd1;
    localparam [1:0] W_DATA_LO  = 2'd2;
    localparam [1:0] W_DATA_HI  = 2'd3;

    reg [1:0] w_state;
    reg       w_is_64bit;
    reg [ADDR_WIDTH-1:0] w_saved_addr;
    reg [63:0]           w_saved_data;
    reg [7:0]            w_saved_strb;
    reg                  w_saved_last;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_state        <= W_IDLE;
            s_axi_awready  <= 1'b1;
            s_axi_wready   <= 1'b0;
            m_axi_awvalid  <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            m_axi_bready   <= 1'b1;
            w_is_64bit     <= 1'b0;
            w_saved_addr   <= {ADDR_WIDTH{1'b0}};
            w_saved_data   <= 64'd0;
            w_saved_strb   <= 8'd0;
            w_saved_last   <= 1'b0;
            m_axi_awid     <= {MASTER_ID_WIDTH{1'b0}};
            m_axi_awaddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen    <= 8'd0;
            m_axi_awsize   <= 3'd0;
            m_axi_awburst  <= 2'd0;
            m_axi_awlock   <= 1'b0;
            m_axi_awcache  <= 4'd0;
            m_axi_awprot   <= 3'd0;
            m_axi_awqos    <= 4'd0;
            m_axi_awregion <= 4'd0;
            m_axi_wdata    <= 32'd0;
            m_axi_wstrb    <= 4'd0;
            m_axi_wlast    <= 1'b0;
        end else begin
            // Drop AWVALID as soon as the address is accepted, in any state
            // (the address can be accepted after the data phase has started).
            if (m_axi_awvalid && m_axi_awready) begin
                m_axi_awvalid <= 1'b0;
            end
            case (w_state)
                W_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        w_saved_addr  <= s_axi_awaddr;
                        m_axi_awid    <= {{(MASTER_ID_WIDTH-SLAVE_ID_WIDTH){1'b0}}, s_axi_awid};
                        m_axi_awaddr  <= s_axi_awaddr;
                        m_axi_awburst <= s_axi_awburst;
                        m_axi_awlock  <= s_axi_awlock;
                        m_axi_awcache <= s_axi_awcache;
                        m_axi_awprot  <= s_axi_awprot;
                        m_axi_awqos   <= s_axi_awqos;
                        m_axi_awregion<= s_axi_awregion;

                        if (s_axi_awsize == 3'b011) begin
                            // 64-bit access: double length
                            w_is_64bit   <= 1'b1;
                            m_axi_awlen  <= {s_axi_awlen[6:0], 1'b1};
                            m_axi_awsize <= 3'b010;
                        end else begin
                            // 32-bit or narrower access: length unchanged (0 for single beat!)
                            w_is_64bit   <= 1'b0;
                            m_axi_awlen  <= s_axi_awlen;
                            m_axi_awsize <= s_axi_awsize;
                        end

                        m_axi_awvalid <= 1'b1;
                        w_state       <= W_ADDR;
                    end
                end

                W_ADDR: begin

                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready <= 1'b0;
                        w_saved_data <= s_axi_wdata;
                        w_saved_strb <= s_axi_wstrb;
                        w_saved_last <= s_axi_wlast;

                        if (w_is_64bit) begin
                            // First 32-bit beat (lower half)
                            m_axi_wdata  <= s_axi_wdata[31:0];
                            m_axi_wstrb  <= s_axi_wstrb[3:0];
                            m_axi_wlast  <= 1'b0;
                            m_axi_wvalid <= 1'b1;
                            w_state      <= W_DATA_LO;
                        end else begin
                            // 32-bit single beat: steer based on addr[2]
                            if (w_saved_addr[2]) begin
                                m_axi_wdata <= s_axi_wdata[63:32];
                                m_axi_wstrb <= s_axi_wstrb[7:4];
                            end else begin
                                m_axi_wdata <= s_axi_wdata[31:0];
                                m_axi_wstrb <= s_axi_wstrb[3:0];
                            end
                            m_axi_wlast  <= s_axi_wlast;
                            m_axi_wvalid <= 1'b1;
                            w_state      <= W_DATA_HI;
                        end
                    end
                end

                W_DATA_LO: begin
                    if (m_axi_wready) begin
                        // Second 32-bit beat (upper half)
                        m_axi_wdata  <= w_saved_data[63:32];
                        m_axi_wstrb  <= w_saved_strb[7:4];
                        m_axi_wlast  <= w_saved_last;
                        m_axi_wvalid <= 1'b1;
                        w_state      <= W_DATA_HI;
                    end
                end

                W_DATA_HI: begin
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        if (!m_axi_awvalid || m_axi_awready) begin
                            s_axi_awready <= 1'b1;
                            w_state       <= W_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    // Write Response Channel
    always @* begin
        s_axi_bvalid = m_axi_bvalid;
        s_axi_bresp  = m_axi_bresp;
        s_axi_bid    = m_axi_bid[SLAVE_ID_WIDTH-1:0];
    end

    // =========================================================================
    // Read Path
    // =========================================================================
    localparam [1:0] R_IDLE    = 2'd0;
    localparam [1:0] R_ISSUE   = 2'd1;
    localparam [1:0] R_COLLECT = 2'd2;

    reg [1:0]  r_state;
    reg        r_is_64bit;
    reg        r_sub_beat;
    reg [31:0] r_data_lo;
    reg [1:0]  r_resp_lo;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r_state        <= R_IDLE;
            s_axi_arready  <= 1'b1;
            m_axi_arvalid  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rlast    <= 1'b0;
            s_axi_rdata    <= 64'd0;
            s_axi_rresp    <= 2'd0;
            s_axi_rid      <= {SLAVE_ID_WIDTH{1'b0}};
            m_axi_rready   <= 1'b1;
            r_is_64bit     <= 1'b0;
            r_sub_beat     <= 1'b0;
            r_data_lo      <= 32'd0;
            r_resp_lo      <= 2'd0;
            m_axi_arid     <= {MASTER_ID_WIDTH{1'b0}};
            m_axi_araddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen    <= 8'd0;
            m_axi_arsize   <= 3'd0;
            m_axi_arburst  <= 2'd0;
            m_axi_arlock   <= 1'b0;
            m_axi_arcache  <= 4'd0;
            m_axi_arprot   <= 3'd0;
            m_axi_arqos    <= 4'd0;
            m_axi_arregion <= 4'd0;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            case (r_state)
                R_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arready  <= 1'b0;
                        m_axi_arid     <= {{(MASTER_ID_WIDTH-SLAVE_ID_WIDTH){1'b0}}, s_axi_arid};
                        m_axi_araddr   <= s_axi_araddr;
                        m_axi_arburst  <= s_axi_arburst;
                        m_axi_arlock   <= s_axi_arlock;
                        m_axi_arcache  <= s_axi_arcache;
                        m_axi_arprot   <= s_axi_arprot;
                        m_axi_arqos    <= s_axi_arqos;
                        m_axi_arregion <= s_axi_arregion;

                        if (s_axi_arsize == 3'b011) begin
                            // 64-bit access: double length
                            r_is_64bit   <= 1'b1;
                            m_axi_arlen  <= {s_axi_arlen[6:0], 1'b1};
                            m_axi_arsize <= 3'b010;
                        end else begin
                            // 32-bit access: single beat (len unchanged, e.g. 0)
                            r_is_64bit   <= 1'b0;
                            m_axi_arlen  <= s_axi_arlen;
                            m_axi_arsize <= s_axi_arsize;
                        end

                        m_axi_arvalid <= 1'b1;
                        r_state       <= R_ISSUE;
                    end
                end

                R_ISSUE: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        r_sub_beat    <= 1'b0;
                        r_state       <= R_COLLECT;
                    end
                end

                R_COLLECT: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (!r_is_64bit) begin
                            // Single 32-bit beat: replicate to both 32-bit halves
                            s_axi_rdata   <= {m_axi_rdata, m_axi_rdata};
                            s_axi_rresp   <= m_axi_rresp;
                            s_axi_rlast   <= m_axi_rlast;
                            s_axi_rid     <= m_axi_rid[SLAVE_ID_WIDTH-1:0];
                            s_axi_rvalid  <= 1'b1;
                            s_axi_arready <= 1'b1;
                            r_state       <= R_IDLE;
                        end else begin
                            // 64-bit access: assemble 2x 32-bit beats
                            if (r_sub_beat == 1'b0) begin
                                r_data_lo  <= m_axi_rdata;
                                r_resp_lo  <= m_axi_rresp;
                                r_sub_beat <= 1'b1;
                            end else begin
                                s_axi_rdata   <= {m_axi_rdata, r_data_lo};
                                s_axi_rresp   <= m_axi_rresp | r_resp_lo;
                                s_axi_rlast   <= m_axi_rlast;
                                s_axi_rid     <= m_axi_rid[SLAVE_ID_WIDTH-1:0];
                                s_axi_rvalid  <= 1'b1;
                                r_sub_beat    <= 1'b0;
                                if (m_axi_rlast) begin
                                    s_axi_arready <= 1'b1;
                                    r_state       <= R_IDLE;
                                end
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
