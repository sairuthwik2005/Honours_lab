// soc_env.sv - SoC environment: the three generated VIP agents + scoreboard
class soc_env extends uvm_env;
  `uvm_component_utils(soc_env)

  uart_agent      uart_agt;   // active : acts as the PC
  spi_agent       spi_agt;    // active : acts as the SPI slave
  gpio_agent      gpio_agt;   // passive: watches the LEDs
  soc_scoreboard  scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "gpio_agt", "is_active", UVM_PASSIVE);
    uart_agt = uart_agent::type_id::create("uart_agt", this);
    spi_agt  = spi_agent ::type_id::create("spi_agt",  this);
    gpio_agt = gpio_agent::type_id::create("gpio_agt", this);
    scb      = soc_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    uart_agt.ap.connect(scb.uart_imp);
    spi_agt.ap .connect(scb.spi_imp);
    gpio_agt.ap.connect(scb.gpio_imp);
  endfunction
endclass
