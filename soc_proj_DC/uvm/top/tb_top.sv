// tb_top.sv - SoC UVM top: soc_top + one interface per external IP
//   Program for VeeR : +BOOT_HEX=sw/build/<c_test>.hex
//   UVM test         : +UVM_TESTNAME=<test>
// (The tb_top.sv files inside *_uvm_tb/ are the generator's standalone tops; not used here.)
`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  import soc_env_pkg::*;

  // ---- clock and reset ----
  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;                       // 100 MHz
  initial begin
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---- one interface per external IP ----
  uart_if uart_vif ();
  spi_if  spi_vif  ();
  gpio_if gpio_vif ();

  assign uart_vif.clk = clk;  assign uart_vif.rst_n = rst_n;
  assign spi_vif.clk  = clk;  assign spi_vif.rst_n  = rst_n;
  assign gpio_vif.clk = clk;  assign gpio_vif.rst_n = rst_n;

  // ---- DUT: soc_top pins wired to the interfaces ----
  soc_top dut (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .uart_rx_i        (uart_vif.uart_rx_i),   // UART VIP driver  -> SoC
    .uart_tx_o        (uart_vif.uart_tx_o),   // SoC -> UART VIP monitor
    .spi_sclk_o       (spi_vif.spi_sclk_o),
    .spi_mosi_o       (spi_vif.spi_mosi_o),
    .spi_cs_no        (spi_vif.spi_cs_no),
    .spi_miso_i       (spi_vif.spi_miso_i),   // SPI slave VIP -> SoC
    .gpio_out_o       (gpio_vif.gpio_out_o),  // SoC -> GPIO VIP monitor
    // test-bench bus master port of soc_top: unused, CPU runs the program
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

  // ---- hand the interfaces to the VIPs and start UVM ----
  initial begin
    uvm_config_db#(virtual uart_if)::set(null, "*", "uart_vif", uart_vif);
    uvm_config_db#(virtual spi_if) ::set(null, "*", "spi_vif",  spi_vif);
    uvm_config_db#(virtual gpio_if)::set(null, "*", "gpio_vif", gpio_vif);
    run_test("soc_uart_test");
  end

  // ---- waveforms: +define+FSDB (Verdi) or +VCD ----
`ifdef FSDB
  initial begin
    $fsdbDumpfile("sim/uvm/out/tb_top.fsdb");
    $fsdbDumpvars(0, tb_top, "+all");
  end
`endif
  initial if ($test$plusargs("VCD")) begin
    $dumpfile("sim/uvm/out/tb_top.vcd");
    $dumpvars(0);
  end
endmodule
