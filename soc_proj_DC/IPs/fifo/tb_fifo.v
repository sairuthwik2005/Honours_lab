/*
 * ============================================================================
 * File: tb_fifo.v
 * Project: RISC-V Reliable Digital Communication SoC
 * Description: Self-Checking Testbench for 16x8 TX Streaming FIFO Core
 *              Tests:
 *                1. Reset values (empty=1, full=0, level=0)
 *                2. 16-byte write to fill FIFO (level=16, full=1)
 *                3. Illegal write on full -> overflow flag latched
 *                4. Synchronous reads with fifo_data_valid verification
 *                5. Illegal read on empty -> underflow flag latched
 *                6. Clear status & clear contents via CTRL register
 *                7. Full AXI4 burst rejection check (AxLEN > 0 returns SLVERR)
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

`include "fifo_defines.vh"

module tb_fifo;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam ID_WIDTH   = 8;
    localparam STRB_WIDTH = 4;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    // AXI4 Interface
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

    // Streaming Read Port (SPI side)
    reg                   fifo_rd_en = 0;
    wire [7:0]            fifo_rd_data;
    wire                  fifo_data_valid;
    wire                  fifo_empty;
    wire                  fifo_full;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    fifo_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .rst_n           (rst_n),
        .s_axi_awid      (awid),
        .s_axi_awaddr    (awaddr),
        .s_axi_awlen     (awlen),
        .s_axi_awsize    (awsize),
        .s_axi_awburst   (awburst),
        .s_axi_awlock    (awlock),
        .s_axi_awcache   (awcache),
        .s_axi_awprot    (awprot),
        .s_axi_awqos     (awqos),
        .s_axi_awregion  (awregion),
        .s_axi_awvalid   (awvalid),
        .s_axi_awready   (awready),
        .s_axi_wdata     (wdata),
        .s_axi_wstrb     (wstrb),
        .s_axi_wlast     (wlast),
        .s_axi_wvalid    (wvalid),
        .s_axi_wready    (wready),
        .s_axi_bid       (bid),
        .s_axi_bresp     (bresp),
        .s_axi_bvalid    (bvalid),
        .s_axi_bready    (bready),
        .s_axi_arid      (arid),
        .s_axi_araddr    (araddr),
        .s_axi_arlen     (arlen),
        .s_axi_arsize    (arsize),
        .s_axi_arburst   (arburst),
        .s_axi_arlock    (arlock),
        .s_axi_arcache   (arcache),
        .s_axi_arprot    (arprot),
        .s_axi_arqos     (arqos),
        .s_axi_arregion  (arregion),
        .s_axi_arvalid   (arvalid),
        .s_axi_arready   (arready),
        .s_axi_rid       (rid),
        .s_axi_rdata     (rdata),
        .s_axi_rresp     (rresp),
        .s_axi_rlast     (rlast),
        .s_axi_rvalid    (rvalid),
        .s_axi_rready    (rready),
        .fifo_rd_en      (fifo_rd_en),
        .fifo_rd_data    (fifo_rd_data),
        .fifo_data_valid (fifo_data_valid),
        .fifo_empty      (fifo_empty),
        .fifo_full       (fifo_full)
    );

    // AXI Write Task
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

    // AXI Read Task
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

    reg [31:0] r_val;
    reg [1:0]  r_resp;
    integer i;

    initial begin
        $display("================================================================");
        $display(" Starting 16x8 TX Streaming FIFO AXI4 Verification Testbench ");
        $display(" Base Address: 0x2000_4000 | Depth: 16 | Width: 8 bits ");
        $display("================================================================");

        // Reset sequence
        #40;
        rst   <= 1'b0;
        rst_n <= 1'b1;
        #20;

        // TEST 1: Check Reset State
        $display("\n[TEST 1] Verifying reset status (empty=1, full=0, level=0)...");
        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_STATUS, 8'h01, 8'd0, r_val, r_resp);
        if (r_resp == 2'b00 && r_val[`FIFO_STATUS_EMPTY_BIT] == 1'b1 && r_val[`FIFO_STATUS_FULL_BIT] == 1'b0) begin
            $display("  -> PASS: STATUS is empty and not full");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: STATUS expected empty=1, full=0, got 0x%08X", r_val);
            fail_count = fail_count + 1;
        end

        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_LEVEL, 8'h02, 8'd0, r_val, r_resp);
        if (r_resp == 2'b00 && r_val[4:0] == 5'd0) begin
            $display("  -> PASS: Initial occupancy level = 0");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Initial level expected 0, got %0d", r_val[4:0]);
            fail_count = fail_count + 1;
        end

        // TEST 2: Write 16 Bytes to Fill FIFO
        $display("\n[TEST 2] Writing 16 bytes (0x10 to 0x1F) to fill FIFO...");
        for (i = 0; i < 16; i = i + 1) begin
            axi_write(`FIFO_BASE_ADDR + `FIFO_REG_DATA, 32'h10 + i, 8'h10 + i[7:0], 8'd0, r_resp);
        end

        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_STATUS, 8'h03, 8'd0, r_val, r_resp);
        if (r_val[`FIFO_STATUS_FULL_BIT] == 1'b1 && r_val[`FIFO_STATUS_EMPTY_BIT] == 1'b0) begin
            $display("  -> PASS: FIFO is FULL (full=1, empty=0)");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected full=1, got 0x%08X", r_val);
            fail_count = fail_count + 1;
        end

        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_LEVEL, 8'h04, 8'd0, r_val, r_resp);
        if (r_val[4:0] == 5'd16) begin
            $display("  -> PASS: Occupancy level is 16");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Level expected 16, got %0d", r_val[4:0]);
            fail_count = fail_count + 1;
        end

        // TEST 3: Illegal Write on Full FIFO (Overflow)
        $display("\n[TEST 3] Testing overflow detection (write 17th byte)...");
        axi_write(`FIFO_BASE_ADDR + `FIFO_REG_DATA, 32'hFF, 8'h20, 8'd0, r_resp);
        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_STATUS, 8'h21, 8'd0, r_val, r_resp);
        if (r_val[`FIFO_STATUS_OVERFLOW_BIT] == 1'b1) begin
            $display("  -> PASS: Sticky overflow flag latched correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Overflow flag not set after write on full!");
            fail_count = fail_count + 1;
        end

        // TEST 4: Synchronous Read of 16 Bytes with Data Valid Check
        $display("\n[TEST 4] Synchronous Read of 16 bytes via direct SPI streaming port...");
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            fifo_rd_en <= 1'b1;
            @(posedge clk);
            fifo_rd_en <= 1'b0;
            #1; // Allow NBA outputs to settle

            // Wait for synchronous valid
            if (fifo_data_valid && (fifo_rd_data == (8'h10 + i[7:0]))) begin
                // Match
            end else begin
                $display("  -> MISMATCH at byte %0d: valid=%b, data=0x%02X (expected 0x%02X)",
                         i, fifo_data_valid, fifo_rd_data, (8'h10 + i[7:0]));
                fail_count = fail_count + 1;
            end
        end
        if (fail_count == 0) begin
            $display("  -> PASS: All 16 bytes drained in exact FIFO order with valid pulse!");
            pass_count = pass_count + 1;
        end

        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_STATUS, 8'h30, 8'd0, r_val, r_resp);
        if (r_val[`FIFO_STATUS_EMPTY_BIT] == 1'b1 && r_val[`FIFO_STATUS_FULL_BIT] == 1'b0) begin
            $display("  -> PASS: FIFO is empty after draining");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected empty=1, got 0x%08X", r_val);
            fail_count = fail_count + 1;
        end

        // TEST 5: Illegal Read on Empty FIFO (Underflow)
        $display("\n[TEST 5] Testing underflow detection (read on empty FIFO)...");
        @(posedge clk);
        fifo_rd_en <= 1'b1;
        @(posedge clk);
        fifo_rd_en <= 1'b0;
        @(posedge clk);

        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_STATUS, 8'h31, 8'd0, r_val, r_resp);
        if (r_val[`FIFO_STATUS_UNDERFLOW_BIT] == 1'b1) begin
            $display("  -> PASS: Sticky underflow flag latched correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Underflow flag not set after read on empty!");
            fail_count = fail_count + 1;
        end

        // TEST 6: Clear Status & Re-check
        $display("\n[TEST 6] Clearing status flags via CTRL[1]...");
        axi_write(`FIFO_BASE_ADDR + `FIFO_REG_CTRL, 32'h0000_0002, 8'h32, 8'd0, r_resp);
        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_STATUS, 8'h33, 8'd0, r_val, r_resp);
        if (r_val[`FIFO_STATUS_OVERFLOW_BIT] == 1'b0 && r_val[`FIFO_STATUS_UNDERFLOW_BIT] == 1'b0) begin
            $display("  -> PASS: Overflow and underflow flags successfully cleared");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Flags not cleared (STATUS=0x%08X)", r_val);
            fail_count = fail_count + 1;
        end

        // TEST 7: AXI Protocol Compliance - Burst Rejection (AxLEN > 0)
        $display("\n[TEST 7] Testing AXI burst rejection (AxLEN=1 must return SLVERR)...");
        axi_read(`FIFO_BASE_ADDR + `FIFO_REG_LEVEL, 8'h40, 8'd1, r_val, r_resp);
        if (r_resp == 2'b10) begin
            $display("  -> PASS: Multi-beat read burst correctly rejected with SLVERR");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected SLVERR (2'b10), got %b", r_resp);
            fail_count = fail_count + 1;
        end

        axi_write(`FIFO_BASE_ADDR + `FIFO_REG_DATA, 32'hAA, 8'h41, 8'd1, r_resp);
        if (r_resp == 2'b10) begin
            $display("  -> PASS: Multi-beat write burst correctly rejected with SLVERR");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: Expected SLVERR (2'b10), got %b", r_resp);
            fail_count = fail_count + 1;
        end

        // Summary
        $display("\n================================================================");
        $display(" TX FIFO Verification Summary: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0)
            $display(" *** ALL TX FIFO TESTS PASSED SUCCESSFULLY! ***\n");
        else
            $display(" *** TESTS FAILED! ***\n");

        #50;
        $finish;
    end

endmodule

`default_nettype wire
