// AXI4-Lite wrapper around the plain `pwm` core (pwm.sv).
// Core is unchanged. Wrapper adds: bus handshake + 2 registers.
//
// Register map (offset from slave base):
//   0x0  CTRL  bit0 = enable          (rw)
//   0x4  DUTY  PWM_RES bits           (rw)   duty cycle = DUTY / 2^PWM_RES

module axil_pwm #(
    parameter int CLK_FREQ = 27_000_000,
    parameter int PWM_FREQ = 50,
    parameter int PWM_RES  = 8
) (
    input logic clk,
    input logic resetn,

    // AXI4-Lite slave
    input  logic [31:0] awaddr,
    input  logic        awvalid,
    output logic        awready,
    input  logic [31:0] wdata,
    input  logic [ 3:0] wstrb,
    input  logic        wvalid,
    output logic        wready,
    output logic        bvalid,
    input  logic        bready,
    input  logic [31:0] araddr,
    input  logic        arvalid,
    output logic        arready,
    output logic [31:0] rdata,
    output logic        rvalid,
    input  logic        rready,

    output logic pwm_out
);
  // ---------- registers ----------
  logic               enable;
  logic [PWM_RES-1:0] duty_reg;

  // ---------- write channel ----------
  logic               do_write;
  assign do_write = awvalid & wvalid & ~bvalid;
  assign awready  = do_write;
  assign wready   = do_write;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      enable   <= 1'b0;
      duty_reg <= '0;
      bvalid   <= 1'b0;
    end else if (do_write) begin
      bvalid <= 1'b1;
      case (awaddr[3:2])
        2'd0:    if (wstrb[0]) enable   <= wdata[0];
        2'd1:    if (wstrb[0]) duty_reg <= wdata[PWM_RES-1:0];
        default: ;
      endcase
    end else if (bvalid && bready) begin
      bvalid <= 1'b0;
    end
  end

  // ---------- read channel ----------
  logic do_read;
  assign do_read = arvalid & ~rvalid;
  assign arready = do_read;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      rvalid <= 1'b0;
      rdata  <= '0;
    end else if (do_read) begin
      rvalid <= 1'b1;
      case (araddr[3:2])
        2'd0:    rdata <= 32'(enable);
        2'd1:    rdata <= 32'(duty_reg);
        default: rdata <= '0;
      endcase
    end else if (rvalid && rready) begin
      rvalid <= 1'b0;
    end
  end

  // ---------- original core ----------
  logic pwm_line;

  pwm #(
      .CLK_FREQ(CLK_FREQ),
      .PWM_FREQ(PWM_FREQ),
      .PWM_RES (PWM_RES)
  ) core (
      .rst_n     (resetn),
      .clk       (clk),
      .duty_cycle(duty_reg),
      .pwm_line  (pwm_line)
  );

  assign pwm_out = enable & pwm_line;
endmodule
