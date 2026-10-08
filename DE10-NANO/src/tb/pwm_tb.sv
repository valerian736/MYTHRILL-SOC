`timescale 1ns / 1ps
`default_nettype none

module tb_pwm;

  localparam int  CLK_FREQ   = 27000000;
  localparam int  PWM_RES    = 8;
  localparam int  PERIOD_CLK = 1 << PWM_RES;           // clocks per PWM period when DIV = 1
  localparam int  PWM_FREQ   = CLK_FREQ / PERIOD_CLK;  // forces DIV = 1: one clock = one count step
  localparam real CLK_PERIOD = 1.0e9 / CLK_FREQ;       // ns (timescale is 1ns/1ps)

  reg                clk;
  reg                rst;
  wire               pwm;
  reg  [PWM_RES-1:0] duty_cycle;

  pwm #(
      .CLK_FREQ(CLK_FREQ),
      .PWM_FREQ(PWM_FREQ),
      .PWM_RES (PWM_RES)
  ) dut (
      .rst_n     (~rst),
      .clk       (clk),
      .duty_cycle(duty_cycle),
      .pwm_line  (pwm)
  );

  // ---------------------------------------------------------------------------
  // Clock (27 MHz)
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD / 2.0) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Waveform dump
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_pwm.vcd");
    $dumpvars(0, tb_pwm);
  end

  // ---------------------------------------------------------------------------
  // Cycle-accurate reference model (scoreboard)
  // Mirrors the DUT with DIV = 1:
  //   - free-running counter
  //   - duty latched when counter is all ones (end of period)
  //   - registered output: full-on if latched duty is all ones, else counter < duty
  // Stimulus is driven on the falling edge and checked on the falling edge, so
  // there are no races with the DUT's posedge updates.
  // ---------------------------------------------------------------------------
  reg     [PWM_RES-1:0] m_counter;
  reg     [PWM_RES-1:0] m_duty;
  reg                   m_pwm;
  reg                   model_valid;  // goes high after the first reset edge
  integer               errors;
  integer               checks;

  always @(posedge clk) begin
    if (rst) begin
      m_counter   <= '0;
      m_duty      <= '0;
      m_pwm       <= 1'b0;
      model_valid <= 1'b1;
    end else begin
      m_counter <= m_counter + 1'b1;
      if (m_counter == '1) m_duty <= duty_cycle;
      m_pwm <= (m_duty == '1) || (m_counter < m_duty);
    end
  end

  always @(negedge clk) begin
    if (model_valid) begin
      checks = checks + 1;
      if (pwm !== m_pwm) begin
        errors = errors + 1;
        $display(
            "[%0t] MISMATCH: pwm=%b expected=%b (model counter=%0d duty_lat=%0d duty=%0d rst=%b)",
            $time, pwm, m_pwm, m_counter, m_duty, duty_cycle, rst);
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Helper tasks
  // ---------------------------------------------------------------------------

  // Apply reset for n clock cycles (driven on the falling edge)
  task automatic do_reset(input int n);
    begin
      @(negedge clk);
      rst = 1'b1;
      repeat (n) @(negedge clk);
      rst = 1'b0;
    end
  endtask

  // Independent check of the duty ratio, separate from the scoreboard.
  // Duty is latched at period end, so wait two periods for the new value to
  // settle, then count high samples over exactly one period.
  // Expected: d high clocks of 2^PWM_RES. Exception: d = all ones is full-on,
  // so 2^PWM_RES high clocks (100 %).
  task automatic check_duty(input int d);
    int high_count;
    int expected;
    begin
      @(negedge clk);
      duty_cycle = d[PWM_RES-1:0];
      repeat (2 * PERIOD_CLK + 2) @(negedge clk);

      high_count = 0;
      repeat (PERIOD_CLK) begin
        @(negedge clk);
        if (pwm === 1'b1) high_count++;
      end

      expected = (d == PERIOD_CLK - 1) ? PERIOD_CLK : d;

      if (high_count !== expected) begin
        errors++;
        $display("[%0t] DUTY FAIL: duty=%0d -> %0d high clocks per period (expected %0d)", $time,
                 d, high_count, expected);
      end else begin
        $display("[%0t] duty=%3d OK  (%0d/%0d high = %0.2f%%)", $time, d, high_count, PERIOD_CLK,
                 100.0 * high_count / PERIOD_CLK);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main stimulus
  // ---------------------------------------------------------------------------
  initial begin
    errors      = 0;
    checks      = 0;
    model_valid = 1'b0;
    rst         = 1'b0;
    duty_cycle  = '0;

    // --- Test 1: power-up reset ------------------------------------------
    $display("--- Test 1: reset ---");
    #1 rst = 1'b1;  // assert before the first clock edge
    repeat (3) @(posedge clk);
    #1;
    if (pwm !== 1'b0) begin
      errors++;
      $display("[%0t] FAIL: pwm_line not low during reset (pwm=%b)", $time, pwm);
    end
    do_reset(2);

    // --- Test 2: duty sweep with independent period counting -------------
    $display("--- Test 2: duty sweep ---");
    check_duty(0);  // always low
    check_duty(1);  // minimum non-zero pulse
    check_duty(2);
    check_duty(64);  // 25 %
    check_duty(127);
    check_duty(128);  // 50 %
    check_duty(192);  // 75 %
    check_duty(254);
    check_duty(255);  // all ones = full-on (100 %)
    check_duty(0);  // back from full-on to off

    // --- Test 3: reset in the middle of a running period ------------------
    // Reset clears the latched duty, so the first period after release stays
    // low. The new duty is latched at the end of that period.
    $display("--- Test 3: mid-period reset ---");
    @(negedge clk);
    duty_cycle = 8'd100;
    repeat (2 * PERIOD_CLK + 17) @(negedge clk);  // settle, then stop unaligned
    rst = 1'b1;
    @(negedge clk);
    @(negedge clk);
    if (pwm !== 1'b0) begin
      errors++;
      $display("[%0t] FAIL: pwm_line not low after mid-run reset", $time);
    end
    rst = 1'b0;
    repeat (PERIOD_CLK - 56) begin  // stay inside first period after release
      @(negedge clk);
      if (pwm !== 1'b0) begin
        errors++;
        $display("[%0t] FAIL: pwm high in first period after reset (duty not yet latched)", $time);
      end
    end
    check_duty(100);  // duty latched, normal operation resumed

    // --- Test 4: duty changes on the fly (mid-period) ---------------------
    // Scoreboard checks that a new duty only takes effect at the next period.
    $display("--- Test 4: on-the-fly duty changes ---");
    repeat (20) begin
      @(negedge clk);
      duty_cycle = $urandom;
      repeat ($urandom_range(1, PERIOD_CLK + 40)) @(negedge clk);
    end

    // --- Test 5: random duty values, each verified over a full period -----
    $display("--- Test 5: random duty values ---");
    repeat (8) check_duty($urandom_range(0, (1 << PWM_RES) - 1));

    // --- Summary ---------------------------------------------------------
    repeat (4) @(negedge clk);
    $display("=====================================================");
    if (errors == 0) $display("PASS: %0d cycle comparisons, 0 errors", checks);
    else $display("FAIL: %0d errors in %0d cycle comparisons", errors, checks);
    $display("=====================================================");
    $finish;
  end

  // Watchdog in case something hangs
  initial begin
    #(CLK_PERIOD * PERIOD_CLK * 400);
    $display("TIMEOUT: testbench did not finish");
    $finish;
  end

endmodule
`default_nettype wire
