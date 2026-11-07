/*
 * ============================================================================
 * File: tb_crc_top.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Comprehensive Self-Checking Testbench for CRC-16 IP Core
 *              Tests:
 *                1. Reset values and initialization
 *                2. Standard CCITT-FALSE reference vector "123456789" -> 0x29B1
 *                3. Soft reset / re-init via CTRL register
 *                4. Multi-byte packet CRC calculation
 *                5. Error detection (1-bit flip mismatch)
 *                6. Full AXI4 protocol checks (AxLEN=0 OKAY, AxLEN>0 SLVERR)
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

`include "crc_defines.vh"

module tb_crc_top;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam ID_WIDTH   = 8;
    localparam STRB_WIDTH = 4;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rst_n = 1'b0;

    always #5 clk = ~clk; // 100 MHz clock

    // AXI4 Interface Signals
    reg  [ID_WIDTH-1:0]   awid = 0;
    reg  [ADDR_WIDTH-1:0] awaddr = 0;
    reg  [7:0]            awlen = 0;
    reg  [2:0]            awsize = 3'b010;
    reg  [1:0]            awburst = 2'b01;
    reg                   awlock = 0;
    reg  [3:0]            awcache = 0;
    reg  [2:0]            awprot = 0;
    reg  [3:0]            awqos = 0;
    reg  [3:0]            awregion = 0;
    reg                   awvalid = 0;
    wire                  awready;

    reg  [DATA_WIDTH-1:0] wdata = 0;
    reg  [STRB_WIDTH-1:0] wstrb = 4'hF;
    reg                   wlast = 1;
    reg                   wvalid = 0;
    wire                  wready;

    wire [ID_WIDTH-1:0]   bid;
    wire [1:0]            bresp;
    wire                  bvalid;
    reg                   bready = 1;

    reg  [ID_WIDTH-1:0]   arid = 0;
    reg  [ADDR_WIDTH-1:0] araddr = 0;
    reg  [7:0]            arlen = 0;
    reg  [2:0]            arsize = 3'b010;
    reg  [1:0]            arburst = 2'b01;
    reg                   arlock = 0;
    reg  [3:0]            arcache = 0;
    reg  [2:0]            arprot = 0;
    reg  [3:0]            arqos = 0;
    reg  [3:0]            arregion = 0;
    reg                   arvalid = 0;
    wire                  arready;

    wire [ID_WIDTH-1:0]   rid;
    wire [DATA_WIDTH-1:0] rdata;
    wire [1:0]            rresp;
    wire                  rlast;
    wire                  rvalid;
    reg                   rready = 1;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    crc_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .rst_n         (rst_n),
        .s_axi_awid    (awid),
        .s_axi_awaddr  (awaddr),
        .s_axi_awlen   (awlen),
        .s_axi_awsize  (awsize),
        .s_axi_awburst (awburst),
        .s_axi_awlock  (awlock),
        .s_axi_awcache (awcache),
        .s_axi_awprot  (awprot),
        .s_axi_awqos   (awqos),
        .s_axi_awregion(awregion),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),
        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (wstrb),
        .s_axi_wlast   (wlast),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),
        .s_axi_bid     (bid),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),
        .s_axi_arid    (arid),
        .s_axi_araddr  (araddr),
        .s_axi_arlen   (arlen),
        .s_axi_arsize  (arsize),
        .s_axi_arburst (arburst),
        .s_axi_arlock  (arlock),
        .s_axi_arcache (arcache),
        .s_axi_arprot  (arprot),
        .s_axi_arqos   (arqos),
        .s_axi_arregion(arregion),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),
        .s_axi_rid     (rid),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rlast   (rlast),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready)
    );

    // Helper task: AXI Write (single beat)
    task axi_write(input [31:0] addr, input [31:0] data, input [7:0] tid, input [7:0] len, output [1:0] resp);
        begin
            @(posedge clk);
            awaddr  <= addr;
            awid    <= tid;
            awlen   <= len;
            awvalid <= 1'b1;
            wdata   <= data;
            wlast   <= 1'b1;
            wvalid  <= 1'b1;

            fork
                begin
                    while (!awready) @(posedge clk);
                    @(posedge clk);
                    awvalid <= 1'b0;
                end
                begin
                    while (!wready) @(posedge clk);
                    @(posedge clk);
                    wvalid <= 1'b0;
                end
            join

            while (!bvalid) @(posedge clk);
            resp = bresp;
            @(posedge clk);
            #1;
        end
    endtask

    // Helper task: AXI Read (single beat)
    task axi_read(input [31:0] addr, input [7:0] tid, input [7:0] len, output [31:0] data, output [1:0] resp);
        begin
            @(posedge clk);
            araddr  <= addr;
            arid    <= tid;
            arlen   <= len;
            arvalid <= 1'b1;

            while (!arready) @(posedge clk);
            @(posedge clk);
            arvalid <= 1'b0;

            while (!rvalid) @(posedge clk);
            data = rdata;
            resp = rresp;
            @(posedge clk);
            #1;
        end
    endtask

    reg [31:0] read_val;
    reg [1:0]  resp_val;
    integer i;
    reg [7:0]  ref_str [0:8];
    reg [15:0] calc_crc1;
    reg [15:0] calc_crc2;

    initial begin
        $display("================================================================");
        $display(" Starting CRC-16-CCITT-FALSE IP AXI4 Verification Testbench ");
        $display(" Base Address: 0x2000_3000 | Poly: 0x1021 | Init: 0xFFFF ");
        $display("================================================================");

        // Reset
        #40;
        rst   <= 1'b0;
        rst_n <= 1'b1;
        #20;

        // TEST 1: Check Reset State
        $display("\n[TEST 1] Verifying reset value of CRC_REG_RESULT...");
        axi_read(`CRC_BASE_ADDR + `CRC_REG_RESULT, 8'h01, 8'd0, read_val, resp_val);
        if (resp_val == 2'b00 && read_val[15:0] == 16'hFFFF) begin
            $display("  -> PASS: CRC result is 0x%04X as expected", read_val[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected 0xFFFF, got 0x%04X (resp=%b)", read_val[15:0], resp_val);
            fail_count = fail_count + 1;
        end

        // TEST 2: Reference Vector "123456789" -> Expected CRC: 0x29B1
        $display("\n[TEST 2] Testing CCITT-FALSE standard vector '123456789' -> Expected: 0x29B1...");
        ref_str[0] = "1"; ref_str[1] = "2"; ref_str[2] = "3";
        ref_str[3] = "4"; ref_str[4] = "5"; ref_str[5] = "6";
        ref_str[6] = "7"; ref_str[7] = "8"; ref_str[8] = "9";

        // Initialize CRC
        axi_write(`CRC_BASE_ADDR + `CRC_REG_CTRL, 32'h1, 8'h02, 8'd0, resp_val);

        for (i = 0; i < 9; i = i + 1) begin
            axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, {24'h0, ref_str[i]}, 8'h10 + i[7:0], 8'd0, resp_val);
        end

        axi_read(`CRC_BASE_ADDR + `CRC_REG_RESULT, 8'h03, 8'd0, read_val, resp_val);
        if (resp_val == 2'b00 && read_val[15:0] == 16'h29B1) begin
            $display("  -> PASS: '123456789' CRC-16 is 0x%04X (MATCH 0x29B1)!", read_val[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected 0x29B1, got 0x%04X", read_val[15:0]);
            fail_count = fail_count + 1;
        end

        // TEST 3: Soft Re-Initialization via CTRL register
        $display("\n[TEST 3] Testing Soft Re-Init via CTRL[0]...");
        axi_write(`CRC_BASE_ADDR + `CRC_REG_CTRL, 32'h0000_0001, 8'h04, 8'd0, resp_val);
        axi_read(`CRC_BASE_ADDR + `CRC_REG_RESULT, 8'h05, 8'd0, read_val, resp_val);
        if (resp_val == 2'b00 && read_val[15:0] == 16'hFFFF) begin
            $display("  -> PASS: CRC re-initialized to 0x%04X", read_val[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected 0xFFFF after re-init, got 0x%04X", read_val[15:0]);
            fail_count = fail_count + 1;
        end

        // TEST 4: Packet CRC Calculation and 1-bit Error Detection
        $display("\n[TEST 4] Packet CRC Calculation & Error Detection...");
        // Packet: Header=0xAA, Type=0x01, Len=0x04, Payload=[0x11, 0x22, 0x33, 0x44]
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'hAA, 8'h20, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h01, 8'h21, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h04, 8'h22, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h11, 8'h23, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h22, 8'h24, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h33, 8'h25, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h44, 8'h26, 8'd0, resp_val);
        axi_read(`CRC_BASE_ADDR + `CRC_REG_RESULT, 8'h27, 8'd0, read_val, resp_val);
        calc_crc1 = read_val[15:0];
        $display("  -> Clean packet CRC: 0x%04X", calc_crc1);

        // Corrupted Packet: Flip 1 bit in payload byte 0x22 -> 0x23
        axi_write(`CRC_BASE_ADDR + `CRC_REG_CTRL, 32'h1, 8'h30, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'hAA, 8'h31, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h01, 8'h32, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h04, 8'h33, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h11, 8'h34, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h23, 8'h35, 8'd0, resp_val); // Bit 0 flipped!
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h33, 8'h36, 8'd0, resp_val);
        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h44, 8'h37, 8'd0, resp_val);
        axi_read(`CRC_BASE_ADDR + `CRC_REG_RESULT, 8'h38, 8'd0, read_val, resp_val);
        calc_crc2 = read_val[15:0];
        $display("  -> Corrupted packet CRC: 0x%04X", calc_crc2);

        if (calc_crc1 != calc_crc2) begin
            $display("  -> PASS: 1-bit error produced distinct CRC (0x%04X != 0x%04X)", calc_crc1, calc_crc2);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: CRC collision on 1-bit error!");
            fail_count = fail_count + 1;
        end

        // TEST 5: AXI Protocol Compliance - Burst Rejection (AxLEN > 0)
        $display("\n[TEST 5] Testing AXI Burst Rejection (AxLEN=1 must return SLVERR)...");
        axi_read(`CRC_BASE_ADDR + `CRC_REG_RESULT, 8'h40, 8'd1, read_val, resp_val); // ARLEN=1
        if (resp_val == 2'b10) begin // SLVERR
            $display("  -> PASS: Multi-beat read burst correctly rejected with SLVERR");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected SLVERR (2'b10), got %b", resp_val);
            fail_count = fail_count + 1;
        end

        axi_write(`CRC_BASE_ADDR + `CRC_REG_DATA, 32'h55, 8'h41, 8'd1, resp_val); // AWLEN=1
        if (resp_val == 2'b10) begin // SLVERR
            $display("  -> PASS: Multi-beat write burst correctly rejected with SLVERR");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected SLVERR (2'b10), got %b", resp_val);
            fail_count = fail_count + 1;
        end

        // Summary
        $display("\n================================================================");
        $display(" CRC-16 Verification Summary: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0)
            $display(" *** ALL CRC-16 TESTS PASSED SUCCESSFULLY! ***\n");
        else
            $display(" *** TESTS FAILED! ***\n");

        #50;
        $finish;
    end

endmodule

`default_nettype wire
