`include "MLP_include.sv"
`include "mlp_bias.svh"
`timescale 1ns / 1ps

module neuron #(
    parameter layerNo = 0,
    parameter neuronNo = 0,
    parameter numWeight = 784,
    parameter dataWidth = 16,
    //parameter sigmoidSize = 5,
    parameter weightIntWidth = 1,
    parameter actType = "relu",
    parameter string biasFile = "",
    parameter string weightFile = ""
) (
    input                      clk,
    input                      rst,
    input      [dataWidth-1:0] myinput,
    input                      myinputValid,
    input                      weightValid,
    input                      biasValid,
    input      [         31:0] weightValue,
    input      [         31:0] biasValue,
    input      [         31:0] config_layer_num,
    input      [         31:0] config_neuron_num,
    output     [dataWidth-1:0] out,
    output reg                 outvalid
);

  parameter int addressWidth = $clog2(numWeight);

  reg wen;
  wire ren;
  reg [addressWidth-1:0] w_addr;
  reg [addressWidth:0]   r_addr;//read address has to reach until numWeight hence width is 1 bit more
  reg [dataWidth-1:0] w_in;
  wire [dataWidth-1:0] w_out;
  reg [2*dataWidth-1:0] mul;
  reg [2*dataWidth-1:0] sum;
  reg [2*dataWidth-1:0] bias;

reg [31:0] biasReg[0:0];
initial biasReg[0] = bias_const(layerNo, neuronNo);
  reg weight_valid;
  reg mult_valid;
  wire mux_valid;
  reg sigValid;
  wire [2*dataWidth:0] comboAdd;
  wire [2*dataWidth:0] BiasAdd;
  reg [dataWidth-1:0] myinputd;
  reg muxValid_d;
  reg muxValid_f;

  //Loading weight values into the memory
  always @(posedge clk) begin : load_rom_from_weight
    if (rst) begin
      w_addr <= {addressWidth{1'b1}};
      wen <= 0;
    end
        else if(weightValid & (config_layer_num==layerNo) & (config_neuron_num==neuronNo))
        begin
      w_in <= weightValue;
      w_addr <= w_addr + 1;
      wen <= 1;
    end else wen <= 0;
  end

  assign mux_valid = mult_valid;
  assign comboAdd = mul + sum;
  assign BiasAdd = bias + sum;
  assign ren = myinputValid;

  always @(posedge clk) begin
bias <= {{dataWidth{biasReg[0][dataWidth-1]}},
         biasReg[0][dataWidth-1:0]} <<< (dataWidth - weightIntWidth);
  end

  /* `ifdef pretrained
  initial begin
    $readmemb(biasFile, biasReg);
  end
  always @(posedge clk) begin
    bias <= {biasReg[addr][dataWidth-1:0], {dataWidth{1'b0}}};
  end
`else
  always @(posedge clk) begin
    if (biasValid & (config_layer_num == layerNo) & (config_neuron_num == neuronNo)) begin
      bias <= {biasValue[dataWidth-1:0], {dataWidth{1'b0}}};
    end
  end
`endif */


  always @(posedge clk) begin
    if (rst | outvalid) r_addr <= 0;
    else if (myinputValid) r_addr <= r_addr + 1;
  end

  always @(posedge clk) begin : multiply_input_and_weight
    mul <= $signed(myinputd) * $signed(w_out);
  end


  always @(posedge clk) begin : MAC
    if (rst | outvalid) sum <= 0;
    else if ((r_addr == numWeight) & muxValid_f) begin
      if(!bias[2*dataWidth-1] &!sum[2*dataWidth-1] & BiasAdd[2*dataWidth-1]) //If bias and sum are positive and after adding bias to sum, if sign bit becomes 1, saturate
            begin
        sum[2*dataWidth-1]   <= 1'b0;
        sum[2*dataWidth-2:0] <= {2 * dataWidth - 1{1'b1}};
      end else if(bias[2*dataWidth-1] & sum[2*dataWidth-1] &  !BiasAdd[2*dataWidth-1]) //If bias and sum are negative and after addition if sign bit is 0, saturate
            begin
        sum[2*dataWidth-1]   <= 1'b1;
        sum[2*dataWidth-2:0] <= {2 * dataWidth - 1{1'b0}};
      end else sum <= BiasAdd;
    end else if (mux_valid) begin
      if (!mul[2*dataWidth-1] & !sum[2*dataWidth-1] & comboAdd[2*dataWidth-1]) begin
        sum[2*dataWidth-1]   <= 1'b0;
        sum[2*dataWidth-2:0] <= {2 * dataWidth - 1{1'b1}};
      end else if (mul[2*dataWidth-1] & sum[2*dataWidth-1] & !comboAdd[2*dataWidth-1]) begin
        sum[2*dataWidth-1]   <= 1'b1;
        sum[2*dataWidth-2:0] <= {2 * dataWidth - 1{1'b0}};
      end else sum <= comboAdd;
    end
  end

  always @(posedge clk) begin : delay_assign
    myinputd <= myinput;
    weight_valid <= myinputValid;
    mult_valid <= weight_valid;
    sigValid <= ((r_addr == numWeight) & muxValid_f) ? 1'b1 : 1'b0;
    outvalid <= sigValid;
    muxValid_d <= mux_valid;
    muxValid_f <= !mux_valid & muxValid_d;
  end


weight_rom #(
    .layer       (layerNo),
    .neuron      (neuronNo),
    .weight_depth(numWeight),
    .data_width  (dataWidth),
    .adress_width(addressWidth)
) WM (
    .clk(clk),
    .read_en(ren),
    .read_addr(r_addr[addressWidth-1:0]),
    .dout(w_out)
);

  generate
    if (actType == "linear") begin : g_Linear
      linear #(
          .data_width(dataWidth),
          .weightIntwidth(weightIntWidth)
      ) s1 (

          .clk(clk),
          .x  (sum),
          .out(out)
      );
    end else begin : g_relu
      relu #(
          .data_width(dataWidth),
          .weightIntwidth(weightIntWidth)
      ) s1 (
          .clk(clk),
          .x  (sum),
          .out(out)
      );
    end
  endgenerate

`ifdef DEBUG
  always @(posedge clk) begin
    if (outvalid) $display(neuronNo,,,, "%b", out);
  end
`endif
endmodule

module weight_rom #(
    parameter int layer        = 1,       // 1, 2, or 3
    parameter int neuron       = 0,       // 0..3
    parameter int weight_depth = 5,
    parameter int data_width   = 32,
    parameter int adress_width = 3
) (
    input  logic                      clk,
    input  logic                      read_en,
    input  logic [adress_width-1:0]   read_addr,
    output logic [data_width-1:0]     dout
);

  `include "mlp_weight.svh"

  reg [data_width-1:0] mem [0:weight_depth-1];

  integer i;
  initial for (i = 0; i < weight_depth; i = i + 1)
      mem[i] = weight_const(layer, neuron, i);

  always_ff @(posedge clk) begin
    if (read_en) dout <= mem[read_addr];
  end

endmodule



/* module MLP #(
    parameters
) (
    ports
);

endmodule */

module relu #(
    parameter data_width = 16,
    parameter weightIntwidth = 4
) (
    input clk,
    input [2*data_width-1:0] x,
    output reg [data_width-1:0] out
);

  always_ff @(posedge clk) begin : relu_process
    if ($signed(x) >= 0) begin
      // Fix slicing logic to target the proper Q-format boundary
      if (|x[2*data_width-1-:data_width-weightIntwidth+1]) begin
        out <= {1'b0, {(data_width - 1) {1'b1}}};
      end else begin
        out <= x[data_width+weightIntwidth-1-:data_width];
      end
    end else begin
      out <= 0;
    end
  end
endmodule

module linear #(
    parameter data_width = 16,
    parameter weightIntwidth = 4
) (
    input clk,
    input [2*data_width-1:0] x,
    output logic [data_width-1:0] out
);
  wire sign = x[2*data_width-1];
  wire overflow = !(&(x[2*data_width-1-:data_width-weightIntwidth+1] ~^{(data_width-weightIntwidth + 1) {sign}}));

  always_ff @(posedge clk) begin : linear_process
    if (overflow)
      out <= sign ? {1'b1, {(data_width - 1) {1'b0}}} : {1'b0, {(data_width - 1) {1'b1}}};
    else out <= x[data_width+weightIntwidth-1-:data_width];  // Fixed here too
  end
endmodule


/* module sigmoid #(
    parameter data_width = 16,
    parameter weightIntwidth = 4
) (
    input clk,
    input [2*data_width-1:0] x,
    output logic [data_width-1:0] out
);



endmodule */
