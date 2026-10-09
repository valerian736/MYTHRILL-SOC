`timescale 1ns / 1ps

module mlp_vector_tb;
  localparam int NV = 100;
  localparam int TOL = 2;
  localparam int TIMEOUT = 2000;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic [31:0] in_data;
  logic        in_valid = 0;
  logic [31:0] out_data;
  logic        out_valid;

  MLP dut (.*);

  logic [31:0] x[5];
  logic [31:0] expected;
  int fd, rc, n, errors, worst, timeouts;
  int diff, t;
  bit done;
  string vec_path;

  // -------------------------------------------------------------------
  // DEBUG: dump ROM + bias contents at time 0
  // -------------------------------------------------------------------
  initial begin
    #1;
    $display("=== ROM dump at t=1 ===");
    $display("L1 n0 ROM[0..4] = %08h %08h %08h %08h %08h", dut.l1.neuron_gen[0].n.WM.mem[0],
             dut.l1.neuron_gen[0].n.WM.mem[1], dut.l1.neuron_gen[0].n.WM.mem[2],
             dut.l1.neuron_gen[0].n.WM.mem[3], dut.l1.neuron_gen[0].n.WM.mem[4]);
    $display("L2 n0 ROM[0..3] = %08h %08h %08h %08h", dut.l2.neuron_gen[0].n.WM.mem[0],
             dut.l2.neuron_gen[0].n.WM.mem[1], dut.l2.neuron_gen[0].n.WM.mem[2],
             dut.l2.neuron_gen[0].n.WM.mem[3]);
    $display("L3 n0 ROM[0..3] = %08h %08h %08h %08h", dut.l3.neuron_gen[0].n.WM.mem[0],
             dut.l3.neuron_gen[0].n.WM.mem[1], dut.l3.neuron_gen[0].n.WM.mem[2],
             dut.l3.neuron_gen[0].n.WM.mem[3]);
    $display("L1 n0 biasReg  = %08h", dut.l1.neuron_gen[0].n.biasReg[0]);
    $display("L3 n0 biasReg  = %08h", dut.l3.neuron_gen[0].n.biasReg[0]);
    $display("========================");
  end

  // -------------------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------------------
  initial begin
    in_data = '0;
    errors = 0;
    worst = 0;
    timeouts = 0;

    if (!$value$plusargs("VEC=%s", vec_path)) vec_path = "tb/vectors.txt";
    $display("Opening vector file: %s", vec_path);
    fd = $fopen(vec_path, "r");
    if (fd == 0) begin
      $display("FAIL: cannot open %s", vec_path);
      $finish;
    end

    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (3) @(posedge clk);

    done = 0;
    for (n = 0; n < NV && !done; n++) begin
      rc = $fscanf(fd, "%h %h %h %h %h %h\n", x[0], x[1], x[2], x[3], x[4], expected);
      if (rc != 6) begin
        $display("stop: vectors.txt ended after %0d vectors", n);
        done = 1;
      end else begin

        // one feature per cycle
        for (int i = 0; i < 5; i++) begin
          @(posedge clk);
          in_data  <= x[i];
          in_valid <= 1'b1;
        end
        @(posedge clk);
        in_valid <= 1'b0;

        // wait for result
        begin
          t = 0;
          while (!out_valid && t < TIMEOUT) begin
            @(posedge clk);
            t++;
          end
          if (!out_valid) begin
            timeouts++;
            $display("vec %0d: TIMEOUT", n);
          end else begin
            diff = $signed(out_data) - $signed(expected);
            if (diff < 0) diff = -diff;
            if (diff > worst) worst = diff;
            if (diff > TOL) begin
              errors++;
              if (n < 5) begin
                $display("vec %0d: MISMATCH got %08h exp %08h (diff %0d LSB)", n, out_data,
                         expected, diff);
                $display("   features: %08h %08h %08h %08h %08h", x[0], x[1], x[2], x[3], x[4]);
              end
            end
          end
        end
        repeat (5) @(posedge clk);
      end
    end

    $display("----");
    $display("vectors run: %0d | mismatches: %0d | timeouts: %0d | worst diff: %0d LSB (tol %0d)",
             n, errors, timeouts, worst, TOL);
    if (errors == 0 && timeouts == 0) $display("PASS");
    else $display("FAIL");
    $fclose(fd);
    $finish;
  end
endmodule
