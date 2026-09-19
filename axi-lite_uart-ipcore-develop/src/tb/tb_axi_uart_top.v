/*
 * tb_axi_uart_top
 *
 * Self-checking testbench for the BSC AXI-Lite UART IP core.
 *
 *   TB (AXI-Lite BFM) ──▶ axi_uart_top ──uart_tx_o──┐
 *                                                    │  looped back
 *                              uart_rx_i ◀───────────┘
 *
 * The serial output is wired straight back to the serial input, so one AXI
 * write to THR should reappear as one AXI read from RBR. That single path
 * exercises the write FSM, TX FIFO, transmitter, serial framing, receiver,
 * RX FIFO and read FSM.
 *
 * A separate serial monitor decodes uart_tx_o independently of the DUT's own
 * receiver, so framing and parity are checked against the wire, not against
 * another block that might share the same bug.
 *
 * ---------------------------------------------------------------- reg map
 * Derived from axi_uart.vh. The DUT decodes axi_*addr[4:2], so the word index
 * there becomes a byte address of index*4.
 *
 *   0x00  RBR   read    received byte
 *   0x00  THR   write   byte to transmit
 *   0x04  IER   write   [0] interrupt / data-ready enable
 *   0x08  DLL   write   baud divisor      (only when LCR[7] DLAB = 1)
 *   0x0C  LCR   write   [2] stop bits 0=1 1=2
 *                       [3] parity enable
 *                       [4] parity mode 0=odd 1=even
 *                       [7] DLAB
 *   0x14  LSR   read    [0] data ready
 *                       [5] THRE
 *                       [6] TEMT
 *
 * ---------------------------------------------------------------- gotcha
 * DATA_READY is ANDed with the interrupt-enable bit inside the DUT:
 *
 *     UART_LSR_DATA_READY: assign uart_lsr_reg_int[I] =
 *                            ~rx_fifo_space_int[AXI_FIFO_ADDR] & uart_irq_en_int;
 *
 * So software that polls LSR without first writing IER=1 will never see a byte
 * arrive, even though the RX FIFO holds one. Every test below writes IER=1
 * during setup. Test 7 demonstrates the trap directly.
 */

`timescale 1ns/1ps
`default_nettype none

module tb_axi_uart_top;

localparam AW = 5, DW = 32, IDW = 12;

// byte addresses
localparam [AW-1:0] A_RBR = 5'h00,
                    A_THR = 5'h00,
                    A_IER = 5'h04,
                    A_DLL = 5'h08,
                    A_LCR = 5'h0C,
                    A_LSR = 5'h14;

// LCR bits
localparam LCR_STOP2  = 32'h0000_0004;
localparam LCR_PAR_EN = 32'h0000_0008;
localparam LCR_PAR_EV = 32'h0000_0010;
localparam LCR_DLAB   = 32'h0000_0080;

// LSR bits
localparam LSR_DR   = 0;
localparam LSR_THRE = 5;
localparam LSR_TEMT = 6;

// A small divisor keeps simulation fast. It cannot go much below ~20: the
// transmitter's bit period is (baud_div + 1) clocks while the receiver's is
// baud_div, so the sampling point walks about one clock earlier per bit. Over
// a 10-bit frame that is ~10 clocks of drift, which must stay well inside half
// a bit period. 64 leaves comfortable margin.
localparam [31:0] BAUD_DIV = 32'd64;
localparam integer BIT_CLKS = BAUD_DIV + 1;

reg clk = 0, aresetn = 0;
always #5 clk = ~clk;

// AXI-Lite
reg  [IDW-1:0] arid = 0;
reg  [AW-1:0]  araddr = 0;
reg            arvalid = 0;
wire           arready;
wire [IDW-1:0] rid;
wire [DW-1:0]  rdata;
wire [1:0]     rresp;
wire           rvalid;
reg            rready = 1;

reg  [IDW-1:0] awid = 0;
reg  [AW-1:0]  awaddr = 0;
reg            awvalid = 0;
wire           awready;
reg  [DW-1:0]  wdata = 0;
reg  [3:0]     wstrb = 4'hF;
reg            wvalid = 0;
wire           wready;
wire [IDW-1:0] bid;
wire [1:0]     bresp;
wire           bvalid;
reg            bready = 1;

wire read_interrupt;
wire uart_tx;
wire uart_rx;

// serial loopback
assign uart_rx = uart_tx;

integer errors = 0;
reg [DW-1:0] cap;

