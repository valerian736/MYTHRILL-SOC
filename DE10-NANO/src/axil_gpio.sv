`default_nettype wire
// AXI4-Lite GPIO slave.
// Register map (offset from slave base):
//   0x0  OUT  read/write  drives gpio_out
//   0x4  IN   read-only   samples gpio_in

module axil_gpio #(
    parameter int GPIO_W = 8
) (
    input logic clk,
    input logic resetn,

    // AXI4-Lite slave
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
    input  logic        rready,

    // pins
    output logic [GPIO_W-1:0] gpio_out,
    input  logic [GPIO_W-1:0] gpio_in
);
  // ---- write ----
  logic do_write;
  assign do_write = awvalid & wvalid & ~bvalid;
  assign awready  = do_write;
  assign wready   = do_write;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      gpio_out <= '0;
      bvalid   <= 1'b0;
    end else if (do_write) begin
      bvalid <= 1'b1;
      if (awaddr[3:2] == 2'd0 && wstrb[0]) gpio_out <= wdata[GPIO_W-1:0];
    end else if (bvalid && bready) begin
      bvalid <= 1'b0;
    end
  end

  // ---- read ----
  logic do_read;
  assign do_read = arvalid & ~rvalid;
  assign arready = do_read;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      rvalid <= 1'b0;
      rdata  <= '0;
    end else if (do_read) begin
      rvalid <= 1'b1;
      case (araddr[3:2])
        2'd0:    rdata <= 32'(gpio_out);
        2'd1:    rdata <= 32'(gpio_in);
        default: rdata <= '0;
      endcase
    end else if (rvalid && rready) begin
      rvalid <= 1'b0;
    end
  end
endmodule
