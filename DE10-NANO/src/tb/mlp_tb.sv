`timescale 1ns / 1ps
`include "MLP_include.sv"


module mlp_tb;

  reg clk = 0;
  reg rst_n = 0;
  reg [`dataWidth-1:0] din;
  reg din_valid;
  wire [`dataWidth-1:0] dout;
  wire dout_valid;

  localparam integer SCALE = 1 << 16;

  MLP dut (
      .s_axi_aclk(clk),
      .s_axi_aresetn(rst_n),
      .axis_in_data(din),
      .axis_in_data_valid(din_valid),
      .axis_in_data_ready(),
      .axis_out_data(dout),
      .axis_out_data_valid(dout_valid)
  );

  always #5 clk = ~clk;

  initial begin
    $dumpfile("mlp_tb.vcd");
    $dumpvars(0, mlp_tb);
  end

  task automatic run_case(input string name, input signed [`dataWidth-1:0] x0,
                          input signed [`dataWidth-1:0] x1, input signed [`dataWidth-1:0] x2,
                          input signed [`dataWidth-1:0] x3, input signed [`dataWidth-1:0] x4);
    real out_real;
    reg signed [`dataWidth-1:0] samples[4];
    integer i;
    begin
      samples[0] = x0;
      samples[1] = x1;
      samples[2] = x2;
      samples[3] = x3;
      samples[4] = x4;
      @(posedge clk);
      for (i = 0; i < 5; i = i + 1) begin
        din       <= samples[i];
        din_valid <= 1'b1;
        @(posedge clk);
      end
      din_valid <= 1'b0;
      wait (dout_valid);
      @(posedge clk);
      out_real = $itor($signed(dout)) / SCALE;
      $display("%-15s | out=%0d (Q16.16) | out=%f mm/h", name, $signed(dout), out_real);
    end
  endtask

  initial begin
    din = 0;
    din_valid = 0;
    rst_n = 0;
    #100;
    rst_n = 1;
    #20;

    // normalized inputs (x-mu)/sigma, quantized to Q16.16
    // order: shortwave_radiation, hour, relative_humidity_2m, temperature_2m, wind_speed_10m
    run_case("Clear_Noon", 136399, 4771, -96290, 165747, -64824);
    run_case("Night_Time", -49419, 99332, 42488, -61762, -81083);
    run_case("Dense_Storm", -39582, 23683, 85189, -88528, 102206);
    run_case("Humid_Morning", 11792, -42510, 10462, -21613, -85517);

    $dumpflush;
    $finish;
  end

endmodule
