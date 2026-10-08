module pwm #(
    parameter int CLK_FREQ = 27_000_000,
    parameter int PWM_FREQ = 1_000,
    parameter int PWM_RES  = 8
) (
    input  logic               rst_n,
    input  logic               clk,
    input  logic [PWM_RES-1:0] duty_cycle,
    output logic               pwm_line
);

  localparam int TICKS = CLK_FREQ / (PWM_FREQ * (2 ** PWM_RES));
  localparam int DIV   = (TICKS < 1) ? 1 : TICKS;
  localparam int DIV_W = (DIV > 1) ? $clog2(DIV) : 1;

  // PWM frequency = CLK_FREQ / (DIV * 2^PWM_RES), DIV = CLK_FREQ / (PWM_FREQ * 2^PWM_RES)
  // Duty         = duty_cycle / 2^PWM_RES

  logic [  DIV_W-1:0] div_cnt;
  logic [PWM_RES-1:0] count;
  logic [PWM_RES-1:0] duty_lat;
  logic               tick;

  assign tick = (div_cnt == DIV_W'(DIV - 1));

  always_ff @(posedge clk) begin : prescaler
    if (!rst_n || tick) div_cnt <= 0;
    else div_cnt <= div_cnt + 1'b1;
  end

  always_ff @(posedge clk) begin : counter
    if (!rst_n) begin
      count    <= 0;
      duty_lat <= 0;
    end else if (tick) begin
      count <= count + 1'b1;
      if (count == {PWM_RES{1'b1}}) duty_lat <= duty_cycle;
    end
  end


  always_ff @(posedge clk) begin : cycle
    if (!rst_n) pwm_line <= 0;
    else pwm_line <= (duty_lat == {PWM_RES{1'b1}}) || (count < duty_lat);
  end

endmodule
