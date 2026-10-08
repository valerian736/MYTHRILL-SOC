module reset_top #(
    parameter int CLOCK_CYCLE_RESET = 256
) (
    input  logic clk,
    rst,
    output logic resetn
);

  logic [$clog2(CLOCK_CYCLE_RESET) - 1:0] count = 0;
  assign resetn = (&count) & ~rst;
  always_ff @(posedge clk) begin : counter
    if (!resetn) begin
      count <= count + 1;
    end

  end

endmodule