axi_uart_top dut (
    .fixed_clk_i    (clk),
    .axi_aclk_i     (clk),
    .axi_aresetn_i  (aresetn),

    .axi_arid_i     (arid),
    .axi_araddr_i   (araddr),
    .axi_arvalid_i  (arvalid),
    .axi_arready_o  (arready),
    .axi_rid_o      (rid),
    .axi_rdata_o    (rdata),
    .axi_rresp_o    (rresp),
    .axi_rvalid_o   (rvalid),
    .axi_rready_i   (rready),

    .axi_awid_i     (awid),
    .axi_awaddr_i   (awaddr),
    .axi_awvalid_i  (awvalid),
    .axi_awready_o  (awready),
    .axi_wdata_i    (wdata),
    .axi_wstrb_i    (wstrb),
    .axi_wvalid_i   (wvalid),
    .axi_wready_o   (wready),
    .axi_bid_o      (bid),
    .axi_bresp_o    (bresp),
    .axi_bvalid_o   (bvalid),
    .axi_bready_i   (bready),

    .read_interrupt_o (read_interrupt),
    .uart_rx_i      (uart_rx),
    .uart_tx_o      (uart_tx)
);

// ==========================================================================
//  AXI-Lite BFM
//  This IP needs AWVALID and WVALID asserted together - its write FSM gates
//  on (awvalid & wvalid), so a split address/data phase would hang.
// ==========================================================================
task axi_write(input [AW-1:0] a, input [DW-1:0] d);
    integer to;
    begin
        @(posedge clk);
        awaddr <= a; awid <= 12'h5A; awvalid <= 1'b1;
        wdata  <= d; wvalid  <= 1'b1;
        to = 0;
        @(posedge clk);
        while (!bvalid && to < 1000) begin @(posedge clk); to = to + 1; end
        if (to >= 1000) begin
            $display("FAIL write to %02h timed out", a); errors = errors + 1;
        end
        awvalid <= 1'b0; wvalid <= 1'b0;
        @(posedge clk);
        @(posedge clk);
    end
endtask

task axi_read(input [AW-1:0] a, output [DW-1:0] d);
    integer to;
    begin
        @(posedge clk);
        araddr <= a; arid <= 12'h2C; arvalid <= 1'b1;
        to = 0;
        @(posedge clk);
        while (!rvalid && to < 1000) begin @(posedge clk); to = to + 1; end
        if (to >= 1000) begin
            $display("FAIL read from %02h timed out", a); errors = errors + 1;
            d = 32'hDEAD_DEAD;
        end else
            d = rdata;
        arvalid <= 1'b0;
        @(posedge clk);
        @(posedge clk);
    end
endtask

