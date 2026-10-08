module rs485_controller #(
    parameter int BAUD_RATE = 4800,
    parameter int CLK_FREQ = 27000000,
    parameter int DATA_LENGHT = 8,
    parameter int OVERSAMPLING = 16,
    parameter logic PARITY = 0,
    parameter logic PARITY_EO = 1,
    parameter int DATA_WIDTH = 16,
    parameter int TIMEOUT_MS = 100,
    parameter logic [7:0] REQUEST_PATTERN[8] = '{
        8'h01,
        8'h03,
        8'h00,
        8'h00,
        8'h00,
        8'h01,
        8'h84,
        8'h0A
    }
) (
    //input logic [31:0] MS,
    input logic tx_trigger,
    output logic de_re,
    input logic clk,
    input logic rstn,
    input logic rx,
    output logic tx,
    output logic [DATA_WIDTH-1:0] data_raw,
    output logic data_valid,
    output logic frame_error,
    // debug: flags [0] timeout, [1] uart rx error, [2] bad frame/CRC, [3] request sent
    output logic [3:0] dbg_flags,
    output logic [3:0] dbg_rx_cnt,  // bytes received in last query
    output logic [7:0] dbg_tx_cnt,  // queries sent since reset
    output logic [7:0] dbg_rx0      // first byte received in last query
);

  // ---------------------------------------------------------------
  // Poll timer: fixed-size 1 ms tick counter + runtime ms counter
  // ---------------------------------------------------------------


  localparam int REQUEST_LEN = 8;
  localparam int RESPONSE_LEN = 7;
  localparam int BIT_CYCLES = CLK_FREQ / BAUD_RATE;
  localparam int TAIL_CYCLES = 2 * BIT_CYCLES;  // last stop bit + margin before releasing bus
  localparam int TIMEOUT_CYCLES = (CLK_FREQ / 1000) * TIMEOUT_MS;
  localparam int CNT_MAX = (TIMEOUT_CYCLES > TAIL_CYCLES) ? TIMEOUT_CYCLES : TAIL_CYCLES;

  typedef enum logic [2:0] {
    IDLE,
    QUERY,
    TAIL,
    DATA,
    CHECK
  } rs485_t;

  typedef enum logic [1:0] {
    SEND,
    WAIT_START,
    WAIT_END
  } tx_step_t;

  rs485_t state;
  tx_step_t tx_step;

  logic rs485_rx_busy;
  logic rs485_rx_error;
  logic [DATA_LENGHT-1:0] rs485_rx_data;
  logic rs485_tx_busy;
  logic rs485_rx_busy_prev = 0;
  logic rs485_tx_ena = 0;
  logic [DATA_LENGHT-1:0] current_byte = 0;

  logic [$clog2(REQUEST_LEN+1)-1:0] tx_idx;
  logic [$clog2(RESPONSE_LEN+1)-1:0] rx_idx;
  logic [$clog2(CNT_MAX+1)-1:0] wait_cnt;
  logic [15:0] crc;
  logic [7:0] rx_frame[RESPONSE_LEN];

  wire rx_byte_done = rs485_rx_busy_prev & ~rs485_rx_busy;

  // Modbus CRC16 (poly 0xA001, init 0xFFFF)
  function automatic logic [15:0] crc16_update(input logic [15:0] crc_in, input logic [7:0] b);
    logic [15:0] c;
    c = crc_in ^ {8'h00, b};
    for (int i = 0; i < 8; i++) begin
      c = c[0] ? ((c >> 1) ^ 16'hA001) : (c >> 1);
    end
    return c;
  endfunction

  wire frame_ok = (rx_frame[0] == REQUEST_PATTERN[0]) &&
                  (rx_frame[1] == REQUEST_PATTERN[1]) &&
                  (rx_frame[2] == 8'h02) &&
                  (crc == {rx_frame[6], rx_frame[5]});

  always_ff @(posedge clk) begin : rs485_query_fsm
    if (!rstn) begin
      state <= IDLE;
      tx_step <= SEND;
      de_re <= 1'b0;
      rs485_tx_ena <= 1'b0;
      rs485_rx_busy_prev <= 1'b0;
      current_byte <= '0;
      tx_idx <= '0;
      rx_idx <= '0;
      wait_cnt <= '0;
      crc <= 16'hFFFF;
      data_raw <= '0;
      data_valid <= 1'b0;
      frame_error <= 1'b0;
      dbg_flags <= '0;
      dbg_rx_cnt <= '0;
      dbg_tx_cnt <= '0;
      dbg_rx0 <= '0;
      for (int i = 0; i < RESPONSE_LEN; i++) rx_frame[i] <= '0;
    end else begin
      data_valid <= 1'b0;
      rs485_rx_busy_prev <= rs485_rx_busy;

      case (state)
        IDLE: begin
          rs485_tx_ena <= 1'b0;
          de_re <= 1'b0;
          if (tx_trigger == 1'b1) begin
            de_re <= 1'b1;
            frame_error <= 1'b0;
            dbg_flags <= '0;
            dbg_rx_cnt <= '0;
            dbg_rx0 <= '0;
            dbg_tx_cnt <= dbg_tx_cnt + 1'b1;
            tx_idx <= '0;
            tx_step <= SEND;
            state <= QUERY;
          end
        end


        QUERY: begin
          case (tx_step)
            SEND: begin
              current_byte <= REQUEST_PATTERN[tx_idx];
              rs485_tx_ena <= 1'b1;
              tx_step <= WAIT_START;
            end

            WAIT_START: begin
              if (rs485_tx_busy) begin
                rs485_tx_ena <= 1'b0;
                tx_step <= WAIT_END;
              end
            end

            WAIT_END: begin
              if (!rs485_tx_busy) begin
                if (tx_idx == REQUEST_LEN - 1) begin
                  wait_cnt <= '0;
                  dbg_flags[3] <= 1'b1;
                  state <= TAIL;
                end else begin
                  tx_idx  <= tx_idx + 1'b1;
                  tx_step <= SEND;
                end
              end
            end

            default: tx_step <= SEND;
          endcase
        end


        TAIL: begin
          if (wait_cnt >= TAIL_CYCLES) begin
            de_re <= 1'b0;
            wait_cnt <= '0;
            rx_idx <= '0;
            crc <= 16'hFFFF;
            state <= DATA;
          end else begin
            wait_cnt <= wait_cnt + 1'b1;
          end
        end

        // Collect response bytes
        DATA: begin
          if (rx_byte_done) begin
            wait_cnt <= '0;
            if (rs485_rx_error) begin
              frame_error <= 1'b1;
              dbg_flags[1] <= 1'b1;
              state <= IDLE;
            end else begin
              dbg_rx_cnt <= dbg_rx_cnt + 1'b1;
              if (rx_idx == 0) dbg_rx0 <= rs485_rx_data[7:0];
              rx_frame[rx_idx] <= rs485_rx_data[7:0];
              if (rx_idx < RESPONSE_LEN - 2) crc <= crc16_update(crc, rs485_rx_data[7:0]);
              if (rx_idx == RESPONSE_LEN - 1) state <= CHECK;
              else rx_idx <= rx_idx + 1'b1;
            end
          end else if (wait_cnt >= TIMEOUT_CYCLES) begin
            frame_error <= 1'b1;
            dbg_flags[0] <= 1'b1;
            state <= IDLE;
          end else begin
            wait_cnt <= wait_cnt + 1'b1;
          end
        end

        // Validate frame, latch value
        CHECK: begin
          if (frame_ok) begin
            data_raw   <= {rx_frame[3], rx_frame[4]};
            data_valid <= 1'b1;
          end else begin
            frame_error <= 1'b1;
            dbg_flags[2] <= 1'b1;
          end
          state <= IDLE;
        end

        default: begin
          state <= IDLE;
        end
      endcase
    end
  end

  uart #(
      .BAUD_RATE   (BAUD_RATE),
      .CLK_FREQ    (CLK_FREQ),
      .DATA_LENGHT (DATA_LENGHT),
      .OVERSAMPLING(OVERSAMPLING),
      .PARITY_EN   (PARITY),
      .PARITY_EO   (PARITY_EO)
  ) rs485 (
      .*,
      .rx_busy (rs485_rx_busy),
      .rx_error(rs485_rx_error),
      .tx_busy (rs485_tx_busy),
      .tx_ena  (rs485_tx_ena),
      .tx_data (current_byte),
      .rx_data (rs485_rx_data)
  );

endmodule