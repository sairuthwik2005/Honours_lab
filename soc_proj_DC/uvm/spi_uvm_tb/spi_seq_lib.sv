// spi_seq_lib.sv - SPI slave sequences (added; not produced by the generator)
//   The slave driver runs on its own; use this only to force MISO data for the next frame.
class spi_set_response_seq extends uvm_sequence #(spi_item);
  `uvm_object_utils(spi_set_response_seq)
  bit [7:0] bytes[$];
  function new(string name = "spi_set_response_seq"); super.new(name); endfunction
  task body();
    req = spi_item::type_id::create("req");
    start_item(req);
    req.resp_bytes = new[bytes.size()];
    foreach (bytes[i]) req.resp_bytes[i] = bytes[i];
    finish_item(req);
  endtask
endclass