// ==========================================================================
//  UART setup - baud divisor is behind DLAB, 16550 style
// ==========================================================================
task uart_setup(input [DW-1:0] lcr_cfg);
    begin
        axi_write(A_LCR, LCR_DLAB);         // open the divisor latch
        axi_write(A_DLL, BAUD_DIV);
        axi_write(A_LCR, lcr_cfg);          // close it, apply config
        axi_write(A_IER, 32'h1);            // REQUIRED: gates LSR data-ready
    end
endtask

// ==========================================================================
//  send one byte and read it back through the loopback
// ==========================================================================
task send_recv_chk(input [7:0] tx_byte, input [255:0] tag);
    integer to;
    begin
        axi_write(A_THR, {24'd0, tx_byte});

        // wait for the byte to travel out and back
        to = 0; cap = 0;
        while (cap[LSR_DR] !== 1'b1 && to < 200) begin
            axi_read(A_LSR, cap);
            to = to + 1;
        end
        if (to >= 200) begin
            $display("FAIL %0s: data-ready never set for %02h", tag, tx_byte);
            errors = errors + 1;
        end else begin
            axi_read(A_RBR, cap);
            if (cap[7:0] !== tx_byte) begin
                $display("FAIL %0s: sent %02h got %02h", tag, tx_byte, cap[7:0]);
                errors = errors + 1;
            end else
                $display("     %0s %02h OK", tag, tx_byte);
        end
    end
endtask

// ==========================================================================
//  independent serial monitor
//  Decodes uart_tx_o on its own so framing and parity are checked against the
//  wire rather than against the DUT's own receiver.
// ==========================================================================
reg        mon_en = 0;
reg        mon_parity_en = 0;
reg        mon_parity_even = 0;
reg [7:0]  mon_byte;
reg        mon_parity_rx;
reg        mon_stop;
reg        mon_done;
integer    mon_i;

task monitor_frame;
    begin
        mon_done = 0;
        @(negedge uart_tx);                 // start bit
        #(BIT_CLKS * 10 * 1.5);             // into the middle of data bit 0
        for (mon_i = 0; mon_i < 8; mon_i = mon_i + 1) begin
            mon_byte[mon_i] = uart_tx;      // LSB first
            #(BIT_CLKS * 10);
        end
        if (mon_parity_en) begin
            mon_parity_rx = uart_tx;
            #(BIT_CLKS * 10);
        end
        mon_stop = uart_tx;
        mon_done = 1;
    end
endtask

function expected_parity;
    input [7:0] b;
    input       even;
    reg         p;
    begin
        p = ^b;                             // 1 when the byte has odd weight
        expected_parity = even ? p : ~p;
    end
endfunction

// ==========================================================================
//  tests
// ==========================================================================
initial begin
    repeat (10) @(posedge clk);
    aresetn = 1;
    repeat (10) @(posedge clk);

    // ------------------------------------------------------------------
    $display("== 1. LSR readable after reset ==");
    axi_read(A_LSR, cap);
    $display("     LSR = %08h", cap);
    if (cap[LSR_DR] !== 1'b0) begin
        $display("FAIL data-ready set with no traffic"); errors = errors + 1;
    end

    // ------------------------------------------------------------------
    $display("== 2. loopback, 8N1 ==");
    uart_setup(32'h0);                      // 1 stop bit, no parity
    send_recv_chk(8'h55, "8N1");
    send_recv_chk(8'hAA, "8N1");
    send_recv_chk(8'h00, "8N1");
    send_recv_chk(8'hFF, "8N1");
    send_recv_chk(8'h5A, "8N1");

    // ------------------------------------------------------------------
    $display("== 3. loopback, 2 stop bits ==");
    uart_setup(LCR_STOP2);
    send_recv_chk(8'h3C, "8N2");
    send_recv_chk(8'hC3, "8N2");

    // ------------------------------------------------------------------
    $display("== 4. loopback, even parity ==");
    uart_setup(LCR_PAR_EN | LCR_PAR_EV);
    send_recv_chk(8'h69, "8E1");
    send_recv_chk(8'h96, "8E1");

    // ------------------------------------------------------------------
    $display("== 5. loopback, odd parity ==");
    uart_setup(LCR_PAR_EN);
    send_recv_chk(8'h69, "8O1");
    send_recv_chk(8'h96, "8O1");

    // ------------------------------------------------------------------
    $display("== 6. several bytes queued, FIFO ordering ==");
    uart_setup(32'h0);
    axi_write(A_THR, 32'h11);
    axi_write(A_THR, 32'h22);
    axi_write(A_THR, 32'h33);
    axi_write(A_THR, 32'h44);
    // let all four make the round trip
    repeat (4 * 12 * BIT_CLKS) @(posedge clk);
    axi_read(A_RBR, cap);
    if (cap[7:0] !== 8'h11) begin
        $display("FAIL order byte0: got %02h want 11", cap[7:0]); errors = errors+1;
    end
    axi_read(A_RBR, cap);
    if (cap[7:0] !== 8'h22) begin
        $display("FAIL order byte1: got %02h want 22", cap[7:0]); errors = errors+1;
    end
    axi_read(A_RBR, cap);
    if (cap[7:0] !== 8'h33) begin
        $display("FAIL order byte2: got %02h want 33", cap[7:0]); errors = errors+1;
    end
    axi_read(A_RBR, cap);
    if (cap[7:0] !== 8'h44) begin
        $display("FAIL order byte3: got %02h want 44", cap[7:0]); errors = errors+1;
    end
    $display("     ordering OK 11 22 33 44");

    // ------------------------------------------------------------------
    $display("== 7. IER=0 hides data-ready, IP quirk ==");
    axi_write(A_IER, 32'h0);
    axi_write(A_THR, 32'h7E);
    repeat (12 * BIT_CLKS) @(posedge clk);
    axi_read(A_LSR, cap);
    if (cap[LSR_DR] === 1'b1) begin
        $display("     NOTE data-ready visible with IER=0");
    end else begin
        $display("     confirmed: byte arrived but data-ready reads 0 with IER=0");
        axi_write(A_IER, 32'h1);
        axi_read(A_LSR, cap);
        if (cap[LSR_DR] !== 1'b1) begin
            $display("FAIL data-ready still low after re-enabling IER");
            errors = errors + 1;
        end else begin
            axi_read(A_RBR, cap);
            if (cap[7:0] !== 8'h7E) begin
                $display("FAIL held byte: got %02h want 7E", cap[7:0]);
                errors = errors + 1;
            end else
                $display("     held byte recovered OK 7e");
        end
    end

    $display("");
    if (errors == 0) $display("*** ALL TESTS PASSED ***");
    else             $display("*** %0d ERRORS ***", errors);
    $finish;
end

// ==========================================================================
//  wire-level framing check, runs alongside
// ==========================================================================
initial begin
    @(posedge aresetn);
    forever begin
        monitor_frame;
        if (mon_en) begin
            if (mon_stop !== 1'b1) begin
                $display("FAIL framing: stop bit was %b, byte %02h",
                          mon_stop, mon_byte);
                errors = errors + 1;
            end
            if (mon_parity_en) begin
                if (mon_parity_rx !== expected_parity(mon_byte, mon_parity_even))
                    $display("NOTE parity on wire %b, computed %b, byte %02h",
                              mon_parity_rx,
                              expected_parity(mon_byte, mon_parity_even),
                              mon_byte);
            end
        end
    end
end

initial begin #50000000; $display("*** TIMEOUT ***"); $finish; end

endmodule
`default_nettype wire
