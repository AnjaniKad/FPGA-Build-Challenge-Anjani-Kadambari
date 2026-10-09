// reg_if.v
// Minimal memory-mapped register block (simple sync bus: addr/wdata/we ->
// rdata one cycle later). Wrap with an AXI-lite or Wishbone shim if your
// SoC needs that specific protocol; this keeps the core logic protocol-
// agnostic.
//
// Address map (word-addressed):
//   0x0 CTRL          [0]=parity_en [1]=parity_odd [2]=tx_mirror_en
//   0x1 TX_BAUD_DIV   fallback/fixed TX bit_period when tx_mirror_en=0
//   0x2 RELOCK_THRESH error count threshold before forcing baud relock
//   0x3 DETECTED_BAUD read-only: live bit_period from baud_rate_detector
//   0x4 LOCK_STATUS   read-only: [0]=baud_locked
//   0x5 ERROR_STATUS  read-only: [0]=framing [1]=parity [2]=overrun [15:8]=error_count
//   0x6 FIFO_STATUS   read-only: [0]=rx_full [1]=rx_empty [2]=tx_full [3]=tx_empty

module reg_if #(
    parameter DATA_WIDTH = 20
) (
    input  wire        clk,
    input  wire        rst_n,

    // bus side
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // config out
    output reg          parity_en,
    output reg          parity_odd,
    output reg          tx_mirror_en,
    output reg  [DATA_WIDTH-1:0] tx_baud_div,
    output reg  [7:0]   relock_threshold,

    // status in
    input  wire [DATA_WIDTH-1:0] detected_baud,
    input  wire         baud_locked,
    input  wire         framing_err,
    input  wire         parity_err,
    input  wire         fifo_overrun,
    input  wire [7:0]   error_count,
    input  wire         rx_full, rx_empty, tx_full, tx_empty
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parity_en        <= 1'b0;
            parity_odd       <= 1'b0;
            tx_mirror_en     <= 1'b1;
            tx_baud_div      <= 0;
            relock_threshold <= 8'd8;
        end else if (we) begin
            case (addr)
                4'h0: begin
                    parity_en    <= wdata[0];
                    parity_odd   <= wdata[1];
                    tx_mirror_en <= wdata[2];
                end
                4'h1: tx_baud_div      <= wdata[DATA_WIDTH-1:0];
                4'h2: relock_threshold <= wdata[7:0];
                default: ; // read-only regs, writes ignored
            endcase
        end
    end

    always @(*) begin
        case (addr)
            4'h0: rdata = {29'b0, tx_mirror_en, parity_odd, parity_en};
            4'h1: rdata = {{(32-DATA_WIDTH){1'b0}}, tx_baud_div};
            4'h2: rdata = {24'b0, relock_threshold};
            4'h3: rdata = {{(32-DATA_WIDTH){1'b0}}, detected_baud};
            4'h4: rdata = {31'b0, baud_locked};
            4'h5: rdata = {16'b0, error_count, 5'b0, fifo_overrun, parity_err, framing_err};
            4'h6: rdata = {28'b0, tx_empty, tx_full, rx_empty, rx_full};
            default: rdata = 32'b0;
        endcase
    end

endmodule
