// uart_pc_model.sv - plays the PC on the other end of the SoC UART
//  * Receives what the SoC sends on uart_tx and prints it line by line.
//  * After the SoC prints "UART OK" it sends 'H' 'I' (0x48 0x49) on uart_rx.
//  * Ends the simulation when the SoC prints "PASS" or "FAIL".
// CLKS_PER_BIT must equal (UART divisor + 1), the bit time of IPs/UART_IP.
`timescale 1ns/1ps
module uart_pc_model #(
  parameter int CLKS_PER_BIT = 64
)(
  input  logic clk,
  input  logic soc_tx,     // SoC uart_tx_o
  output logic soc_rx      // SoC uart_rx_i
);
  string line = "";
  bit    hello_seen = 0;
  int    pass_count = 0;
  int    fail_count = 0;

  initial soc_rx = 1'b1;   // line idles high

  // ---------- receive one byte from the SoC (8N1, LSB first) ----------
  task automatic rx_byte(output logic [7:0] b);
    @(negedge soc_tx);                          // start bit
    repeat (CLKS_PER_BIT/2) @(posedge clk);     // middle of start bit
    for (int i = 0; i < 8; i++) begin
      repeat (CLKS_PER_BIT) @(posedge clk);
      b[i] = soc_tx;
    end
    repeat (CLKS_PER_BIT) @(posedge clk);       // stop bit
  endtask

  initial begin
    logic [7:0] b;
    forever begin
      rx_byte(b);
      if (b == 8'h0A) begin
        $display("[%0t ns] UART RX from SoC: \"%s\"", $time, line);
        if (line == "UART OK") hello_seen = 1;
        if (line == "PASS") begin
          $display("============================================");
          $display(" *** UART C TEST PASSED ***");
          $display("============================================");
          $finish;
        end
        if (line == "FAIL") begin
          $display("============================================");
          $display(" *** UART C TEST FAILED ***");
          $display("============================================");
          $finish;
        end
        line = "";
      end else begin
        line = {line, string'(b)};
      end
    end
  end

  // ---------- send one byte into the SoC ----------
  task automatic tx_byte(input logic [7:0] b);
    soc_rx = 1'b0; repeat (CLKS_PER_BIT) @(posedge clk);       // start
    for (int i = 0; i < 8; i++) begin
      soc_rx = b[i]; repeat (CLKS_PER_BIT) @(posedge clk);     // data
    end
    soc_rx = 1'b1; repeat (CLKS_PER_BIT) @(posedge clk);       // stop
  endtask

  initial begin
    wait (hello_seen);
    repeat (10*CLKS_PER_BIT) @(posedge clk);
    $display("[%0t ns] PC model sends 0x48 0x49 (\"HI\")", $time);
    tx_byte(8'h48);
    tx_byte(8'h49);
  end
endmodule
