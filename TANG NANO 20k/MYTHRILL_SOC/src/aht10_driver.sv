module aht10_driver #(
    parameter logic [6:0] ADDR = 7'b0111000,
    parameter int CLK_FREQ = 27000000,
    parameter int BUS_SPEED = 400000
) (
    input logic clk,
    rstn,
    inout logic scl,
    sda,
    output logic i2c_ack_error,
    output logic [19:0] temp,
    output logic [19:0] hum
);

  /*     input logic clk,
    resetn,
    ena,
    rw,
    ack_error,
    darawr,
    input logic [7:0] addr,
    inout logic scl,
    sda,
    output logic busy,
    output logic [7:0] data_rd */
  typedef enum {
    s_start,
    s_callibrate,
    s_trigger,
    s_read,
    s_output
  } aht10_s;

  localparam int ONE_MS = CLK_FREQ / 1000;
  localparam int POWERUP_DELAY = 40 * ONE_MS;
  localparam int MEASURE_DELAY = 80 * ONE_MS;

  logic i2c_ena = 0;
  logic [6:0] i2c_addr = 0;
  logic i2c_rw = 0;
  logic [7:0] i2c_data_wr = 0;
  logic i2c_busy;
  logic [7:0] i2c_data_rd;
  logic i2c_ack_err;
  logic busy_prev = 0;

  aht10_s state;
  logic cal = 0;
  logic [19:0] temp_raw = 0;
  logic [19:0] hum_raw = 0;

  assign i2c_ack_error = i2c_ack_err;

  i2c #(
      .CLK_FREQ(CLK_FREQ),
      .BUS_CLK (BUS_SPEED)
  ) aht10 (
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
    static logic [7:0] busy_cnt;
    static logic [$clog2(MEASURE_DELAY+1) - 1:0] counter;

    if (!rstn) begin
      state     <= s_start;
      i2c_ena   <= 0;
      i2c_rw    <= 0;
      cal       <= 0;
      busy_prev <= 0;
      busy_cnt = 0;
      counter  = 0;
      temp_raw <= 0;
      hum_raw  <= 0;
      hum      <= 0;
      temp     <= 0;
    end else begin
      case (state)
        s_start: begin
          if (counter < POWERUP_DELAY) begin
            counter = counter + 1;
          end else begin
            counter = 0;
            state <= s_callibrate;
          end
        end

        s_callibrate: begin
          busy_prev <= i2c_busy;
          if (!busy_prev && i2c_busy) begin
            busy_cnt = busy_cnt + 1;
          end

          case (busy_cnt)
            0: begin
              i2c_ena <= 1'b1;
              i2c_addr <= ADDR;
              i2c_rw <= 0;
              i2c_data_wr <= 8'he1;
            end
            1: begin
              i2c_data_wr <= 8'h08;
            end
            2: begin
              i2c_data_wr <= 8'h00;
            end
            3: begin
              i2c_ena <= 0;
              if (!i2c_busy) begin
                busy_cnt = 0;
                cal   <= 1'b1;
                state <= s_trigger;
              end
            end
            default: begin
              busy_cnt = 0;
            end
          endcase
        end

        s_trigger: begin
          busy_prev <= i2c_busy;
          if (!busy_prev && i2c_busy) begin
            busy_cnt = busy_cnt + 1;
          end
          case (busy_cnt)
            0: begin
              i2c_ena <= 1'b1;
              i2c_addr <= ADDR;
              i2c_rw <= 0;
              i2c_data_wr <= 8'hac;
            end
            1: begin
              i2c_data_wr <= 8'h33;
            end
            2: begin
              i2c_data_wr <= 8'h00;
            end
            3: begin
              i2c_ena <= 0;
              if (!i2c_busy) begin
                busy_cnt = 0;
                counter  = 0;
                state <= s_read;
              end
            end
            default: begin
              busy_cnt = 0;
            end
          endcase
        end

        s_read: begin
          if (counter < MEASURE_DELAY) begin
            counter = counter + 1;
          end else begin
            busy_prev <= i2c_busy;
            if (!busy_prev && i2c_busy) begin
              busy_cnt = busy_cnt + 1;
              case (busy_cnt)
                3: begin
                  hum_raw[19:12] <= i2c_data_rd;
                end
                4: begin
                  hum_raw[11:4] <= i2c_data_rd;
                end
                5: begin
                  hum_raw[3:0] <= i2c_data_rd[7:4];
                  temp_raw[19:16] <= i2c_data_rd[3:0];
                end
                6: begin
                  temp_raw[15:8] <= i2c_data_rd;
                end
              endcase
            end

            case (busy_cnt)
              0: begin
                i2c_ena  <= 1'b1;
                i2c_addr <= ADDR;
                i2c_rw   <= 1'b1;
              end

              6: begin
                i2c_ena <= 0;
                if (!i2c_busy) begin
                  temp_raw[7:0] <= i2c_data_rd;
                  busy_cnt = 0;
                  counter  = 0;
                  state <= s_output;
                end
              end
            endcase
          end
        end

        s_output: begin
          temp  <= temp_raw;
          hum   <= hum_raw;
          state <= s_trigger;
        end

      endcase
    end

  end

endmodule