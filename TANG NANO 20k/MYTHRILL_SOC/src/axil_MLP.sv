`timescale 1ns / 1ps
`include "MLP_include.sv"

// AXI4-Lite slave wrapper around MLP core (MLP.sv).
//
// Offset  Name      Access  Note
// 0x00    MLP_RDY   r       bit0 = 1: result valid. Clears on new start.
// 0x04    MLP_OUT   r       last prediction
// 0x08    MLP_TRG   w       write bit0 = 1: start. Ignored while busy.
// 0x0C    MLP_INT   rw      clock cycles between auto starts. 0 = manual only.
// 0x10    FEAT0     rw      feature 0 (irradiance; order: irr, hour, hum, temp, wind)
// 0x14    FEAT1     rw
// 0x18    FEAT2     rw
// 0x1C    FEAT3     rw
// 0x20    FEAT4     rw
// 0x24    MLP_SRC   rw      bit0: 1 = features from sensor bridge (default), 0 = FEAT regs


module axil_mlp #(
    parameter int AFRAC = 30,
    parameter logic signed [31:0] A_HOUR = 32'sd1073741824,
    parameter logic signed [31:0] B_HOUR = 32'sd0,
    parameter logic signed [31:0] A_TEMP = 32'sd204800,
    parameter logic signed [31:0] B_TEMP = -32'sd3276800,
    parameter logic signed [31:0] A_HUM = 32'sd102400,
    parameter logic signed [31:0] B_HUM = 32'sd0,
    parameter logic signed [31:0] A_IRR = 32'sd1073741824,
    parameter logic signed [31:0] B_IRR = 32'sd0,
    parameter logic signed [31:0] A_WIND = 32'sd386547057,
    parameter logic signed [31:0] B_WIND = 32'sd0
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

    input logic [19:0] temp_raw,
    input logic [19:0] hum_raw,
    input logic [15:0] irr_raw,
    input logic [15:0] wind_raw,
    input logic [ 7:0] hour_bcd,
    input logic        irr_valid,
    input logic        wind_valid
);

  localparam int NF = `numWeightLayer1;  // features per inference

  logic [`dataWidth-1:0] feat       [NF];
  logic [          31:0] interval;
  logic [          31:0] int_cnt;
  logic [`dataWidth-1:0] result;
  logic                  rdy;
  logic                  busy;
  logic                  feeding;
  logic [`dataWidth-1:0] snap       [NF];
  logic                  src;
  logic [           2:0] fidx;
  logic                  start;
  logic                  trg_wr;

  // ---------- scaler ----------
  logic [          31:0] sens_feat  [ 5];
  logic                  sens_start;

  mlp_bridge #(
      .AFRAC (AFRAC),
      .A_HOUR(A_HOUR),
      .B_HOUR(B_HOUR),
      .A_TEMP(A_TEMP),
      .B_TEMP(B_TEMP),
      .A_HUM (A_HUM),
      .B_HUM (B_HUM),
      .A_IRR (A_IRR),
      .B_IRR (B_IRR),
      .A_WIND(A_WIND),
      .B_WIND(B_WIND)
  ) scaler (
      .clk       (clk),
      .resetn    (resetn),
      .temp_raw  (temp_raw),
      .hum_raw   (hum_raw),
      .irr_raw   (irr_raw),
      .wind_raw  (wind_raw),
      .hour_bcd  (hour_bcd),
      .irr_valid (irr_valid),
      .wind_valid(wind_valid),
      .mlp_ready (~busy),
      .feat      (sens_feat),
      .start     (sens_start)
  );

  // ---------- core ----------
  logic [`dataWidth-1:0] core_in;
  logic                  core_in_valid;
  logic [`dataWidth-1:0] core_out;
  logic                  core_out_valid;

  assign core_in_valid = feeding;
  assign core_in       = snap[fidx];

  MLP core (
      .clk      (clk),
      .rst_n    (resetn),
      .in_data  (core_in),
      .in_valid (core_in_valid),
      .out_data (core_out),
      .out_valid(core_out_valid)
  );

  // ---------- write channel ----------
  logic do_write;
  assign do_write = awvalid & wvalid & ~bvalid;
  assign awready  = do_write;
  assign wready   = do_write;

  assign trg_wr   = do_write & (awaddr[5:2] == 4'd2) & wstrb[0] & wdata[0];

  function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] nw,
                                        input logic [3:0] be);
    for (int b = 0; b < 4; b++) merge[b*8+:8] = be[b] ? nw[b*8+:8] : old[b*8+:8];
  endfunction

  always_ff @(posedge clk) begin : write
    if (!resetn) begin
      bvalid   <= 1'b0;
      interval <= '0;
      src      <= 1'b1;
      for (int i = 0; i < NF; i++) feat[i] <= '0;
    end else if (do_write) begin
      bvalid <= 1'b1;
      case (awaddr[5:2])
        4'd3: interval <= merge(interval, wdata, wstrb);
        4'd4: feat[0] <= merge(feat[0], wdata, wstrb);
        4'd5: feat[1] <= merge(feat[1], wdata, wstrb);
        4'd6: feat[2] <= merge(feat[2], wdata, wstrb);
        4'd7: feat[3] <= merge(feat[3], wdata, wstrb);
        4'd8: feat[4] <= merge(feat[4], wdata, wstrb);
        4'd9: if (wstrb[0]) src <= wdata[0];
        default: ;
      endcase
    end else if (bvalid && bready) begin
      bvalid <= 1'b0;
    end
  end

  // ---------- trigger, feed, result ----------
  logic auto_hit;
  assign auto_hit = (interval != 0) && (int_cnt + 1 >= interval);
  assign start    = (trg_wr | auto_hit | (sens_start & src)) & ~busy;

  always_ff @(posedge clk) begin : control
    if (!resetn) begin
      int_cnt <= '0;
      busy    <= 1'b0;
      feeding <= 1'b0;
      fidx    <= '0;
      rdy     <= 1'b0;
      result  <= '0;
      for (int i = 0; i < NF; i++) snap[i] <= '0;
    end else begin
      if (interval == 0 || auto_hit) int_cnt <= '0;
      else int_cnt <= int_cnt + 1;

      if (start) begin
        busy    <= 1'b1;
        feeding <= 1'b1;
        fidx    <= '0;
        rdy     <= 1'b0;
        for (int i = 0; i < NF; i++) snap[i] <= src ? sens_feat[i] : feat[i];
      end else if (feeding) begin
        if (fidx == NF - 1) feeding <= 1'b0;
        fidx <= fidx + 1;
      end

      if (core_out_valid) begin
        result <= core_out;
        rdy    <= 1'b1;
        busy   <= 1'b0;
      end
    end
  end

  // ---------- read channel ----------
  logic do_read;
  assign do_read = arvalid & ~rvalid;
  assign arready = do_read;

  always_ff @(posedge clk) begin : read
    if (!resetn) begin
      rvalid <= 1'b0;
      rdata  <= '0;
    end else if (do_read) begin
      rvalid <= 1'b1;
      case (araddr[5:2])
        4'd0:    rdata <= 32'(rdy);
        4'd1:    rdata <= 32'(result);
        4'd3:    rdata <= interval;
        4'd4:    rdata <= feat[0];
        4'd5:    rdata <= feat[1];
        4'd6:    rdata <= feat[2];
        4'd7:    rdata <= feat[3];
        4'd8:    rdata <= feat[4];
        4'd9:    rdata <= 32'(src);
        4'd10:   rdata <= snap[0];  // features used by last inference (Q16.16)
        4'd11:   rdata <= snap[1];
        4'd12:   rdata <= snap[2];
        4'd13:   rdata <= snap[3];
        4'd14:   rdata <= snap[4];
        default: rdata <= '0;
      endcase
    end else if (rvalid && rready) begin
      rvalid <= 1'b0;
    end
  end

endmodule : axil_mlp
