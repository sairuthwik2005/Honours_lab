// uart_seq_lib.sv - UART sequences (added; not produced by the generator)

class uart_base_seq extends uvm_sequence #(uart_item);
  `uvm_object_utils(uart_base_seq)
  function new(string name = "uart_base_seq"); super.new(name); endfunction

  task send_byte(bit [7:0] b, bit inject = 0, int unsigned bitn = 0);
    req = uart_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { data == b; inject_err == inject; err_bit == bitn; idle_bits == 0; })
      `uvm_error("RAND", "randomize failed")
    finish_item(req);
  endtask
endclass

// Send a list of bytes; err_index >= 0 corrupts that byte (bit err_bit)
class uart_send_bytes_seq extends uart_base_seq;
  `uvm_object_utils(uart_send_bytes_seq)
  bit [7:0]    bytes[$];
  int          err_index = -1;
  int unsigned err_bit   = 0;
  function new(string name = "uart_send_bytes_seq"); super.new(name); endfunction
  task body();
    foreach (bytes[i]) send_byte(bytes[i], (i == err_index), err_bit);
  endtask
endclass

// Send a text string
class uart_send_string_seq extends uart_base_seq;
  `uvm_object_utils(uart_send_string_seq)
  string text;
  function new(string name = "uart_send_string_seq"); super.new(name); endfunction
  task body();
    for (int i = 0; i < text.len(); i++) send_byte(text[i]);
  endtask
endclass
