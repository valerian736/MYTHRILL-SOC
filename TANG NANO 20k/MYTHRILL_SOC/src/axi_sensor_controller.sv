`timescale 1ns / 1ps

// Register map (byte offset from slave base):
//   0x00 TEMP   r   AHT10 raw temp, 20 bit
//   0x04 HUM    r   AHT10 raw hum, 20 bit
//   0x08 IRR    r   SEM228A raw, 16 bit
//   0x0C WIND   r   SN3000 raw, 16 bit
//   0x10 HOUR   r   DS3231 hours register (BCD)
//   0x14 STATUS r   bit4 irr, bit3 wind, bit2 temp, bit1 hum, bit0 hour. 1 = healthy
//   0x18 POLL   rw  RS485 poll period in ms (default 1000)
//   0x1C IRR_DBG  r {rx0[7:0], tx_cnt[7:0], rx_cnt[3:0], flags[3:0]}
//   0x20 WIND_DBG r same. flags: bit0 timeout, bit1 uart err, bit2 bad frame, bit3 request sent


module axi_sensor_controller #(
    parameter int CLK_FREQ  = 27_000_000,
    parameter int I2C_SPEED = 400_000
) (
    input logic clk,
    input logic resetn,

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

    input  logic SEM228A_RX,
    output logic SEM228A_TX,
    output logic SEM228A_DERE,
    input  logic SN3000_RX,
    output logic SN3000_TX,
    output logic SN3000_DERE,
    inout  wire SCL_AHT,
    inout  wire SDA_AHT,
    inout  wire SCL_RTC,
    inout  wire SDA_RTC,

    // direct sensor outputs
    output logic [19:0] temp_raw,
    output logic [19:0] hum_raw,
    output logic [15:0] irr_raw,
    output logic [15:0] wind_raw,
    output logic [ 7:0] hour_raw,
    output logic        irr_valid,
    output logic        wind_valid
);

  localparam int PIPE = 3;

  logic [19:0] temp_d, hum_d;
  logic [15:0] irr_d, wind_d;
  logic [ 7:0] hour_d;
  logic irr_valid_d, wind_valid_d;
  logic irr_valid_i, wind_valid_i;

  sync_pipe #(.W(20), .STAGES(PIPE)) p_temp (.clk(clk), .rstn(resetn), .d(temp_d), .q(temp_raw));
  sync_pipe #(.W(20), .STAGES(PIPE)) p_hum  (.clk(clk), .rstn(resetn), .d(hum_d),  .q(hum_raw));
  sync_pipe #(.W(16), .STAGES(PIPE)) p_irr  (.clk(clk), .rstn(resetn), .d(irr_d),  .q(irr_raw));
  sync_pipe #(.W(16), .STAGES(PIPE)) p_wind (.clk(clk), .rstn(resetn), .d(wind_d), .q(wind_raw));
  sync_pipe #(.W(8),  .STAGES(PIPE)) p_hour (.clk(clk), .rstn(resetn), .d(hour_d), .q(hour_raw));
  sync_pipe #(.W(1),  .STAGES(PIPE)) p_irrv (.clk(clk), .rstn(resetn), .d(irr_valid_i),  .q(irr_valid));
  sync_pipe #(.W(1),  .STAGES(PIPE)) p_windv(.clk(clk), .rstn(resetn), .d(wind_valid_i), .q(wind_valid));

  // RS485 debug: 0x1C irr, 0x20 wind = {rx0[7:0], tx_cnt[7:0], rx_cnt[3:0], flags[3:0]}
  logic [3:0] irr_dbg_fl, irr_dbg_rxc, wind_dbg_fl, wind_dbg_rxc;
  logic [7:0] irr_dbg_tx, irr_dbg_rx0, wind_dbg_tx, wind_dbg_rx0;

  logic [31:0] sensor_poll_ms;
  logic        sensor_poll;

  logic aht_ack_err, rtc_ack_err;
  logic irr_ferr, wind_ferr;
  logic irr_ok, wind_ok;

  logic [4:0] sensor_status;
  assign sensor_status = {irr_ok, wind_ok, ~aht_ack_err, ~aht_ack_err, ~rtc_ack_err};

  // ---------- AXI-Lite write ----------
  logic do_write;
  assign do_write = awvalid & wvalid & ~bvalid;
  assign awready  = do_write;
  assign wready   = do_write;

  always_ff @(posedge clk) begin : write
    if (!resetn) begin
      bvalid         <= 1'b0;
      sensor_poll_ms <= 32'd1000;
    end else if (do_write) begin
      bvalid <= 1'b1;
      if (awaddr[4:2] == 3'd6) begin
        for (int b = 0; b < 4; b++)
        if (wstrb[b]) sensor_poll_ms[b*8+:8] <= wdata[b*8+:8];
      end
    end else if (bvalid && bready) begin
      bvalid <= 1'b0;
    end
  end

  // ---------- AXI-Lite read ----------
  logic do_read;
  assign do_read = arvalid & ~rvalid;
  assign arready = do_read;

  always_ff @(posedge clk) begin : read
    if (!resetn) begin
      rvalid <= 1'b0;
      rdata  <= '0;
    end else if (do_read) begin
      rvalid <= 1'b1;
      case (araddr[5:2])
        4'd0:    rdata <= 32'(temp_raw);
        4'd1:    rdata <= 32'(hum_raw);
        4'd2:    rdata <= 32'(irr_raw);
        4'd3:    rdata <= 32'(wind_raw);
        4'd4:    rdata <= 32'(hour_raw);
        4'd5:    rdata <= 32'(sensor_status);
        4'd6:    rdata <= sensor_poll_ms;
        4'd7:    rdata <= {8'b0, irr_dbg_rx0, irr_dbg_tx, irr_dbg_rxc, irr_dbg_fl};
        4'd8:    rdata <= {8'b0, wind_dbg_rx0, wind_dbg_tx, wind_dbg_rxc, wind_dbg_fl};
        default: rdata <= '0;
      endcase
    end else if (rvalid && rready) begin
      rvalid <= 1'b0;
    end
  end

  // ---------- RS485 health ----------
  always_ff @(posedge clk) begin
    if (!resetn) begin
      irr_ok  <= 1'b0;
      wind_ok <= 1'b0;
    end else begin
      if (irr_valid_i) irr_ok <= 1'b1;
      else if (irr_ferr) irr_ok <= 1'b0;
      if (wind_valid_i) wind_ok <= 1'b1;
      else if (wind_ferr) wind_ok <= 1'b0;
    end
  end

  // ---------- sensors ----------
  sensor_poll_timer #(
      .CLK_FREQ(CLK_FREQ)
  ) poll (
      .clk (clk),
      .rstn(resetn),
      .ms  (sensor_poll_ms),
      .tick(sensor_poll)
  );

  rs485_controller #(
      .CLK_FREQ(CLK_FREQ)
  ) sem228a (
      .tx_trigger(sensor_poll),
      .de_re(SEM228A_DERE),
      .clk(clk),
      .rstn(resetn),
      .rx(SEM228A_RX),
      .tx(SEM228A_TX),
      .data_raw(irr_d),
      .data_valid(irr_valid_i),
      .frame_error(irr_ferr),
      .dbg_flags(irr_dbg_fl),
      .dbg_rx_cnt(irr_dbg_rxc),
      .dbg_tx_cnt(irr_dbg_tx),
      .dbg_rx0(irr_dbg_rx0)
  );

  rs485_controller #(
      .CLK_FREQ(CLK_FREQ)
  ) sn3000t (
      .tx_trigger(sensor_poll),
      .de_re(SN3000_DERE),
      .clk(clk),
      .rstn(resetn),
      .rx(SN3000_RX),
      .tx(SN3000_TX),
      .data_raw(wind_d),
      .data_valid(wind_valid_i),
      .frame_error(wind_ferr),
      .dbg_flags(wind_dbg_fl),
      .dbg_rx_cnt(wind_dbg_rxc),
      .dbg_tx_cnt(wind_dbg_tx),
      .dbg_rx0(wind_dbg_rx0)
  );

  aht10_driver #(
      .CLK_FREQ (CLK_FREQ),
      .BUS_SPEED(I2C_SPEED)
  ) aht10 (
      .clk(clk),
      .rstn(resetn),
      .scl(SCL_AHT),
      .sda(SDA_AHT),
      .i2c_ack_error(aht_ack_err),
      .temp(temp_d),
      .hum(hum_d)
  );

  ds2331_driver #(
      .CLK_FREQ (CLK_FREQ),
      .BUS_SPEED(I2C_SPEED)
  ) ds2331 (
      .clk(clk),
      .rstn(resetn),
      .scl(SCL_RTC),
      .sda(SDA_RTC),
      .i2c_ack_error(rtc_ack_err),
      .hours(hour_d)
  );

endmodule : axi_sensor_controller


// 1-cycle tick every `ms` milliseconds
module sensor_poll_timer #(
    parameter int CLK_FREQ = 27_000_000
) (
    input  logic        clk,
    input  logic        rstn,
    input  logic [31:0] ms,
    output logic        tick
);

  localparam int CYCLES_MS = CLK_FREQ / 1000;

  logic [$clog2(CYCLES_MS)-1:0] cnt_cycle;
  logic [31:0] cnt_ms;

  always_ff @(posedge clk) begin : ms_counter
    if (!rstn) begin
      cnt_cycle <= '0;
      cnt_ms    <= '0;
      tick      <= 1'b0;
    end else begin
      tick <= 1'b0;
      if (cnt_cycle == CYCLES_MS - 1) begin
        cnt_cycle <= '0;
        if (cnt_ms + 32'd1 >= ms) begin
          cnt_ms <= '0;
          tick   <= 1'b1;
        end else begin
          cnt_ms <= cnt_ms + 32'd1;
        end
      end else begin
        cnt_cycle <= cnt_cycle + 1'b1;
      end
    end
  end

endmodule : sensor_poll_timer


// W-bit register chain
module sync_pipe #(
    parameter int W = 1,
    parameter int STAGES = 3
) (
    input  logic         clk,
    input  logic         rstn,
    input  logic [W-1:0] d,
    output logic [W-1:0] q
);
  logic [W-1:0] r[STAGES];
  always_ff @(posedge clk) begin
    if (!rstn) for (int i = 0; i < STAGES; i++) r[i] <= '0;
    else begin
      r[0] <= d;
      for (int i = 1; i < STAGES; i++) r[i] <= r[i-1];
    end
  end
  assign q = r[STAGES-1];
endmodule : sync_pipe