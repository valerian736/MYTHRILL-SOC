`include "MLP_include.sv"
`timescale 1ns / 1ps

module neuron #(
    parameter int layerNo = 0,
    parameter int neuronNo = 0,
    parameter int numWeight = 784,
    parameter int dataWidth = 16,
    parameter int weightIntWidth = 1,
    parameter string actType = "relu"
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

  // ----- bias lookup as a compile-time constant -----
  localparam [31:0] BIAS_VAL =
      ((layerNo == 1) && (neuronNo == 0)) ? 32'hffff16f7 :
      ((layerNo == 1) && (neuronNo == 1)) ? 32'h0000ecbf :
      ((layerNo == 1) && (neuronNo == 2)) ? 32'h0000cff1 :
      ((layerNo == 1) && (neuronNo == 3)) ? 32'hffffee6e :
      ((layerNo == 2) && (neuronNo == 0)) ? 32'hffffd635 :
      ((layerNo == 2) && (neuronNo == 1)) ? 32'hffffd3f9 :
      ((layerNo == 2) && (neuronNo == 2)) ? 32'hffff9b65 :
      ((layerNo == 2) && (neuronNo == 3)) ? 32'hfffffe22 :
      ((layerNo == 3) && (neuronNo == 0)) ? 32'h00000ebc :
                                            32'h00000000;

  reg wen;
  wire ren;
  reg [addressWidth-1:0] w_addr;
  reg [addressWidth:0] r_addr;
  reg [dataWidth-1:0] w_in;
  wire [dataWidth-1:0] w_out;
  reg [2*dataWidth-1:0] mul;
  reg [2*dataWidth-1:0] sum;
  reg [2*dataWidth-1:0] bias;

  reg weight_valid;
  reg mult_valid;
  wire mux_valid;
  reg sigValid;
  wire [2*dataWidth:0] comboAdd;
  wire [2*dataWidth:0] BiasAdd;
  reg [dataWidth-1:0] myinputd;
  reg muxValid_d;
  reg muxValid_f;

  always @(posedge clk) begin : load_rom_from_weight
    if (rst) begin
      w_addr <= {addressWidth{1'b1}};
      wen <= 0;
    end
    else if (weightValid & (config_layer_num==layerNo) & (config_neuron_num==neuronNo)) begin
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
    bias <= {{dataWidth{BIAS_VAL[dataWidth-1]}},
             BIAS_VAL[dataWidth-1:0]} <<< (dataWidth - weightIntWidth);
  end

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
      if (!bias[2*dataWidth-1] & !sum[2*dataWidth-1] & BiasAdd[2*dataWidth-1]) begin
        sum[2*dataWidth-1]   <= 1'b0;
        sum[2*dataWidth-2:0] <= {2 * dataWidth - 1{1'b1}};
      end else if (bias[2*dataWidth-1] & sum[2*dataWidth-1] & !BiasAdd[2*dataWidth-1]) begin
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

endmodule


module weight_rom #(
    parameter int layer        = 1,
    parameter int neuron       = 0,
    parameter int weight_depth = 5,
    parameter int data_width   = 32,
    parameter int adress_width = 3
) (
    input  logic                    clk,
    input  logic                    read_en,
    input  logic [adress_width-1:0] read_addr,
    output logic [  data_width-1:0] dout
);

  always_ff @(posedge clk) begin
    if (read_en) begin
      if ((layer == 1) && (neuron == 0)) begin
        case (read_addr)
          3'd0: dout <= 32'h0000a174;
          3'd1: dout <= 32'h000017af;
          3'd2: dout <= 32'h000104cd;
          3'd3: dout <= 32'hffff798f;
          3'd4: dout <= 32'h0000601e;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 1) && (neuron == 1)) begin
        case (read_addr)
          3'd0: dout <= 32'h00018636;
          3'd1: dout <= 32'h000013b4;
          3'd2: dout <= 32'h00008134;
          3'd3: dout <= 32'h00001567;
          3'd4: dout <= 32'h0000188c;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 1) && (neuron == 2)) begin
        case (read_addr)
          3'd0: dout <= 32'h0000c034;
          3'd1: dout <= 32'hffff2b0c;
          3'd2: dout <= 32'hfffee69d;
          3'd3: dout <= 32'h000064e0;
          3'd4: dout <= 32'h00003355;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 1) && (neuron == 3)) begin
        case (read_addr)
          3'd0: dout <= 32'h0000e966;
          3'd1: dout <= 32'hffff78ea;
          3'd2: dout <= 32'h00000834;
          3'd3: dout <= 32'hffffedb4;
          3'd4: dout <= 32'hffff4b5e;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 2) && (neuron == 0)) begin
        case (read_addr)
          3'd0: dout <= 32'hffff662b;
          3'd1: dout <= 32'hffffda52;
          3'd2: dout <= 32'hffffddca;
          3'd3: dout <= 32'h00000d48;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 2) && (neuron == 1)) begin
        case (read_addr)
          3'd0: dout <= 32'hffffc24b;
          3'd1: dout <= 32'hffffbbdc;
          3'd2: dout <= 32'hffff9493;
          3'd3: dout <= 32'h00001a66;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 2) && (neuron == 2)) begin
        case (read_addr)
          3'd0: dout <= 32'hffffc7b7;
          3'd1: dout <= 32'hffff3d44;
          3'd2: dout <= 32'hfffe089f;
          3'd3: dout <= 32'h0000912e;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 2) && (neuron == 3)) begin
        case (read_addr)
          3'd0: dout <= 32'h000115ec;
          3'd1: dout <= 32'h00011b96;
          3'd2: dout <= 32'hffff0f92;
          3'd3: dout <= 32'hffff469e;
          default: dout <= 32'h0;
        endcase
      end else if ((layer == 3) && (neuron == 0)) begin
        case (read_addr)
          3'd0: dout <= 32'hffff279a;
          3'd1: dout <= 32'hffffb2fe;
          3'd2: dout <= 32'h0000d69d;
          3'd3: dout <= 32'h0000ab3b;
          default: dout <= 32'h0;
        endcase
      end else begin
        dout <= 32'h0;
      end
    end
  end

endmodule


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
    else out <= x[data_width+weightIntwidth-1-:data_width];
  end
endmodule
