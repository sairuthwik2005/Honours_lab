// soc_tests.sv - SoC-level UVM tests. Each runs with a C program loaded by +BOOT_HEX.
//
//   UVM test            C program   checks
//   soc_uart_test       test_uart   "UART OK" -> VIP sends "HI" -> "RX 48 49" -> "PASS"
//   soc_uart_err_test   test_uart   VIP flips a bit (0x49 -> 0x4B) -> C must print "FAIL"
//   soc_spi_test        test_spi    SPI write frame MOSI = 48 49 40 87, readback MISO same -> "PASS"
//   soc_spi_err_test    test_spi    SPI VIP flips a MISO bit -> C must print "FAIL"

class soc_base_test extends uvm_test;
  `uvm_component_utils(soc_base_test)

  soc_env      env;
  int unsigned timeout_ns = 5_000_000;   // 5 ms
  int unsigned uart_cpb   = 64;          // UART clocks per bit = divisor + 1

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("UART_CPB=%d", uart_cpb));
    void'($value$plusargs("TIMEOUT_NS=%d", timeout_ns));
    uvm_config_db#(int unsigned)::set(this, "env.uart_agt*", "uart_clks_per_bit", uart_cpb);
    configure();
    env = soc_env::type_id::create("env", this);
    uvm_top.set_timeout(timeout_ns * 1ns, 0);
  endfunction

  virtual function void configure();   // derived tests set extra knobs here
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    $display("============================================");
    if (errs == 0) $display(" *** UVM TEST %s PASSED ***", get_type_name());
    else           $display(" *** UVM TEST %s FAILED (%0d errors) ***", get_type_name(), errs);
    $display("============================================");
  endfunction
endclass


class soc_uart_test extends soc_base_test;
  `uvm_component_utils(soc_uart_test)

  bit [7:0] payload[$]    = '{8'h48, 8'h49};   // "HI"
  int       err_index     = -1;
  string    expect_echo   = "RX 48 49";
  string    expect_result = "PASS";

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    uart_send_bytes_seq seq;
    string result;
    phase.raise_objection(this);

    `uvm_info("TEST", "waiting for the C program to print \"UART OK\"", UVM_LOW)
    env.scb.wait_line("UART OK");

    seq = uart_send_bytes_seq::type_id::create("seq");
    seq.bytes     = payload;
    seq.err_index = err_index;
    seq.err_bit   = 1;
    `uvm_info("TEST", "UART VIP sends the payload to the SoC", UVM_LOW)
    seq.start(env.uart_agt.seqr);

    env.scb.wait_any_line('{"PASS", "FAIL"}, result);
    if (!env.scb.has_line(expect_echo))
      `uvm_error("TEST", $sformatf("expected the SoC to print \"%s\"", expect_echo))
    if (result != expect_result)
      `uvm_error("TEST", $sformatf("C program printed \"%s\", expected \"%s\"", result, expect_result))
    else
      `uvm_info("TEST", $sformatf("C program printed \"%s\" as expected", result), UVM_LOW)

    phase.drop_objection(this);
  endtask
endclass


class soc_uart_err_test extends soc_uart_test;
  `uvm_component_utils(soc_uart_err_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    err_index     = 1;              // 2nd byte, bit 1: 0x49 -> 0x4B
    expect_echo   = "RX 48 4B";
    expect_result = "FAIL";
  endfunction
endclass


class soc_spi_test extends soc_base_test;
  `uvm_component_utils(soc_spi_test)

  bit [7:0] payload[$]    = '{8'h48, 8'h49, 8'h40, 8'h87};
  bit [7:0] expect_rd[$]  = '{8'h48, 8'h49, 8'h40, 8'h87};
  string    expect_result = "PASS";

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string rd_line();
    string s = "SPI RD";
    foreach (expect_rd[i]) s = {s, $sformatf(" %02H", expect_rd[i])};
    return s;
  endfunction

  task run_phase(uvm_phase phase);
    string result;
    phase.raise_objection(this);

    env.scb.wait_line("SPI TEST");
    env.scb.wait_any_line('{"PASS", "FAIL"}, result);

    if (env.scb.spi_frames.size() < 2) begin
      `uvm_error("TEST", $sformatf("expected 2 SPI frames, saw %0d", env.scb.spi_frames.size()))
    end else begin
      spi_item wr = env.scb.spi_frames[0];
      spi_item rd = env.scb.spi_frames[1];
      if (wr.mosi_bytes != payload)
        `uvm_error("TEST", {"WRITE frame MOSI wrong: ", spi_item::bytes2str(wr.mosi_bytes)})
      else
        `uvm_info("TEST", {"WRITE frame MOSI ok: ", spi_item::bytes2str(wr.mosi_bytes)}, UVM_LOW)
      if (rd.miso_bytes != expect_rd)
        `uvm_error("TEST", {"READBACK frame MISO wrong: ", spi_item::bytes2str(rd.miso_bytes)})
      else
        `uvm_info("TEST", {"READBACK frame MISO ok: ", spi_item::bytes2str(rd.miso_bytes)}, UVM_LOW)
    end

    if (!env.scb.has_line(rd_line()))
      `uvm_error("TEST", $sformatf("expected the SoC to print \"%s\"", rd_line()))
    if (result != expect_result)
      `uvm_error("TEST", $sformatf("C program printed \"%s\", expected \"%s\"", result, expect_result))
    else
      `uvm_info("TEST", $sformatf("C program printed \"%s\" as expected", result), UVM_LOW)

    phase.drop_objection(this);
  endtask
endclass


class soc_spi_err_test extends soc_spi_test;
  `uvm_component_utils(soc_spi_err_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    expect_rd     = '{8'h48, 8'h48, 8'h40, 8'h87};   // byte 1 bit 0 flipped on MISO
    expect_result = "FAIL";
  endfunction
  function void configure();
    uvm_config_db#(int unsigned)::set(this, "env.spi_agt*", "spi_inject_miso_err", 1);
    uvm_config_db#(int unsigned)::set(this, "env.spi_agt*", "spi_err_frame", 1);   // readback frame
    uvm_config_db#(int unsigned)::set(this, "env.spi_agt*", "spi_err_byte",  1);
    uvm_config_db#(int unsigned)::set(this, "env.spi_agt*", "spi_err_bit",   0);
  endfunction
endclass


// ---------------------------------------------------------------------------
// soc_gpio_test - pairs with sw/tests/test_gpio.c
//   The GPIO VIP (passive) records every change on gpio_out_o. The C program
//   writes 55, AA, SET 05 (AF), CLEAR A0 (0F), 01; the pins must show exactly
//   that sequence and the C program must print "GPIO 55 AA AF 0F 01" + "PASS".
// ---------------------------------------------------------------------------
class soc_gpio_test extends soc_base_test;
  `uvm_component_utils(soc_gpio_test)

  bit [7:0] expect_pins[$] = '{8'h55, 8'hAA, 8'hAF, 8'h0F, 8'h01};

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    string result, pins;
    phase.raise_objection(this);

    env.scb.wait_line("GPIO TEST");
    env.scb.wait_any_line('{"PASS", "FAIL"}, result);

    // ---- what the GPIO VIP saw on the pins ----
    foreach (env.scb.gpio_values[i]) pins = {pins, $sformatf("%02h ", env.scb.gpio_values[i])};
    if (env.scb.gpio_values != expect_pins)
      `uvm_error("TEST", {"gpio_out_o sequence wrong: ", pins})
    else
      `uvm_info("TEST", {"gpio_out_o sequence ok: ", pins}, UVM_LOW)

    // ---- what the C program reported ----
    if (!env.scb.has_line("GPIO 55 AA AF 0F 01"))
      `uvm_error("TEST", "expected the SoC to print \"GPIO 55 AA AF 0F 01\"")
    if (result != "PASS")
      `uvm_error("TEST", $sformatf("C program printed \"%s\", expected \"PASS\"", result))
    else
      `uvm_info("TEST", "C program printed \"PASS\" as expected", UVM_LOW)

    phase.drop_objection(this);
  endtask
endclass
