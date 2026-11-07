class spi_test extends uvm_test;
spi_env env;
`uvm_component_utils(spi_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=spi_env::type_id::create("env",this); endfunction
endclass
