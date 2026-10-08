`timescale 1ns / 1ps

// Raw sensor values -> 5 scaled Q16.16 MLP features -> start pulse.
// Feature order (must match training): 0 irradiance, 1 hour, 2 hum, 3 temp, 4 wind.
//
// feature = (raw * A) >>> (AFRAC-16) + B      (Q16.16 result)
//   A = unit_scale / std  * 2^AFRAC
//   B = (unit_offset - mean) / std * 2^16
// Defaults below: physical units, mean 0, std 1. Replace with training stats.
//   temp C  = raw * 200/2^20 - 50     hum %  = raw * 100/2^20
//   irr W/m2 = raw                    hour = decoded BCD
//   wind km/h = raw * 0.1 * 3.6 (training data is Open-Meteo km/h; raw = 0.1 m/s)
// Generate A_*/B_* from scaler.mean_ / scaler.scale_ with gen_scaler_params.py.
//
// Fires one inference when both RS485 sensors delivered fresh data
// and MLP is idle. Temp, hum, hour use latest value.
// One shared multiplier, features scaled one per cycle.

module mlp_bridge #(
    parameter int AFRAC = 30,

    parameter logic signed [31:0] A_HOUR = 32'sd1073741824,
    parameter logic signed [31:0] B_HOUR = 32'sd0,
    parameter logic signed [31:0] A_TEMP = 32'sd204800,
    parameter logic signed [31:0] B_TEMP = -32'sd3276800,
    parameter logic signed [31:0] A_HUM  = 32'sd102400,
    parameter logic signed [31:0] B_HUM  = 32'sd0,
    parameter logic signed [31:0] A_IRR  = 32'sd1073741824,
    parameter logic signed [31:0] B_IRR  = 32'sd0,
    parameter logic signed [31:0] A_WIND = 32'sd386547057,
    parameter logic signed [31:0] B_WIND = 32'sd0
) (
    input logic clk,
    input logic resetn,

    input logic [19:0] temp_raw,
    input logic [19:0] hum_raw,
    input logic [15:0] irr_raw,
    input logic [15:0] wind_raw,
    input logic [ 7:0] hour_bcd,
    input logic        irr_valid,
    input logic        wind_valid,

    input  logic              mlp_ready,
    output logic [31:0]       feat[5],
    output logic              start
);

  // DS3231 hours register (BCD, 24h or 12h mode) -> 0..23
  function automatic logic [7:0] bcd_hour(input logic [7:0] h);
    logic [7:0] t;
    if (h[6]) begin
      t = (h[4] ? 8'd10 : 8'd0) + {4'b0, h[3:0]};
      return (t % 12) + (h[5] ? 8'd12 : 8'd0);
    end else begin
      return {6'b0, h[5:4]} * 8'd10 + {4'b0, h[3:0]};
    end
  endfunction

  logic signed [31:0] a_tab[5];
  logic signed [31:0] b_tab[5];
  assign a_tab[0] = A_IRR;
  assign a_tab[1] = A_HOUR;
  assign a_tab[2] = A_HUM;
  assign a_tab[3] = A_TEMP;
  assign a_tab[4] = A_WIND;
  assign b_tab[0] = B_IRR;
  assign b_tab[1] = B_HOUR;
  assign b_tab[2] = B_HUM;
  assign b_tab[3] = B_TEMP;
  assign b_tab[4] = B_WIND;

  typedef enum logic [1:0] {
    IDLE,
    SCALE,
    FIRE
  } st_t;

  st_t                 state;
  logic [         2:0] idx;
  logic [4:0][19:0]    snap;
  logic                irr_seen;
  logic                wind_seen;

  logic signed [20:0] rx;
  logic signed [52:0] prod;
  assign rx   = {1'b0, snap[idx]};
  assign prod = rx * a_tab[idx];

  always_ff @(posedge clk) begin : bridge
    if (!resetn) begin
      state     <= IDLE;
      idx       <= '0;
      irr_seen  <= 1'b0;
      wind_seen <= 1'b0;
      start     <= 1'b0;
      feat      <= '{default: '0}; 
      snap      <= '0;
    end else begin
      start <= 1'b0;

      case (state)
        IDLE: begin
          if (irr_seen && wind_seen && mlp_ready) begin
            snap[0]   <= {4'b0, irr_raw};
            snap[1]   <= {12'b0, bcd_hour(hour_bcd)};
            snap[2]   <= hum_raw;
            snap[3]   <= temp_raw;
            snap[4]   <= {4'b0, wind_raw};
            irr_seen  <= 1'b0;
            wind_seen <= 1'b0;
            idx       <= '0;
            state     <= SCALE;
          end
        end
        SCALE: begin
          feat[idx] <= 32'((prod >>> (AFRAC - 16)) + 53'(b_tab[idx]));
          if (idx == 3'd4) begin
            state <= FIRE;
          end else begin
            idx   <= idx + 1'b1;
          end
        end
        FIRE: begin
          start <= 1'b1;
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase

      // set wins over clear
      if (irr_valid) irr_seen <= 1'b1;
      if (wind_valid) wind_seen <= 1'b1;
    end
  end

endmodule : mlp_bridge
