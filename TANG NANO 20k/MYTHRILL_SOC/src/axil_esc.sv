// AXI4-Lite ESC / servo PWM slave. Drop-in for axil_pwm (same ports, same offsets).
//
// ESC signal: 50 Hz (20 ms period), pulse 1000 us = zero throttle,
//             2000 us = full throttle.
//
// Register map (offset from slave base):
//   0x0  CTRL    bit0 = enable                (rw)   0 -> output low, no signal
//   0x4  PERIOD  frame period in us           (rw)   reset: 20000 (50 Hz)
//   0x8  PULSE   pulse width in us            (rw)   reset: 1000 (zero throttle)


module axil_esc #(
    parameter int CLK_FREQ = 27_000_000,
    parameter int MIN_US   = 1000,
    parameter int MAX_US   = 2000
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

    output logic esc_out
);
  localparam int US_DIV = CLK_FREQ / 1_000_000;               // clocks per microsecond
  localparam int DIV_W  = (US_DIV > 1) ? $clog2(US_DIV) : 1;

  logic        enable;
  logic [15:0] period_us;
  logic [15:0] pulse_us;

  // ---------- write channel ----------
  logic        do_write;
  assign do_write = awvalid & wvalid & ~bvalid;
  assign awready  = do_write;
  assign wready   = do_write;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      enable    <= 1'b0;
      period_us <= 16'd20000;
      pulse_us  <= 16'd1000;
      bvalid    <= 1'b0;
    end else if (do_write) begin
      bvalid <= 1'b1;
      case (awaddr[3:2])
        2'd0: if (wstrb[0]) enable <= wdata[0];
        2'd1:
        period_us <= {
          wstrb[1] ? wdata[15:8] : period_us[15:8], wstrb[0] ? wdata[7:0] : period_us[7:0]
        };
        2'd2:
        pulse_us <= {
          wstrb[1] ? wdata[15:8] : pulse_us[15:8], wstrb[0] ? wdata[7:0] : pulse_us[7:0]
        };
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
        2'd1:    rdata <= 32'(period_us);
        2'd2:    rdata <= 32'(pulse_us);
        default: rdata <= '0;
      endcase
    end else if (rvalid && rready) begin
      rvalid <= 1'b0;
    end
  end

  // ---------- 1 us tick ----------
  logic [DIV_W-1:0] div_cnt;
  logic             tick_us;
  assign tick_us = (div_cnt == DIV_W'(US_DIV - 1));

  always_ff @(posedge clk) begin
    if (!resetn || !enable || tick_us) div_cnt <= '0;
    else div_cnt <= div_cnt + 1'b1;
  end

  // ---------- frame counter, counts microseconds ----------
  logic [15:0] cnt;

  always_ff @(posedge clk) begin
    if (!resetn || !enable) cnt <= '0;
    else if (tick_us) cnt <= ({1'b0, cnt} + 17'd1 >= {1'b0, period_us}) ? 16'd0 : cnt + 16'd1;
  end

  // ---------- pulse clamp (safety) ----------
  logic [15:0] pulse_clamped;

  always_comb begin
    if (pulse_us < 16'(MIN_US)) pulse_clamped = 16'(MIN_US);
    else if (pulse_us > 16'(MAX_US)) pulse_clamped = 16'(MAX_US);
    else pulse_clamped = pulse_us;
  end

  // ---------- output, registered ----------
  always_ff @(posedge clk) begin
    if (!resetn) esc_out <= 1'b0;
    else esc_out <= enable & (cnt < pulse_clamped);
  end
endmodule
