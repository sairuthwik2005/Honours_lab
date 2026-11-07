// soc_env_pkg.sv - SoC environment and tests (uses the three generated VIP packages)
package soc_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;
  import spi_pkg::*;
  import gpio_pkg::*;

  `include "soc_scoreboard.sv"
  `include "soc_env.sv"
  `include "soc_tests.sv"
endpackage
