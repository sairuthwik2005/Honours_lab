// soc_scoreboard.sv - collects what the three VIPs see
//   UART : rebuilds the text lines printed by the C program (SoC -> PC)
//   SPI  : records every frame (write / readback)
//   GPIO : records LED changes
`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_spi)
`uvm_analysis_imp_decl(_gpio)

class soc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soc_scoreboard)

  uvm_analysis_imp_uart #(uart_item, soc_scoreboard) uart_imp;
  uvm_analysis_imp_spi  #(spi_item,  soc_scoreboard) spi_imp;
  uvm_analysis_imp_gpio #(gpio_item, soc_scoreboard) gpio_imp;

  string     cur_line;
  string     lines[$];          // complete lines printed by the SoC
  bit [7:0]  pc_sent[$];        // bytes the UART VIP sent to the SoC
  spi_item   spi_frames[$];
  bit [7:0]  gpio_values[$];
  event      line_added;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    uart_imp = new("uart_imp", this);
    spi_imp  = new("spi_imp",  this);
    gpio_imp = new("gpio_imp", this);
  endfunction

  function void write_uart(uart_item tr);
    if (tr.dir == UART_PC_TO_SOC) begin
      pc_sent.push_back(tr.data);
      return;
    end
    if (tr.data == 8'h0A) begin
      lines.push_back(cur_line);
      `uvm_info("SCB", $sformatf("SoC printed: \"%s\"", cur_line), UVM_LOW)
      cur_line = "";
      -> line_added;
    end else if (tr.data != 8'h0D) begin
      cur_line = {cur_line, string'(tr.data)};
    end
  endfunction

  function void write_spi(spi_item tr);
    spi_frames.push_back(tr);
    `uvm_info("SCB", {"SPI ", tr.convert2string()}, UVM_LOW)
  endfunction

  function void write_gpio(gpio_item tr);
    gpio_values.push_back(tr.gpio_out_o);
    `uvm_info("SCB", $sformatf("GPIO = %02h", tr.gpio_out_o), UVM_LOW)
  endfunction

  function bit has_line(string s);
    foreach (lines[i]) if (lines[i] == s) return 1;
    return 0;
  endfunction

  task wait_line(string s);
    forever begin
      if (has_line(s)) return;
      @(line_added);
    end
  endtask

  task wait_any_line(string choices[$], output string seen);
    forever begin
      foreach (choices[i]) if (has_line(choices[i])) begin seen = choices[i]; return; end
      @(line_added);
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("Summary: %0d UART lines, %0d bytes PC->SoC, %0d SPI frames, %0d GPIO changes",
                               lines.size(), pc_sent.size(), spi_frames.size(), gpio_values.size()), UVM_LOW)
  endfunction
endclass
