module ds2331_driver #(
    parameter logic [6:0] ADDR = 7'b1101000,
    parameter int CLK_FREQ = 27000000,
    parameter int BUS_SPEED = 400000,
    parameter int POWERUP_MS = 250,
    parameter int POLL_MS = 100
) (
    input logic clk,
    rstn,
    inout wire scl,
    sda,
    output logic i2c_ack_error,
    output logic [7:0] hours
);

  typedef enum {
    s_start,
    s_read,
    s_output,
    s_wait
  } ds_s;

  localparam int ONE_MS = CLK_FREQ / 1000;
  localparam int POWERUP_DELAY = POWERUP_MS * ONE_MS;
  localparam int POLL_DELAY = POLL_MS * ONE_MS;
  localparam int MAX_DELAY = (POWERUP_DELAY > POLL_DELAY) ? POWERUP_DELAY : POLL_DELAY;

  logic i2c_ena = 0;
  logic [6:0] i2c_addr = 0;
  logic i2c_rw = 0;
  logic [7:0] i2c_data_wr = 0;
  logic i2c_busy;
  logic [7:0] i2c_data_rd;
  logic i2c_ack_err;
  logic busy_prev = 0;

  ds_s state;
  logic [7:0] hour_raw = 0;

  assign i2c_ack_error = i2c_ack_err;

  i2c #(
      .CLK_FREQ(CLK_FREQ),
      .BUS_CLK (BUS_SPEED)
  ) rtc (
      .clk(clk),
      .resetn(rstn),
      .ena(i2c_ena),
      .rw(i2c_rw),
      .ack_error(i2c_ack_err),
      .darawr(i2c_data_wr),
      .addr(i2c_addr),
      .scl(scl),
      .sda(sda),
      .busy(i2c_busy),
      .data_rd(i2c_data_rd)
  );

  always_ff @(posedge clk) begin : fsm
    logic [7:0] busy_cnt;
    logic [$clog2(MAX_DELAY+1) - 1:0] counter;

    if (!rstn) begin
      state     <= s_start;
      i2c_ena   <= 0;
      i2c_rw    <= 0;
      busy_prev <= 0;
      busy_cnt = 0;
      counter  = 0;
      hour_raw <= 0;
      hours    <= 0;
    end else begin
      case (state)
        s_start: begin
          if (counter < POWERUP_DELAY) begin
            counter = counter + 1;
          end else begin
            counter = 0;
            state <= s_read;
          end
        end

        s_read: begin
          busy_prev <= i2c_busy;
          if (!busy_prev && i2c_busy) begin
            busy_cnt = busy_cnt + 1;
          end

          case (busy_cnt)
            0: begin
              i2c_ena <= 1'b1;
              i2c_addr <= ADDR;
              i2c_rw <= 0;
              i2c_data_wr <= 8'h02;
            end
            1: begin
              i2c_rw <= 1'b1;
            end
            2: begin
              i2c_ena <= 0;
              if (!i2c_busy) begin
                hour_raw <= i2c_data_rd;
                busy_cnt = 0;
                counter  = 0;
                state <= s_output;
              end
            end
            default: begin
              busy_cnt = 0;
            end
          endcase
        end

        s_output: begin
          hours <= hour_raw;
          state <= s_wait;
        end

        s_wait: begin
          if (counter < POLL_DELAY) begin
            counter = counter + 1;
          end else begin
            counter = 0;
            state <= s_read;
          end
        end

      endcase
    end

  end

endmodule
