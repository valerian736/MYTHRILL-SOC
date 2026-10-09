`default_nettype wire
module axil_interconnect #(
    parameter int N = 4
) (
    input  logic [31:0] m_awaddr,
    input  logic        m_awvalid,
    output logic        m_awready,
    input  logic [31:0] m_wdata,
    input  logic [ 3:0] m_wstrb,
    input  logic        m_wvalid,
    output logic        m_wready,
    output logic        m_bvalid,
    input  logic        m_bready,
    input  logic [31:0] m_araddr,
    input  logic        m_arvalid,
    output logic        m_arready,
    output logic [31:0] m_rdata,
    output logic        m_rvalid,
    input  logic        m_rready,

    output logic [N-1:0][31:0] s_awaddr,
    output logic [N-1:0]       s_awvalid,
    input  logic [N-1:0]       s_awready,
    output logic [N-1:0][31:0] s_wdata,
    output logic [N-1:0][ 3:0] s_wstrb,
    output logic [N-1:0]       s_wvalid,
    input  logic [N-1:0]       s_wready,
    input  logic [N-1:0]       s_bvalid,
    output logic [N-1:0]       s_bready,
    output logic [N-1:0][31:0] s_araddr,
    output logic [N-1:0]       s_arvalid,
    input  logic [N-1:0]       s_arready,
    input  logic [N-1:0][31:0] s_rdata,
    input  logic [N-1:0]       s_rvalid,
    output logic [N-1:0]       s_rready
);
  logic [N-1:0] wr_sel;
  logic [N-1:0] rd_sel;
  logic [N:0][31:0] rdata_acc;

  assign rdata_acc[0] = 32'h0;
  generate
    genvar i;
    for (i = 0; i < N; i++) begin : g_slave
      localparam logic [3:0] SEL = 4'(i);

      assign wr_sel[i] = (m_awaddr[31:28] == SEL);
      assign rd_sel[i] = (m_araddr[31:28] == SEL);

      assign s_awaddr[i] = m_awaddr;
      assign s_wdata[i] = m_wdata;
      assign s_wstrb[i] = m_wstrb;
      assign s_awvalid[i] = m_awvalid & wr_sel[i];
      assign s_wvalid[i] = m_wvalid & wr_sel[i];
      assign s_bready[i] = m_bready & wr_sel[i];

      assign s_araddr[i] = m_araddr;
      assign s_arvalid[i] = m_arvalid & rd_sel[i];
      assign s_rready[i] = m_rready & rd_sel[i];

      assign rdata_acc[i+1] = rdata_acc[i] | (rd_sel[i] ? s_rdata[i] : 32'h0);
    end
  endgenerate

  assign m_awready = |(wr_sel & s_awready);
  assign m_wready  = |(wr_sel & s_wready);
  assign m_bvalid  = |(wr_sel & s_bvalid);
  assign m_arready = |(rd_sel & s_arready);
  assign m_rvalid  = |(rd_sel & s_rvalid);
  assign m_rdata   = rdata_acc[N];
endmodule
