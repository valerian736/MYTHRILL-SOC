package axil_pkg;

  typedef struct packed {
    int unsigned idx;
    logic [31:0] start_addr;
    logic [31:0] end_addr;
  } addr_map_32_t;

endpackage
