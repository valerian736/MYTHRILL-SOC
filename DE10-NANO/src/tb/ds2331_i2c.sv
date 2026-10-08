`timescale 1ns / 1ps

module rtc_slave #(
    parameter logic [6:0] ADDR = 7'h68
) (
    inout wire  scl,
    inout wire  sda,
    input logic nack,
    input logic stretch_en
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

  logic [7:0] regs[0:18];
  logic [7:0] rx;
  logic [7:0] tx;
  logic [7:0] wlog[0:255];
  int ptr = 0;
  int bitn = 0;
  int wcnt = 0;
  int start_cnt = 0;
  int read_cnt = 0;
  int m_ack_cnt = 0;
  int m_nack_cnt = 0;
  int stretch_cnt = 0;
  logic first_byte = 0;
  logic got_byte = 0;
  logic is_read = 0;
  logic master_ack = 0;

  initial begin
    for (int i = 0; i < 19; i++) regs[i] = 8'h00;
    regs[0] = 8'h45;
    regs[1] = 8'h30;
    regs[2] = 8'h23;
    regs[3] = 8'h03;
    regs[4] = 8'h15;
    regs[5] = 8'h08;
    regs[6] = 8'h26;
  end

  always @(negedge sda) begin
    if (scl === 1'b1) begin
      st = ADDR_ST;
      bitn = 0;
      got_byte = 0;
      first_byte = 1;
      sda_o = 1;
      start_cnt = start_cnt + 1;
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
          tx = regs[ptr];
          ptr = (ptr + 1) % 19;
          read_cnt = read_cnt + 1;
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
        if (first_byte) begin
          ptr = rx;
          first_byte = 0;
        end else begin
          regs[ptr] = rx;
          ptr = (ptr + 1) % 19;
        end
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
        if (master_ack) begin
          tx = regs[ptr];
          ptr = (ptr + 1) % 19;
          read_cnt = read_cnt + 1;
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
  wire [7:0] hours;

  logic nack = 0;
  logic stretch_en = 0;

  int errors = 0;
  int upd = 0;

  ds2331_driver #(
      .CLK_FREQ  (CLK_FREQ),
      .BUS_SPEED (BUS_SPEED),
      .POWERUP_MS(10),
      .POLL_MS   (10)
  ) dut (
      .clk(clk),
      .rstn(rstn),
      .scl(scl),
      .sda(sda),
      .i2c_ack_error(ack_err),
      .hours(hours)
  );

  rtc_slave slave (
      .scl(scl),
      .sda(sda),
      .nack(nack),
      .stretch_en(stretch_en)
  );

  always #(HALF) clk = ~clk;

  always @(posedge clk) if (dut.state == 2) upd <= upd + 1;

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

    $display("T1: first read");
    wait_upd(1);
    check(hours == 8'h23, $sformatf("hours = %h, expect 23", hours));
    check(ack_err == 0, "ack_error low");
    check(slave.wcnt == 1 && slave.wlog[0] == 8'h02, "pointer byte 02 written");
    check(slave.start_cnt == 2, $sformatf("START + repeated START (%0d)", slave.start_cnt));
    check(slave.read_cnt == 1, $sformatf("slave sent %0d byte, expect 1", slave.read_cnt));
    check(slave.m_ack_cnt == 0 && slave.m_nack_cnt == 1, $sformatf(
          "master NACK on only byte (ack %0d, nack %0d)", slave.m_ack_cnt, slave.m_nack_cnt));

    $display("T2: hours change");
    slave.regs[2] = 8'h07;
    wait_upd(upd + 1);
    check(hours == 8'h07, $sformatf("hours = %h, expect 07", hours));
    slave.regs[2] = 8'h12;
    wait_upd(upd + 1);
    check(hours == 8'h12, $sformatf("hours = %h, expect 12", hours));
    check(ack_err == 0, "ack_error low");

    $display("T3: slave clock stretching");
    stretch_en = 1;
    slave.regs[2] = 8'h19;
    wait_upd(upd + 1);
    check(slave.stretch_cnt > 0, $sformatf("slave stretched SCL %0d times", slave.stretch_cnt));
    check(hours == 8'h19, $sformatf("hours = %h, expect 19", hours));
    check(ack_err == 0, "ack_error low");
    stretch_en = 0;

    $display("T4: slave NACK address");
    nack = 1;
    wait_upd(upd + 1);
    check(ack_err == 1, "ack_error high");

    $display("T5: recover after NACK");
    nack = 0;
    slave.regs[2] = 8'h05;
    wait_upd(upd + 2);
    check(ack_err == 0, "ack_error cleared");
    check(hours == 8'h05, $sformatf("hours = %h, expect 05", hours));

    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d CHECK(S) FAILED", errors);
    $finish;
  end
endmodule
