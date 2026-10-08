`default_nettype wire
// AXI4-Lite BRAM slave. Holds firmware.
// Memory write and read are in their own always_ff without reset,
// so synthesis tools can infer block RAM.

module axil_bram #(
    parameter int    WORDS = 1024,           // 4 KB
    parameter  INIT  = "firmware.hex"
) (
    input logic clk,
    input logic resetn,

    input  logic [31:0] awaddr,
    input  logic        awvalid,
    output logic        awready,
    input  logic [31:0] wdata,
    input  logic [ 3:0] wstrb,
    input  logic        wvalid,
    output logic        wready,
    output logic        bvalid,
    input  logic        bready,
    input  logic [31:0] araddr,
    input  logic        arvalid,
    output logic        arready,
    output logic [31:0] rdata,
    output logic        rvalid,
    input  logic        rready
);
  localparam int AW = $clog2(WORDS);

  logic [31:0] mem[WORDS];
  initial $readmemh(INIT, mem);

  // ---- write ----
  logic do_write;
  assign do_write = awvalid & wvalid & ~bvalid;
  assign awready  = do_write;
  assign wready   = do_write;

  logic [AW-1:0] widx;
  assign widx = awaddr[AW+1:2];

  // memory array: no reset
  always_ff @(posedge clk) begin
    if (do_write) begin
      if (wstrb[0]) mem[widx][7:0] <= wdata[7:0];
      if (wstrb[1]) mem[widx][15:8] <= wdata[15:8];
      if (wstrb[2]) mem[widx][23:16] <= wdata[23:16];
      if (wstrb[3]) mem[widx][31:24] <= wdata[31:24];
    end
  end

  // write response
  always_ff @(posedge clk) begin
    if (!resetn) bvalid <= 1'b0;
    else if (do_write) bvalid <= 1'b1;
    else if (bvalid && bready) bvalid <= 1'b0;
  end

  // ---- read ----
  logic do_read;
  assign do_read = arvalid & ~rvalid;
  assign arready = do_read;

  logic [AW-1:0] ridx;
  assign ridx = araddr[AW+1:2];

  // read data: synchronous, no reset
  always_ff @(posedge clk) begin
    if (do_read) rdata <= mem[ridx];
  end

  // read response
  always_ff @(posedge clk) begin
    if (!resetn) rvalid <= 1'b0;
    else if (do_read) rvalid <= 1'b1;
    else if (rvalid && rready) rvalid <= 1'b0;
  end
endmodule
