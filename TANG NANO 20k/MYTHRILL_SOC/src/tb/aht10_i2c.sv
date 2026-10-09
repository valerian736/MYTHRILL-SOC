`timescale 1ns / 1ps

module aht10_slave #(
    parameter logic [6:0] ADDR = 7'h38
) (
    inout wire scl,
    inout wire sda,
    input logic nack,
    input logic stretch_en,
    input logic [19:0] hum_val,
    input logic [19:0] temp_val
);
  typedef enum {
    IDLE,
    ADDR_ST,
    ADDR_ACK,
    WDATA,
    WACK,
    RDATA,
    RACK
  } st_t;
  st_t  st = IDLE;

  logic sda_o = 1;
  logic scl_o = 1;
  assign sda = sda_o ? 1'bz : 1'b0;
  assign scl = scl_o ? 1'bz : 1'b0;

  logic [7:0] rx;
  logic [7:0] tx;
  logic [7:0] rd_bytes[0:5];
  logic [7:0] wlog[0:255];
  int bitn = 0;
  int rd_idx = 0;
  int wcnt = 0;
  int m_ack_cnt = 0;
  int m_nack_cnt = 0;
  int stretch_cnt = 0;
  logic got_byte = 0;
  logic is_read = 0;
  logic master_ack = 0;

  task automatic load_bytes();
    rd_bytes[0] = 8'h18;
    rd_bytes[1] = hum_val[19:12];
    rd_bytes[2] = hum_val[11:4];
    rd_bytes[3] = {hum_val[3:0], temp_val[19:16]};
    rd_bytes[4] = temp_val[15:8];
    rd_bytes[5] = temp_val[7:0];
  endtask

  always @(negedge sda) begin
    if (scl === 1'b1) begin
      st = ADDR_ST;
      bitn = 0;
      got_byte = 0;
      sda_o = 1;
      rd_idx = 0;
    end
  end

  always @(posedge sda) begin
    if (scl === 1'b1) st = IDLE;
  end

  always @(posedge scl) begin
    case (st)
      ADDR_ST, WDATA: begin
        rx   = {rx[6:0], sda};
        bitn = bitn + 1;
        if (bitn == 8) got_byte = 1;
      end
      RACK: begin
        master_ack = !sda;
        if (!sda) m_ack_cnt = m_ack_cnt + 1;
        else m_nack_cnt = m_nack_cnt + 1;
      end
      default: ;
    endcase
  end

  always @(negedge scl) begin
    case (st)
      ADDR_ST:
      if (got_byte) begin
        got_byte = 0;
        if (rx[7:1] == ADDR && !nack) begin
          sda_o = 0;
          is_read = rx[0];
          st = ADDR_ACK;
        end else st = IDLE;
      end
      ADDR_ACK: begin
        sda_o = 1;
        bitn  = 0;
        if (is_read) begin
          load_bytes();
          tx = rd_bytes[rd_idx];
          rd_idx = rd_idx + 1;
          sda_o = tx[7];
          bitn = 1;
          st = RDATA;
        end else st = WDATA;
      end
      WDATA:
      if (got_byte) begin
        got_byte = 0;
        wlog[wcnt] = rx;
        wcnt = wcnt + 1;
        sda_o = 0;
        st = WACK;
      end
      WACK: begin
        sda_o = 1;
        bitn = 0;
        st = WDATA;
      end
      RDATA: begin
        if (bitn < 8) begin
          sda_o = tx[7-bitn];
          bitn  = bitn + 1;
        end else begin
          sda_o = 1;
          st = RACK;
        end
      end
      RACK: begin
        if (master_ack && rd_idx < 6) begin
          tx = rd_bytes[rd_idx];
          rd_idx = rd_idx + 1;
          sda_o = tx[7];
          bitn = 1;
          st = RDATA;
        end else begin
          sda_o = 1;
          st = IDLE;
        end
      end
      default: ;
    endcase
    if (stretch_en && st != IDLE) begin
      scl_o = 0;
      stretch_cnt = stretch_cnt + 1;
      #3000;
      scl_o = 1;
    end
  end
endmodule


module tb;
  parameter int CLK_FREQ = 27000000;
  parameter int BUS_SPEED = 400000;
  localparam real HALF = 1.0e9 / CLK_FREQ / 2.0;
  localparam int MAX_WAIT = (CLK_FREQ / 1000) * 400;

  logic clk = 0;
  logic rstn = 0;
  tri1 scl, sda;
  wire ack_err;
  wire [19:0] temp, hum;

  logic nack = 0;
  logic stretch_en = 0;
  logic [19:0] hum_val = 20'h12345;
  logic [19:0] temp_val = 20'hA6789;

  int errors = 0;
  int upd = 0;

  aht10_driver #(
      .CLK_FREQ (CLK_FREQ),
      .BUS_SPEED(BUS_SPEED)
  ) dut (
      .clk(clk),
      .rstn(rstn),
      .scl(scl),
      .sda(sda),
      .i2c_ack_error(ack_err),
      .temp(temp),
      .hum(hum)
  );

  aht10_slave slave (
      .scl(scl),
      .sda(sda),
      .nack(nack),
      .stretch_en(stretch_en),
      .hum_val(hum_val),
      .temp_val(temp_val)
  );

  always #(HALF) clk = ~clk;

  always @(posedge clk) if (dut.state == 4) upd <= upd + 1;

  task automatic check(input bit cond, input string msg);
    if (cond) $display("  PASS: %s", msg);
    else begin
      $display("  FAIL: %s", msg);
      errors++;
    end
  endtask

  task automatic wait_upd(input int target);
    int guard;
    guard = 0;
    while (upd < target && guard < MAX_WAIT) begin
      @(posedge clk);
      guard++;
    end
    if (upd < target) begin
      $display("  FAIL: timeout waiting for update %0d", target);
      errors++;
    end
    repeat (3) @(posedge clk);
  endtask

  initial begin
    #1000;
    rstn = 1;

    $display("T1: first measurement");
    wait_upd(1);
    check(temp == 20'hA6789, $sformatf("temp = %h, expect a6789", temp));
    check(hum == 20'h12345, $sformatf("hum = %h, expect 12345", hum));
    check(ack_err == 0, "ack_error low");
    check(slave.wcnt >= 6, $sformatf("slave saw %0d write bytes", slave.wcnt));
    check(slave.wlog[0] == 8'hE1 && slave.wlog[1] == 8'h08 && slave.wlog[2] == 8'h00,
          "calibrate bytes E1 08 00");
    check(slave.wlog[3] == 8'hAC && slave.wlog[4] == 8'h33 && slave.wlog[5] == 8'h00,
          "trigger bytes AC 33 00");
    check(slave.m_ack_cnt == 5 && slave.m_nack_cnt == 1, $sformatf(
          "master ACK x%0d then NACK x%0d on last byte", slave.m_ack_cnt, slave.m_nack_cnt));

    $display("T2: new sensor values");
    hum_val  = 20'hFEDCB;
    temp_val = 20'h05A5A;
    wait_upd(upd + 1);
    check(temp == 20'h05A5A, $sformatf("temp = %h, expect 05a5a", temp));
    check(hum == 20'hFEDCB, $sformatf("hum = %h, expect fedcb", hum));
    check(ack_err == 0, "ack_error low");

    $display("T3: slave clock stretching");
    stretch_en = 1;
    hum_val    = 20'h80000;
    temp_val   = 20'h7FFFF;
    wait_upd(upd + 1);
    check(slave.stretch_cnt > 0, $sformatf("slave stretched SCL %0d times", slave.stretch_cnt));
    check(temp == 20'h7FFFF, $sformatf("temp = %h, expect 7ffff", temp));
    check(hum == 20'h80000, $sformatf("hum = %h, expect 80000", hum));
    check(ack_err == 0, "ack_error low");
    stretch_en = 0;

    $display("T4: slave NACK address");
    nack = 1;
    wait_upd(upd + 1);
    check(ack_err == 1, "ack_error high");

    $display("T5: recover after NACK");
    nack = 0;
    hum_val = 20'h12345;
    temp_val = 20'hA6789;
    wait_upd(upd + 2);
    check(ack_err == 0, "ack_error cleared");
    check(temp == 20'hA6789, $sformatf("temp = %h, expect a6789", temp));
    check(hum == 20'h12345, $sformatf("hum = %h, expect 12345", hum));

    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d CHECK(S) FAILED", errors);
    $finish;
  end
endmodule
