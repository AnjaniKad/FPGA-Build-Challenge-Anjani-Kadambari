// uart_top.v
// Self-correcting UART core: wires together the line synchronizer, baud
// rate detector, adaptive baud generator (NCO), RX/TX FSMs, error/relock
// controller, FIFOs, and the register interface.

module uart_top #(
    parameter CNT_WIDTH  = 20,
    parameter DATA_BITS  = 8,
    parameter FIFO_DEPTH = 16
) (
    input  wire       clk,
    input  wire       rst_n,

    // serial pins
    input  wire       rx_line,
    output wire        tx_line,

    // register bus (simple sync bus, see reg_if.v)
    input  wire [3:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire        reg_we,
    output wire [31:0] reg_rdata,

    // parallel RX side (consumer)
    output wire [DATA_BITS-1:0] rx_data,
    output wire        rx_valid,
    input  wire        rx_ready,

    // parallel TX side (producer)
    input  wire [DATA_BITS-1:0] tx_data,
    input  wire        tx_valid,
    output wire         tx_ready,

    output wire         baud_locked_o,
    output wire         error_flag_o
);

    // ---------------- line sync ----------------
    wire rx_sync, rx_edge, rx_fall;
    rx_line_sync u_sync (
        .clk(clk), .rst_n(rst_n), .rx_line(rx_line),
        .rx_sync(rx_sync), .rx_edge(rx_edge), .rx_fall(rx_fall), .rx_rise()
    );

    // ---------------- config/status wires ----------------
    wire parity_en, parity_odd, tx_mirror_en;
    wire [CNT_WIDTH-1:0] tx_baud_div;
    wire [7:0] relock_threshold;
    wire [CNT_WIDTH-1:0] detected_baud;
    wire baud_locked;
    wire framing_err, parity_err, fifo_overrun_rx;
    wire [7:0] error_count;
    wire rx_full, rx_empty, tx_full, tx_empty;

    assign baud_locked_o = baud_locked;

    // ---------------- baud rate detector ----------------
    wire relock_req;
    wire frame_good;
    wire [CNT_WIDTH-1:0] bit_period;
    wire bit_period_valid;

    baud_rate_detector #(.CNT_WIDTH(CNT_WIDTH)) u_brd (
        .clk(clk), .rst_n(rst_n),
        .rx_edge(rx_edge), .frame_good(frame_good), .relock_req(relock_req),
        .bit_period(bit_period), .bit_period_valid(bit_period_valid),
        .baud_locked(baud_locked)
    );

    assign detected_baud = bit_period;

    // ---------------- adaptive baud generator (RX side) ----------------
    // update_en is gated by rx_idle so a mid-frame relock/correction never
    // shifts the sampling phase out from under a byte that's already being
    // received -- new estimates only take effect between frames.
    wire os_tick, bit_tick_rx, rx_idle, start_edge;
    baud_nco #(.CNT_WIDTH(CNT_WIDTH)) u_nco_rx (
        .clk(clk), .rst_n(rst_n),
        .bit_period(bit_period), .bit_period_valid(bit_period_valid),
        .update_en(rx_idle), .phase_sync(start_edge),
        .os_tick(os_tick), .bit_tick(bit_tick_rx)
    );

    // ---------------- TX baud source: mirror vs fixed ----------------
    // TX doesn't need oversampling, just one tick per bit period, so it gets
    // its own plain divider rather than sharing the RX NCO's phase logic.
    //
    // Mirror mode needs a bootstrap value: bit_period is 0 until the BRD
    // has locked onto something, and TX can't wait for that if it's the
    // only thing generating edges for the BRD to lock onto in the first
    // place. So: use the fixed TX_BAUD_DIV until baud_locked, then switch
    // to mirroring the live detected rate.
    //
    // IMPORTANT: tx_period_sel is latched into tx_period_active only while
    // TX is idle between frames. Feeding the live combinational mux
    // straight into the tick generator would let a baud_locked transition
    // (or any bit_period update) change the bit width mid-transmission,
    // physically corrupting the waveform on the wire -- the TX-side analog
    // of the mid-frame NCO update bug already fixed on the RX side.
    wire [CNT_WIDTH-1:0] tx_period_sel = (tx_mirror_en && baud_locked) ? bit_period : tx_baud_div;
    reg  [CNT_WIDTH-1:0] tx_period_active;
    wire tx_busy_w;
    wire bit_tick_tx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_period_active <= 0;
        else if (!tx_busy_w)
            tx_period_active <= tx_period_sel;
    end

    tx_bit_tick_gen #(.CNT_WIDTH(CNT_WIDTH)) u_tx_tick (
        .clk(clk), .rst_n(rst_n),
        .bit_period(tx_period_active),
        .bit_tick(bit_tick_tx)
    );

    // ---------------- RX FSM ----------------
    wire [DATA_BITS-1:0] rx_byte;
    wire rx_byte_valid;

    uart_rx #(.DATA_BITS(DATA_BITS)) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx_sync(rx_sync), .os_tick(os_tick),
        .parity_en(parity_en), .parity_odd(parity_odd), .baud_locked(baud_locked),
        .rx_byte(rx_byte), .rx_byte_valid(rx_byte_valid),
        .framing_err(framing_err), .parity_err(parity_err),
        .frame_good(frame_good), .rx_idle(rx_idle), .start_edge(start_edge)
    );

    // ---------------- RX FIFO ----------------
    sync_fifo #(.WIDTH(DATA_BITS), .DEPTH(FIFO_DEPTH)) u_rx_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx_byte_valid), .wr_data(rx_byte), .full(rx_full), .overrun(fifo_overrun_rx),
        .rd_en(rx_ready), .rd_data(rx_data), .empty(rx_empty)
    );
    assign rx_valid = !rx_empty;

    // ---------------- TX FIFO ----------------
    wire [DATA_BITS-1:0] tx_byte;
    wire tx_byte_valid_fifo, tx_byte_ack;
    wire tx_fifo_overrun;

    sync_fifo #(.WIDTH(DATA_BITS), .DEPTH(FIFO_DEPTH)) u_tx_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(tx_valid), .wr_data(tx_data), .full(tx_full), .overrun(tx_fifo_overrun),
        .rd_en(tx_byte_ack), .rd_data(tx_byte), .empty(tx_empty)
    );
    assign tx_ready = !tx_full;
    assign tx_byte_valid_fifo = !tx_empty;

    // ---------------- TX FSM ----------------
    uart_tx #(.DATA_BITS(DATA_BITS)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_byte(tx_byte), .tx_byte_valid(tx_byte_valid_fifo), .tx_byte_ack(tx_byte_ack),
        .bit_tick(bit_tick_tx),
        .parity_en(parity_en), .parity_odd(parity_odd),
        .tx_line(tx_line), .tx_busy(tx_busy_w)
    );

    // ---------------- error / recal controller ----------------
    error_controller u_err (
        .clk(clk), .rst_n(rst_n),
        .framing_err(framing_err), .parity_err(parity_err), .fifo_overrun(fifo_overrun_rx),
        .relock_threshold(relock_threshold), .frame_good(frame_good),
        .relock_req(relock_req), .error_flag(error_flag_o), .error_count(error_count)
    );

    // ---------------- register interface ----------------
    reg_if #(.DATA_WIDTH(CNT_WIDTH)) u_regs (
        .clk(clk), .rst_n(rst_n),
        .addr(reg_addr), .wdata(reg_wdata), .we(reg_we), .rdata(reg_rdata),
        .parity_en(parity_en), .parity_odd(parity_odd), .tx_mirror_en(tx_mirror_en),
        .tx_baud_div(tx_baud_div), .relock_threshold(relock_threshold),
        .detected_baud(detected_baud), .baud_locked(baud_locked),
        .framing_err(framing_err), .parity_err(parity_err), .fifo_overrun(fifo_overrun_rx),
        .error_count(error_count),
        .rx_full(rx_full), .rx_empty(rx_empty), .tx_full(tx_full), .tx_empty(tx_empty)
    );

endmodule
