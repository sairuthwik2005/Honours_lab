/*
 * ============================================================================
 * File: spi_axi4.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Full AXI4 Subordinate Interface for SPI Master IP Core
 *              Base Address: 0x2000_5000 (Interconnect Slot M07)
 *              Rejects multi-beat bursts with SLVERR.
 *              Generates rx_read_pulse on reading RX_DATA.
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "spi_defines.vh"

module spi_axi4 #(
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
    output reg                   spi_enable,
    output reg                   spi_start,
    output reg                   spi_mode,
    output reg  [15:0]           spi_length,
    output reg  [15:0]           spi_clk_div,
    output reg                   spi_abort,
    output reg                   spi_clear_status,
    output reg                   rx_read_pulse,

    // Core Status Interface
    input  wire                  spi_busy,
    input  wire                  spi_done,
    input  wire [7:0]            spi_rx_data,
    input  wire                  spi_rx_valid,
    input  wire                  spi_rx_overrun
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
            s_axi_awready    <= 1'b1;
            s_axi_wready     <= 1'b1;
            s_axi_bvalid     <= 1'b0;
            s_axi_bid        <= {ID_WIDTH{1'b0}};
            s_axi_bresp      <= RESP_OKAY;
            aw_captured      <= 1'b0;
            w_captured       <= 1'b0;
            aw_id_reg        <= {ID_WIDTH{1'b0}};
            aw_addr_reg      <= {ADDR_WIDTH{1'b0}};
            aw_len_err       <= 1'b0;
            w_data_reg       <= {DATA_WIDTH{1'b0}};

            spi_enable       <= 1'b1;
            spi_start        <= 1'b0;
            spi_mode         <= 1'b0;
            spi_length       <= 16'd0;
            spi_clk_div      <= `SPI_DEFAULT_CLK_DIV;
            spi_abort        <= 1'b0;
            spi_clear_status <= 1'b0;
        end else begin
            // Default pulse clears
            spi_start        <= 1'b0;
            spi_abort        <= 1'b0;
            spi_clear_status <= 1'b0;

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Capture Write Address
            if (s_axi_awvalid && s_axi_awready) begin
                aw_captured   <= 1'b1;
                aw_id_reg     <= s_axi_awid;
                aw_addr_reg   <= s_axi_awaddr;
                aw_len_err    <= (s_axi_awlen != 8'd0);
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
                        `SPI_REG_CTRL: begin
                            spi_enable <= eff_data[`SPI_CTRL_ENABLE_BIT];
                            if (eff_data[`SPI_CTRL_START_BIT])
                                spi_start <= 1'b1;
                            spi_mode <= eff_data[`SPI_CTRL_MODE_BIT];
                            if (eff_data[`SPI_CTRL_ABORT_BIT])
                                spi_abort <= 1'b1;
                            if (eff_data[`SPI_CTRL_CLEAR_STAT_BIT])
                                spi_clear_status <= 1'b1;
                        end
                        `SPI_REG_LENGTH: begin
                            spi_length <= eff_data[15:0];
                        end
                        `SPI_REG_CLK_DIV: begin
                            spi_clk_div <= eff_data[15:0];
                        end
                        default: begin
                            // Read-only or reserved registers
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
            rx_read_pulse <= 1'b0;
        end else begin
            rx_read_pulse <= 1'b0;

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_rlast   <= 1'b0;
                s_axi_arready <= 1'b1;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid  <= 1'b1;
                s_axi_rid     <= s_axi_arid;
                s_axi_rlast   <= 1'b1;
                s_axi_arready <= 1'b0;

                if (s_axi_arlen != 8'd0) begin
                    // Bursts unsupported
                    s_axi_rresp <= RESP_SLVERR;
                    s_axi_rdata <= 32'hDEAD_BEEF;
                end else begin
                    s_axi_rresp <= RESP_OKAY;
                    case (s_axi_araddr[7:0])
                        `SPI_REG_CTRL: begin
                            s_axi_rdata <= {29'h0, spi_mode, 1'b0, spi_enable};
                        end
                        `SPI_REG_STATUS: begin
                            s_axi_rdata <= {28'h0, spi_rx_overrun, spi_rx_valid, spi_done, spi_busy};
                        end
                        `SPI_REG_LENGTH: begin
                            s_axi_rdata <= {16'h0, spi_length};
                        end
                        `SPI_REG_CLK_DIV: begin
                            s_axi_rdata <= {16'h0, spi_clk_div};
                        end
                        `SPI_REG_RX_DATA: begin
                            s_axi_rdata   <= {24'h0, spi_rx_data};
                            rx_read_pulse <= 1'b1; // Clears spi_rx_valid in core!
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
