class spi_sequencer extends uvm_sequencer #(spi_item);
`uvm_component_utils(spi_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
