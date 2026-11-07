class spi_env extends uvm_env;
spi_agent agent; spi_scoreboard sb;
`uvm_component_utils(spi_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=spi_agent::type_id::create("agent",this); sb=spi_scoreboard::type_id::create("sb",this); endfunction
endclass
