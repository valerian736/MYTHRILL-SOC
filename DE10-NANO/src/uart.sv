`timescale 1ns / 1ps

module uart #(
    parameter int   BAUD_RATE    = 115200,
    parameter int   CLK_FREQ     = 27000000,
    parameter int   DATA_LENGHT  = 8,
    parameter int   OVERSAMPLING = 16,
    parameter logic PARITY_EN    = 0,
    parameter logic PARITY_EO    = 1
) (
    input logic clk,
    input logic rstn,
    input logic rx,
    output logic tx,
    output logic rx_busy,
    output logic rx_error,
    output logic tx_busy,
    input logic tx_ena,
    input logic [DATA_LENGHT-1:0] tx_data,
    output logic [DATA_LENGHT-1:0] rx_data
);


  localparam int PAR = PARITY_EN ? 1 : 0;
  localparam int baudrate_period = (CLK_FREQ / BAUD_RATE) - 1;
  localparam int baudrate_period_ov = (CLK_FREQ / BAUD_RATE) / OVERSAMPLING - 1;
  localparam int tx_bits = DATA_LENGHT + PAR + 2;
  localparam int rx_bits = DATA_LENGHT + PAR + 2;

  typedef enum logic {
    tx_idle,
    tx_transmit
  } tx_t;
  typedef enum logic {
    rx_idle,
    rx_receive
  } rx_t;

  tx_t state_tx;
  rx_t state_rx;

  logic baud_pulse;
  logic baud_ov_pulse;

  logic [$clog2(baudrate_period + 2)-1:0]    count_baudrate;
  logic [$clog2(baudrate_period_ov + 2)-1:0] count_baudrate_ov;

  always_ff @(posedge clk) begin : clocks
    if (!rstn) begin
      baud_pulse        <= 1'b0;
      baud_ov_pulse     <= 1'b0;
      count_baudrate    <= '0;
      count_baudrate_ov <= '0;
    end else begin
      if (count_baudrate < baudrate_period) begin
        count_baudrate = count_baudrate + 1'b1;
        baud_pulse <= 1'b0;
      end else begin
        count_baudrate = '0;
        baud_pulse <= 1'b1;
        count_baudrate_ov = '0;
      end

      if (count_baudrate_ov < baudrate_period_ov) begin
        count_baudrate_ov = count_baudrate_ov + 1'b1;
        baud_ov_pulse <= 1'b0;
      end else begin
        count_baudrate_ov = '0;
        baud_ov_pulse <= 1'b1;
      end
    end
  end

  logic [      DATA_LENGHT+2:0] tx_buffer;
  logic [$clog2(tx_bits+1)-1:0] tx_bit_count;
  wire                          tx_parity = PARITY_EO ^ (^tx_data);

  always_ff @(posedge clk) begin : transmit
    if (!rstn) begin
      state_tx     <= tx_idle;
      tx           <= 1'b1;
      tx_busy      <= 1'b1;
      tx_bit_count <= '0;
      tx_buffer    <= '1;
    end else begin
      case (state_tx)
        tx_idle: begin
          if (tx_ena) begin
            tx_buffer <= PARITY_EN ? {1'b1, tx_parity, tx_data, 1'b0} : {1'b0, 1'b1, tx_data, 1'b0};
            tx_busy <= 1'b1;
            tx_bit_count <= '0;
            state_tx <= tx_transmit;
          end else begin
            tx_busy <= 1'b0;
          end
        end

        tx_transmit: begin
          if (baud_pulse) begin
            tx           <= tx_buffer[0];
            tx_buffer    <= {1'b1, tx_buffer[DATA_LENGHT+2:1]};
            tx_bit_count <= tx_bit_count + 1'b1;
            if (tx_bit_count == tx_bits - 1) state_tx <= tx_idle;
          end
        end
      endcase
    end
  end

  logic [DATA_LENGHT+PAR:0] rx_buffer;  // {PARITY_EN, data, start}
  logic [$clog2(rx_bits+1)-1:0] rx_count;
  logic [$clog2(OVERSAMPLING)-1:0] os_count;

  wire rx_parity = PARITY_EO ^ (^rx_buffer[DATA_LENGHT:1]);
  wire parity_error = PARITY_EN ? (rx_parity ^ rx_buffer[DATA_LENGHT+PAR]) : 1'b0;

  always_ff @(posedge clk) begin : receive
    if (!rstn) begin
      rx_count  <= '0;
      os_count  <= '0;
      state_rx  <= rx_idle;
      rx_busy   <= 1'b0;
      rx_error  <= 1'b0;
      rx_data   <= '0;
      rx_buffer <= '0;
    end else if (baud_ov_pulse) begin
      case (state_rx)
        rx_idle: begin
          rx_busy <= 1'b0;
          if (rx == 1'b0) begin
            if (os_count < OVERSAMPLING / 2) begin
              os_count <= os_count + 1'b1;
            end else begin
              os_count  <= '0;
              rx_count  <= 1;
              rx_busy   <= 1'b1;
              rx_buffer <= {rx, rx_buffer[DATA_LENGHT+PAR:1]};
              state_rx  <= rx_receive;
            end
          end else begin
            os_count <= '0;
          end
        end

        rx_receive: begin
          if (os_count < OVERSAMPLING - 1) begin
            os_count <= os_count + 1'b1;
          end else if (rx_count < rx_bits - 1) begin
            os_count  <= '0;
            rx_count  <= rx_count + 1'b1;
            rx_buffer <= {rx, rx_buffer[DATA_LENGHT+PAR:1]};
          end else begin  // centre of stop bit
            rx_data  <= rx_buffer[DATA_LENGHT:1];
            rx_error <= rx_buffer[0] | parity_error | ~rx;
            rx_busy  <= 1'b0;
            os_count <= '0;
            state_rx <= rx_idle;
          end
        end
      endcase
    end
  end

endmodule
