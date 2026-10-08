`default_nettype wire
//   picorv32_axi --(AXI4-Lite)--> axil_interconnect --+--> axil_bram (0x0000_0000)
//                                                     +--> axil_gpio (0x1000_0000)
//                                                     +--> axil_pwm  (0x2000_0000)
//                                                     +--> axil_uart (0x3000_0000)
//                                                     +--> axil_mlp  (0x4000_0000)
//                                                     +--> axi_sensor_controller (0x5000_0000)
//
//   sensors --> (3-stage pipes) --> axil_mlp [scaler + MLP] (direct, no CPU)

module MYTHRILL_SOC #(
    parameter int GPIO_W    = 1,
    parameter int CLK_FREQ  = 27_000_000,
    parameter int UART_BAUD = 115200
) (
    input logic clk,
    input logic reset,  
    output logic trap,
    output logic [GPIO_W-1:0] gpio_out,
    input logic [GPIO_W-1:0] gpio_in,
    output logic pwm_out,
    input logic uart_rx,
    output logic uart_tx,
    input logic SEM228A_RX,
    output logic SEM228A_TX,
    output logic SEM228A_DERE,
    input logic SN3000_RX,
    output logic SN3000_TX,
    output logic SN3000_DERE,
    inout wire SCL_AHT,
    inout wire SDA_AHT,
    inout wire SCL_RTC,
    inout wire SDA_RTC
);
  localparam int NS = 6;
  localparam int S_BRAM = 0;
  localparam int S_GPIO = 1;
  localparam int S_PWM = 2;
  localparam int S_UART = 3;
  localparam int S_MLP = 4;
  localparam int S_SENS = 5;

  // ---------- reset ----------

  logic resetn;
  reset_top rst_top (
      clk,
      reset,
      resetn
  );

  // ---------- CPU master bus ----------
  logic m_awvalid, m_awready;
  logic [31:0] m_awaddr;
  logic [ 2:0] m_awprot;
  logic m_wvalid, m_wready;
  logic [31:0] m_wdata;
  logic [ 3:0] m_wstrb;
  logic m_bvalid, m_bready;
  logic m_arvalid, m_arready;
  logic [31:0] m_araddr;
  logic [ 2:0] m_arprot;
  logic m_rvalid, m_rready;
  logic [31:0] m_rdata;

  // ---------- slave buses, index = slave number ----------
  logic [NS-1:0][31:0] s_awaddr, s_wdata, s_araddr, s_rdata;
  logic [NS-1:0][3:0] s_wstrb;
  logic [NS-1:0] s_awvalid, s_awready, s_wvalid, s_wready;
  logic [NS-1:0] s_bvalid, s_bready;
  logic [NS-1:0] s_arvalid, s_arready, s_rvalid, s_rready;

  // ---------- CPU ----------
  picorv32_axi #(
      .PROGADDR_RESET (32'h0000_0000),  // boot from BRAM
      .STACKADDR      (32'h0000_1000),  // top of 4 KB BRAM
      .ENABLE_COUNTERS(1),
      .ENABLE_MUL     (1),
      .ENABLE_DIV     (1),
      .COMPRESSED_ISA (1),
      .BARREL_SHIFTER (1)
  ) cpu (
      .clk   (clk),
      .resetn(resetn),
      .trap  (trap),

      .mem_axi_awvalid(m_awvalid),
      .mem_axi_awready(m_awready),
      .mem_axi_awaddr (m_awaddr),
      .mem_axi_awprot (m_awprot),

      .mem_axi_wvalid(m_wvalid),
      .mem_axi_wready(m_wready),
      .mem_axi_wdata (m_wdata),
      .mem_axi_wstrb (m_wstrb),

      .mem_axi_bvalid(m_bvalid),
      .mem_axi_bready(m_bready),

      .mem_axi_arvalid(m_arvalid),
      .mem_axi_arready(m_arready),
      .mem_axi_araddr (m_araddr),
      .mem_axi_arprot (m_arprot),

      .mem_axi_rvalid(m_rvalid),
      .mem_axi_rready(m_rready),
      .mem_axi_rdata (m_rdata),

      // unused: tie inputs low, leave outputs open
      .pcpi_wr   (1'b0),
      .pcpi_rd   (32'b0),
      .pcpi_wait (1'b0),
      .pcpi_ready(1'b0),
      .irq       (32'b0)
  );

  // ---------- interconnect ----------
  axil_interconnect #(
      .N(NS)
  ) xbar (
      .m_awaddr (m_awaddr),
      .m_awvalid(m_awvalid),
      .m_awready(m_awready),
      .m_wdata  (m_wdata),
      .m_wstrb  (m_wstrb),
      .m_wvalid (m_wvalid),
      .m_wready (m_wready),
      .m_bvalid (m_bvalid),
      .m_bready (m_bready),
      .m_araddr (m_araddr),
      .m_arvalid(m_arvalid),
      .m_arready(m_arready),
      .m_rdata  (m_rdata),
      .m_rvalid (m_rvalid),
      .m_rready (m_rready),

      .s_awaddr (s_awaddr),
      .s_awvalid(s_awvalid),
      .s_awready(s_awready),
      .s_wdata  (s_wdata),
      .s_wstrb  (s_wstrb),
      .s_wvalid (s_wvalid),
      .s_wready (s_wready),
      .s_bvalid (s_bvalid),
      .s_bready (s_bready),
      .s_araddr (s_araddr),
      .s_arvalid(s_arvalid),
      .s_arready(s_arready),
      .s_rdata  (s_rdata),
      .s_rvalid (s_rvalid),
      .s_rready (s_rready)
  );

  // ---------- slave 0: BRAM ----------
  axil_bram #(
      .WORDS(1024),
      .INIT ("firmware.hex")
  ) bram (
      .clk(clk),
      .resetn(resetn),
      .awaddr(s_awaddr[S_BRAM]),
      .awvalid(s_awvalid[S_BRAM]),
      .awready(s_awready[S_BRAM]),
      .wdata(s_wdata[S_BRAM]),
      .wstrb(s_wstrb[S_BRAM]),
      .wvalid(s_wvalid[S_BRAM]),
      .wready(s_wready[S_BRAM]),
      .bvalid(s_bvalid[S_BRAM]),
      .bready(s_bready[S_BRAM]),
      .araddr(s_araddr[S_BRAM]),
      .arvalid(s_arvalid[S_BRAM]),
      .arready(s_arready[S_BRAM]),
      .rdata(s_rdata[S_BRAM]),
      .rvalid(s_rvalid[S_BRAM]),
      .rready(s_rready[S_BRAM])
  );

  // ---------- slave 1: GPIO ----------
  axil_gpio #(
      .GPIO_W(GPIO_W)
  ) gpio (
      .clk(clk),
      .resetn(resetn),
      .awaddr(s_awaddr[S_GPIO]),
      .awvalid(s_awvalid[S_GPIO]),
      .awready(s_awready[S_GPIO]),
      .wdata(s_wdata[S_GPIO]),
      .wstrb(s_wstrb[S_GPIO]),
      .wvalid(s_wvalid[S_GPIO]),
      .wready(s_wready[S_GPIO]),
      .bvalid(s_bvalid[S_GPIO]),
      .bready(s_bready[S_GPIO]),
      .araddr(s_araddr[S_GPIO]),
      .arvalid(s_arvalid[S_GPIO]),
      .arready(s_arready[S_GPIO]),
      .rdata(s_rdata[S_GPIO]),
      .rvalid(s_rvalid[S_GPIO]),
      .rready(s_rready[S_GPIO]),
      .gpio_out(gpio_out),
      .gpio_in(gpio_in)
  );

  // ---------- slave 2: PWM ----------
  axil_pwm pwm (
      .clk(clk),
      .resetn(resetn),
      .awaddr(s_awaddr[S_PWM]),
      .awvalid(s_awvalid[S_PWM]),
      .awready(s_awready[S_PWM]),
      .wdata(s_wdata[S_PWM]),
      .wstrb(s_wstrb[S_PWM]),
      .wvalid(s_wvalid[S_PWM]),
      .wready(s_wready[S_PWM]),
      .bvalid(s_bvalid[S_PWM]),
      .bready(s_bready[S_PWM]),
      .araddr(s_araddr[S_PWM]),
      .arvalid(s_arvalid[S_PWM]),
      .arready(s_arready[S_PWM]),
      .rdata(s_rdata[S_PWM]),
      .rvalid(s_rvalid[S_PWM]),
      .rready(s_rready[S_PWM]),
      .pwm_out(pwm_out)
  );

  // ---------- slave 3: UART ----------
  axil_uart #(
      .BAUD_RATE(UART_BAUD),
      .CLK_FREQ (CLK_FREQ)
  ) debug_host (
      .clk(clk),
      .resetn(resetn),
      .awaddr(s_awaddr[S_UART]),
      .awvalid(s_awvalid[S_UART]),
      .awready(s_awready[S_UART]),
      .wdata(s_wdata[S_UART]),
      .wstrb(s_wstrb[S_UART]),
      .wvalid(s_wvalid[S_UART]),
      .wready(s_wready[S_UART]),
      .bvalid(s_bvalid[S_UART]),
      .bready(s_bready[S_UART]),
      .araddr(s_araddr[S_UART]),
      .arvalid(s_arvalid[S_UART]),
      .arready(s_arready[S_UART]),
      .rdata(s_rdata[S_UART]),
      .rvalid(s_rvalid[S_UART]),
      .rready(s_rready[S_UART]),
      .rx(uart_rx),
      .tx(uart_tx)
  );

  // ---------- sensor -> MLP direct path ----------
  logic [19:0] temp_raw, hum_raw;
  logic [15:0] irr_raw, wind_raw;
  logic [7:0] hour_raw;
  logic irr_valid, wind_valid;

  // ---------- slave 4: MLP ----------
  axil_mlp mlp (
      .clk(clk),
      .resetn(resetn),
      .awaddr(s_awaddr[S_MLP]),
      .awvalid(s_awvalid[S_MLP]),
      .awready(s_awready[S_MLP]),
      .wdata(s_wdata[S_MLP]),
      .wstrb(s_wstrb[S_MLP]),
      .wvalid(s_wvalid[S_MLP]),
      .wready(s_wready[S_MLP]),
      .bvalid(s_bvalid[S_MLP]),
      .bready(s_bready[S_MLP]),
      .araddr(s_araddr[S_MLP]),
      .arvalid(s_arvalid[S_MLP]),
      .arready(s_arready[S_MLP]),
      .rdata(s_rdata[S_MLP]),
      .rvalid(s_rvalid[S_MLP]),
      .rready(s_rready[S_MLP]),
      .temp_raw(temp_raw),
      .hum_raw(hum_raw),
      .irr_raw(irr_raw),
      .wind_raw(wind_raw),
      .hour_bcd(hour_raw),
      .irr_valid(irr_valid),
      .wind_valid(wind_valid)
  );

  // ---------- slave 5: sensors ----------
  axi_sensor_controller #(
      .CLK_FREQ(CLK_FREQ)
  ) sensors (
      .clk(clk),
      .resetn(resetn),
      .awaddr(s_awaddr[S_SENS]),
      .awvalid(s_awvalid[S_SENS]),
      .awready(s_awready[S_SENS]),
      .wdata(s_wdata[S_SENS]),
      .wstrb(s_wstrb[S_SENS]),
      .wvalid(s_wvalid[S_SENS]),
      .wready(s_wready[S_SENS]),
      .bvalid(s_bvalid[S_SENS]),
      .bready(s_bready[S_SENS]),
      .araddr(s_araddr[S_SENS]),
      .arvalid(s_arvalid[S_SENS]),
      .arready(s_arready[S_SENS]),
      .rdata(s_rdata[S_SENS]),
      .rvalid(s_rvalid[S_SENS]),
      .rready(s_rready[S_SENS]),
      .SEM228A_RX(SEM228A_RX),
      .SEM228A_TX(SEM228A_TX),
      .SEM228A_DERE(SEM228A_DERE),
      .SN3000_RX(SN3000_RX),
      .SN3000_TX(SN3000_TX),
      .SN3000_DERE(SN3000_DERE),
      .SCL_AHT(SCL_AHT),
      .SDA_AHT(SDA_AHT),
      .SCL_RTC(SCL_RTC),
      .SDA_RTC(SDA_RTC),
      .temp_raw(temp_raw),
      .hum_raw(hum_raw),
      .irr_raw(irr_raw),
      .wind_raw(wind_raw),
      .hour_raw(hour_raw),
      .irr_valid(irr_valid),
      .wind_valid(wind_valid)
  );
endmodule
