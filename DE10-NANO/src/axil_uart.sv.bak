// AXI4-Lite UART slave. Wraps uart.sv.
//
// Register map (offset from slave base):
//   0x0  CTRL     bit0 = enable                       (rw)  gates TX
//   0x4  TX_DATA  write sends one byte                (w)   dropped if disabled or busy
//   0x8  RX_DATA  last received byte                  (r)
//   0xC  STATUS   bit0 tx_busy, bit1 rx_error, bit2 rx_busy   (r)
//   Poll STATUS.tx_busy = 0 before every TX_DATA write.
//   Configuration is set by module parameters.

module axil_uart #(
    parameter int   BAUD_RATE    = 115200,
    parameter int   CLK_FREQ     = 27000000,
    parameter int   DATA_LENGHT  = 8,
    parameter int   OVERSAMPLING = 16,
    parameter logic PARITY_EN    = 0,
    parameter logic PARITY_EO    = 1
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
    input  logic        rready,

    input  logic rx,
    output logic tx
);

  logic                   enable;
  logic [DATA_LENGHT-1:0] tx_data;
  logic [DATA_LENGHT-1:0] rx_data;
  logic                   tx_ena;
  logic                   rx_busy;
  logic                   rx_error;
  logic                   tx_busy;
  logic [            2:0] uart_state;

  // ---------- write channel ----------
  logic                   do_write;
  assign do_write = awvalid & wvalid & ~bvalid;
  assign awready  = do_write;
  assign wready   = do_write;

  always_ff @(posedge clk) begin
    tx_ena <= 1'b0;  // 1-cycle start pulse
    if (!resetn) begin
      enable  <= 1'b0;
      tx_data <= '0;
      bvalid  <= 1'b0;
    end else if (do_write) begin
      bvalid <= 1'b1;
      case (awaddr[3:2])
        2'd0: if (wstrb[0]) enable <= wdata[0];
        2'd1:
        if (wstrb[0]) begin
          tx_data <= wdata[DATA_LENGHT-1:0];
          tx_ena  <= enable;
        end
        default: ;
      endcase
    end else if (bvalid && bready) begin
      bvalid <= 1'b0;
    end
  end

  // ---------- read channel ----------
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
        2'd0:    rdata <= 32'(enable);
        2'd2:    rdata <= 32'(rx_data);
        2'd3:    rdata <= 32'(uart_state);
        default: rdata <= '0;
      endcase
    end else if (rvalid && rready) begin
      rvalid <= 1'b0;
    end
  end

  // tx_ena covers the cycle before uart raises tx_busy, so polling never sees a gap
  assign uart_state = {rx_busy, rx_error, tx_busy | tx_ena};

  // ---------- UART core ----------
  uart #(
      .BAUD_RATE   (BAUD_RATE),
      .CLK_FREQ    (CLK_FREQ),
      .DATA_LENGHT (DATA_LENGHT),
      .OVERSAMPLING(OVERSAMPLING),
      .PARITY_EN   (PARITY_EN),
      .PARITY_EO   (PARITY_EO)
  ) u_uart (
      .clk     (clk),
      .rstn    (resetn),    // uart reset is active HIGH
      .rx      (rx),
      .tx      (tx),
      .rx_busy (rx_busy),
      .rx_error(rx_error),
      .tx_busy (tx_busy),
      .tx_ena  (tx_ena),
      .tx_data (tx_data),
      .rx_data (rx_data)
  );

endmodule
