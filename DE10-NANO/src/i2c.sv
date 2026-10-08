module i2c #(
    parameter int CLK_FREQ = 27000000,
    parameter int BUS_CLK  = 400000
) (
    input  logic clk,
    resetn,
    ena,
    rw,
    output logic ack_error,

    input logic [6:0] addr,
    inout logic scl,
    sda,
    output logic busy,

    input  logic [7:0] darawr,
    output logic [7:0] data_rd
);

  localparam int DIVIDER = (CLK_FREQ / BUS_CLK) / 4;
  typedef enum {
    ready,
    start,
    command,
    slv_ack1,
    wr,
    rd,
    slv_ack2,
    mstr_ack,
    stop
  } I2C_ST;

  I2C_ST state;
  logic data_clk;
  logic data_clk_prev;
  logic scl_clk;
  logic scl_ena;
  logic sda_int = 1'b1;
  logic sda_ena_n;
  logic [7:0] addr_rw;
  logic [7:0] data_tx;
  logic [7:0] data_rx;
  int bit_cnt = 7;
  logic stretch = 0;

  always_ff @(posedge clk) begin : scl_clk_divider
    integer count;
    if (!resetn) begin
      stretch <= 0;
      count = 0;
    end else begin
      data_clk_prev <= data_clk;
      if (count == DIVIDER * 4 - 1) count = 0;
      else if (!stretch) count = count + 1;
      if (count < DIVIDER) begin
        scl_clk  <= 0;
        data_clk <= 0;
      end else if (count < DIVIDER * 2) begin
        scl_clk  <= 0;
        data_clk <= 1'b1;
      end else if (count < DIVIDER * 3) begin
        scl_clk  <= 1'b1;
        stretch  <= (scl == 0);
        data_clk <= 1'b1;
      end else begin
        scl_clk  <= 1'b1;
        data_clk <= 0;
      end
    end
  end

  always_ff @(posedge clk) begin : SDA_LINE

    if (!resetn) begin
      state     <= ready;  //return to initial state
      busy      <= 1'b1;  //indicate not available
      scl_ena   <= 0;  //sets scl high impedance
      sda_int   <= 1'b1;  //sets sda high impedance
      ack_error <= 0;  //clear acknowledge error flag
      bit_cnt   <= 7;  //restarts data bit counter
      data_rd   <= 0;
    end else if (data_clk && !data_clk_prev) begin
      case (state)
        ready: begin
          if (ena) begin
            busy    <= 1'b1;  //flag busy
            addr_rw <= {addr, rw};  //collect requested slave address and command
            data_tx <= darawr;  //collect requested data to write
            state   <= start;
          end else begin
            busy  <= 0;
            state <= ready;
          end
        end

        start: begin
          busy    <= 1'b1;  //resume busy if continuous mode
          sda_int <= addr_rw[bit_cnt];  //set first address bit to bus
          state   <= command;

        end

        command: begin
          if (bit_cnt == 0) begin
            busy <= 1'b1;
            sda_int <= 1'b1;
            bit_cnt <= 7;
            state <= slv_ack1;
          end else begin
            bit_cnt <= bit_cnt - 1;
            sda_int <= addr_rw[bit_cnt-1];
            state   <= command;
          end
        end

        slv_ack1: begin
          if (!addr_rw[0]) begin
            sda_int <= data_tx[bit_cnt];
            state   <= wr;
          end else begin
            sda_int <= 1'b1;
            state   <= rd;
          end
        end

        wr: begin
          busy <= 1'b1;
          if (bit_cnt == 0) begin
            sda_int <= 1'b1;
            bit_cnt <= 7;
            state   <= slv_ack2;
          end else begin
            bit_cnt <= bit_cnt - 1;
            sda_int <= data_tx[bit_cnt-1];
            state   <= wr;
          end
        end

        rd: begin
          busy <= 1'b1;
          if (bit_cnt == 0) begin
            if (ena && (addr_rw == {addr, rw})) begin
              sda_int <= 0;
            end else begin
              sda_int <= 1'b1;
            end
            bit_cnt <= 7;
            data_rd <= data_rx;
            state   <= mstr_ack;
          end else begin
            bit_cnt <= bit_cnt - 1;
          end
        end

        slv_ack2: begin
          if (ena) begin
            busy <= 0;
            addr_rw <= {addr, rw};
            data_tx <= darawr;
            if (addr_rw == {addr, rw}) begin
              sda_int <= darawr[bit_cnt];
              state   <= wr;
            end else begin
              state <= start;
            end
          end else begin
            state <= stop;
          end
        end

        mstr_ack: begin
          if (ena) begin
            busy <= 0;
            addr_rw <= {addr, rw};
            data_tx <= darawr;
            if (addr_rw == {addr, rw}) begin
              sda_int <= 1'b1;
              state   <= rd;
            end else begin
              state <= start;
            end
          end else begin
            state <= stop;
          end
        end

        stop: begin
          busy  <= 0;
          state <= ready;
        end

        default: begin
          state <= ready;
        end
      endcase
    end else if (!data_clk && data_clk_prev) begin
      case (state)
        start:
        if (!scl_ena) begin
          scl_ena   <= 1'b1;
          ack_error <= 0;
        end
        slv_ack1: if (sda != 1'b0 || ack_error) ack_error <= 1'b1;
        rd:       data_rx[bit_cnt] <= sda;
        slv_ack2: if (sda != 1'b0 || ack_error) ack_error <= 1'b1;
        stop:     scl_ena <= 0;
        default:  ;
      endcase
    end
  end

  assign sda_ena_n = (state == start) ? data_clk_prev : (state == stop) ? ~data_clk_prev : sda_int;
  assign scl = (scl_ena && !scl_clk) ? 0 : 1'bz;
  assign sda = (!sda_ena_n) ? 0 : 1'bz;

endmodule
