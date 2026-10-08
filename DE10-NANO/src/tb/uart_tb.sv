`include "uart.sv"
`default_nettype none

module tb_uart;

  localparam CLK_PERIOD = 10;
  localparam CLK_FREQ   = 100_000_000;
  localparam BAUD_RATE  = 115200;

  reg           clk = 1'b0;
  reg           rst_n;
  reg           tx_ena = 1'b0;
  reg     [7:0] tx_data = 8'h00;

  wire          rst = ~rst_n;  // DUT reset is active-high, async
  wire          tx;  // loopback: tx drives rx
  wire          rx_busy;
  wire          rx_error;
  wire          tx_busy;
  wire    [7:0] rx_data;

  integer       errors = 0;

  uart #(
      .BAUD_RATE(BAUD_RATE),
      .CLK_FREQ (CLK_FREQ)
  ) dut (
      .clk     (clk),
      .rst     (rst),
      .rx      (tx),
      .tx      (tx),
      .rx_busy (rx_busy),
      .rx_error(rx_error),
      .tx_busy (tx_busy),
      .tx_ena  (tx_ena),
      .tx_data (tx_data),
      .rx_data (rx_data)
  );

  always #(CLK_PERIOD / 2) clk = ~clk;

  task send_and_check(input [7:0] b);
    begin
      wait (!tx_busy);
      @(posedge clk);
      tx_data <= b;
      tx_ena  <= 1'b1;
      @(posedge clk);
      tx_ena <= 1'b0;
      @(negedge rx_busy);
      @(posedge clk);
      if (rx_data === b && rx_error === 1'b0)
        $display("[%0t] PASS: sent 0x%02h got 0x%02h", $time, b, rx_data);
      else begin
        $display("[%0t] FAIL: sent 0x%02h got 0x%02h err=%b", $time, b, rx_data, rx_error);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    $dumpfile("tb_uart.vcd");
    $dumpvars(0, tb_uart);
  end

  // watchdog
  initial begin
    #5_000_000;
    $display("TIMEOUT");
    $finish;
  end

  initial begin
    rst_n = 1'b1;
    #1 rst_n = 1'b0;  // async reset assert
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    send_and_check(8'h55);
    send_and_check(8'hA3);
    send_and_check(8'h00);
    send_and_check(8'hFF);

    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d TEST(S) FAILED", errors);
    $finish;
  end

endmodule
`default_nettype wire
