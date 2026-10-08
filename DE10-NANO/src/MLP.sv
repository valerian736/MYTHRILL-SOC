`timescale 1ns / 1ps
`include "MLP_include.sv"

// 5 -> 4 (ReLU) -> 4 (ReLU) -> 1 (linear)
// Features arrive one per cycle on in_data while in_valid high.
// Prediction on out_data, qualified by out_valid.
// Weights: w_<layer>_<neuron>.mem, biases: b_<layer>_<neuron>.mem (binary , $readmemb).

`define ASIC_CONFIG 0
`define TEST_RIG 0

`define TIME_INPUT_BITS 16
`define TEMP_INPUT_BITS 16
`define HUM_INPUT_BITS 16
`define IRRADIANCE_INPUT_BITS 16
`define WINDSPEED_INPUT_BITS 16

module MLP (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [`dataWidth-1:0] in_data,
    input  logic                  in_valid,
    output logic [`dataWidth-1:0] out_data,
    output logic                  out_valid
);

  logic reset;
  assign reset = ~rst_n;

  localparam logic        weightValid       = 1'b0;
  localparam logic        biasValid         = 1'b0;
  localparam logic [31:0] weightValue       = 32'd0;
  localparam logic [31:0] biasValue         = 32'd0;
  localparam logic [31:0] config_layer_num  = 32'd0;
  localparam logic [31:0] config_neuron_num = 32'd0;


  logic [           `numNeuronLayer1-1:0] o1_valid;
  logic [`numNeuronLayer1*`dataWidth-1:0] x1_out;
  logic [                 `dataWidth-1:0] s1_data;
  logic                                   s1_valid;

  layer #(
      .NN(`numNeuronLayer1),
      .numWeight(`numWeightLayer1),
      .dataWidth(`dataWidth),
      .layerNum(1),
      .weightIntWidth(`weightIntWidth),
      .actType(`Layer1ActType)
  ) l1 (
      .clk(clk),
      .rst(reset),
      .weightValid(weightValid),
      .biasValid(biasValid),
      .weightValue(weightValue),
      .biasValue(biasValue),
      .config_layer_num(config_layer_num),
      .config_neuron_num(config_neuron_num),
      .x_valid(in_valid),
      .x_in(in_data),
      .o_valid(o1_valid),
      .x_out(x1_out)
  );

  serializer #(
      .N(`numNeuronLayer1),
      .W(`dataWidth)
  ) ser1 (
      .clk(clk),
      .rst(reset),
      .in_valid(o1_valid[0]),
      .in_data(x1_out),
      .out_valid(s1_valid),
      .out_data(s1_data)
  );


  logic [           `numNeuronLayer2-1:0] o2_valid;
  logic [`numNeuronLayer2*`dataWidth-1:0] x2_out;
  logic [                 `dataWidth-1:0] s2_data;
  logic                                   s2_valid;

  layer #(
      .NN(`numNeuronLayer2),
      .numWeight(`numWeightLayer2),
      .dataWidth(`dataWidth),
      .layerNum(2),
      .weightIntWidth(`weightIntWidth),
      .actType(`Layer2ActType)
  ) l2 (
      .clk(clk),
      .rst(reset),
      .weightValid(weightValid),
      .biasValid(biasValid),
      .weightValue(weightValue),
      .biasValue(biasValue),
      .config_layer_num(config_layer_num),
      .config_neuron_num(config_neuron_num),
      .x_valid(s1_valid),
      .x_in(s1_data),
      .o_valid(o2_valid),
      .x_out(x2_out)
  );

  serializer #(
      .N(`numNeuronLayer2),
      .W(`dataWidth)
  ) ser2 (
      .clk(clk),
      .rst(reset),
      .in_valid(o2_valid[0]),
      .in_data(x2_out),
      .out_valid(s2_valid),
      .out_data(s2_data)
  );


  logic [           `numNeuronLayer3-1:0] o3_valid;
  logic [`numNeuronLayer3*`dataWidth-1:0] x3_out;

  layer #(
      .NN(`numNeuronLayer3),
      .numWeight(`numWeightLayer3),
      .dataWidth(`dataWidth),
      .layerNum(3),
      .weightIntWidth(`weightIntWidth),
      .actType(`Layer3ActType)
  ) l3 (
      .clk(clk),
      .rst(reset),
      .weightValid(weightValid),
      .biasValid(biasValid),
      .weightValue(weightValue),
      .biasValue(biasValue),
      .config_layer_num(config_layer_num),
      .config_neuron_num(config_neuron_num),
      .x_valid(s2_valid),
      .x_in(s2_data),
      .o_valid(o3_valid),
      .x_out(x3_out)
  );


  assign out_data       = x3_out;
  assign out_valid = o3_valid[0];

endmodule : MLP


//turn raw value to fitted value
//x-u/s
//output in data input format

/*module s_value (
  ports
);
  
endmodule

module scaler #(
    parameter u[4],
    parameter s[4]
) (
    input  [TIME_INPUT_BITS-1:0] hour,
    input  [TEMP_INPUT_BITS-1:0] temp,
    input  [IRRADIANCE_INPUT_BITS-1:0] irradiance,
    input  [HUM_INPUT_BITS-1:0] hum,
    input  [WINDSPEED_INPUT_BITS-1:0] wind_speed,
    output [dataWidth-1:0] hour_o,
    output [dataWidth-1:0] temp_o,
    output [dataWidth-1:0] irradiance_o,
    output [dataWidth-1:0] hum_o,
    output [dataWidth-1:0] wind_speed_o
);

endmodule : scaler*/



module serializer #(
    parameter int N = 4,
    parameter int W = 31
) (
    input  logic           clk,
    input  logic           rst,
    input  logic           in_valid,
    input  logic [N*W-1:0] in_data,
    output logic           out_valid,
    output logic [  W-1:0] out_data
);

  typedef enum logic {
    IDLE = 1'b0,
    SEND = 1'b1
  } state_t;

  state_t           state;
  int               count;
  logic   [N*W-1:0] hold;

  always_ff @(posedge clk) begin : serializer_proc
    if (rst) begin
      state     <= IDLE;
      count     <= 0;
      out_valid <= 1'b0;
    end else begin
      unique case (state)
        IDLE: begin
          count     <= 0;
          out_valid <= 1'b0;
          if (in_valid) begin
            hold  <= in_data;
            state <= SEND;
          end
        end
        SEND: begin
          out_data  <= hold[W-1:0];
          hold      <= hold >> W;
          count     <= count + 1;
          out_valid <= 1'b1;
          if (count == N) begin
            state     <= IDLE;
            out_valid <= 1'b0;
          end
        end
      endcase
    end
  end

endmodule : serializer


module layer #(
    parameter int    NN             = 30,
    parameter int    numWeight      = 784,
    parameter int    dataWidth      = 16,
    parameter int    layerNum       = 1,
    parameter int    weightIntWidth = 4,
    parameter string actType        = "relu"
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    weightValid,
    input  logic                    biasValid,
    input  logic [            31:0] weightValue,
    input  logic [            31:0] biasValue,
    input  logic [            31:0] config_layer_num,
    input  logic [            31:0] config_neuron_num,
    input  logic                    x_valid,
    input  logic [   dataWidth-1:0] x_in,
    output logic [          NN-1:0] o_valid,
    output logic [NN*dataWidth-1:0] x_out
);


generate
  genvar i;
  for (i = 0; i < NN; i++) begin : neuron_gen
    neuron #(
        .numWeight(numWeight),
        .layerNo(layerNum),
        .neuronNo(i),
        .dataWidth(dataWidth),
        .weightIntWidth(weightIntWidth),
        .actType(actType)
    ) n (
        .clk(clk),
        .rst(rst),
        .myinput(x_in),
        .weightValid(weightValid),
        .biasValid(biasValid),
        .weightValue(weightValue),
        .biasValue(biasValue),
        .config_layer_num(config_layer_num),
        .config_neuron_num(config_neuron_num),
        .myinputValid(x_valid),
        .out(x_out[i*dataWidth+:dataWidth]),
        .outvalid(o_valid[i])
    );
  end
endgenerate

endmodule : layer