// tb_soc.sv - SoC-level testbench for C tests
//   Runs the program given by +BOOT_HEX=<file> on VeeR EL2 inside soc_top.
//   The UART PC model ends the run when the program prints PASS or FAIL.
//   +TIMEOUT=<cycles> overrides the default timeout.
`timescale 1ns/1ps
module tb_soc;
  // Must match SIM_UART_DIV in sw/Makefile (bit time = divisor + 1 clocks)
  localparam int UART_DIV = 63;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic uart_tx, uart_rx;
  logic spi_mosi, spi_sclk, spi_cs_n;
  logic [7:0] gpio_out;

  always #5 clk = ~clk;   // 100 MHz

  soc_top dut (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .uart_rx_i        (uart_rx),
    .uart_tx_o        (uart_tx),
    .spi_mosi_o       (spi_mosi),
    .spi_miso_i       (spi_mosi),   // loopback until an SPI slave model is added
    .spi_sclk_o       (spi_sclk),
    .spi_cs_no        (spi_cs_n),
    .gpio_out_o       (gpio_out),
    // CPU runs the program: test-bench bus master port is unused
    .tb_bypass_cpu    (1'b0),
    .tb_s_axi_awid    ('0), .tb_s_axi_awaddr ('0), .tb_s_axi_awlen ('0),
    .tb_s_axi_awsize  ('0), .tb_s_axi_awburst('0), .tb_s_axi_awlock('0),
    .tb_s_axi_awcache ('0), .tb_s_axi_awprot ('0), .tb_s_axi_awqos ('0),
    .tb_s_axi_awvalid (1'b0), .tb_s_axi_awready(),
    .tb_s_axi_wdata   ('0), .tb_s_axi_wstrb  ('0), .tb_s_axi_wlast (1'b0),
    .tb_s_axi_wvalid  (1'b0), .tb_s_axi_wready (),
    .tb_s_axi_bid     (), .tb_s_axi_bresp  (), .tb_s_axi_bvalid (),
    .tb_s_axi_bready  (1'b1),
    .tb_s_axi_arid    ('0), .tb_s_axi_araddr ('0), .tb_s_axi_arlen ('0),
    .tb_s_axi_arsize  ('0), .tb_s_axi_arburst('0), .tb_s_axi_arlock('0),
    .tb_s_axi_arcache ('0), .tb_s_axi_arprot ('0), .tb_s_axi_arqos ('0),
    .tb_s_axi_arvalid (1'b0), .tb_s_axi_arready(),
    .tb_s_axi_rid     (), .tb_s_axi_rdata  (), .tb_s_axi_rresp  (),
    .tb_s_axi_rlast   (), .tb_s_axi_rvalid (), .tb_s_axi_rready (1'b1)
  );

  uart_pc_model #(.CLKS_PER_BIT(UART_DIV + 1)) pc (
    .clk    (clk),
    .soc_tx (uart_tx),
    .soc_rx (uart_rx)
  );

  // Reset
  initial begin
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
    $display("[%0t ns] Reset released, VeeR EL2 boots from 0x0000_0000", $time);
  end

  // Waveforms
  //   FSDB for Verdi : compile with +define+FSDB (run_vcs.sh does this when WAVES=1)
  //   VCD (any tool) : run with +VCD  -> sim/soc/out/tb_soc.vcd
`ifdef FSDB
  initial begin
    $fsdbDumpfile("sim/soc/out/tb_soc.fsdb");
    $fsdbDumpvars(0, tb_soc, "+all");
  end
`endif
  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("sim/soc/out/tb_soc.vcd");
      $dumpvars(0);
    end
  end

  // Timeout
  initial begin
    int unsigned timeout_cycles = 2_000_000;
    void'($value$plusargs("TIMEOUT=%d", timeout_cycles));
    repeat (timeout_cycles) @(posedge clk);
    $display("[%0t ns] TIMEOUT after %0d cycles: no PASS/FAIL from the C test", $time, timeout_cycles);
    $finish;
  end

  // Optional bus trace of CPU accesses to the peripherals: +BUSTRACE
  bit bustrace;
  initial bustrace = $test$plusargs("BUSTRACE");
  always @(posedge clk) if (bustrace && rst_n) begin
    if (dut.s00_awvalid && dut.s00_awready)
      $display("[%0t ns] AW addr=%08h", $time, dut.s00_awaddr);
    if (dut.s00_wvalid && dut.s00_wready)
      $display("[%0t ns] W  data=%08h strb=%b", $time, dut.s00_wdata, dut.s00_wstrb);
    if (dut.s00_arvalid && dut.s00_arready && dut.s00_araddr >= 32'h1000_0000)
      $display("[%0t ns] AR addr=%08h", $time, dut.s00_araddr);
  end
endmodule
