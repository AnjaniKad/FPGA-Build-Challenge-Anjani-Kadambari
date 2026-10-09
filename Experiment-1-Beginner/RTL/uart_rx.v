// uart_rx.v
// Receiver: samples rx_sync at bit-center using os_tick (x16 oversampling),
// shifts bits in, checks framing/parity, and hands off a completed byte.
//
// IMPORTANT: os_count is a free-running phase counter across the WHOLE
// frame (start bit through stop bit). It is only reset when a fresh start
// bit is detected from IDLE. It must NOT be reset at intermediate state
// transitions (e.g. start-confirm -> data) -- doing so throws sampling out
// of phase by up to half a bit period and corrupts every subsequent bit.

module uart_rx #(
    parameter OVERSAMPLE = 16,
    parameter DATA_BITS  = 8         // 8 or 9
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx_sync,       // from rx_line_sync
    input  wire       os_tick,       // from baud_nco

    input  wire       parity_en,
    input  wire       parity_odd,    // 1 = odd parity, 0 = even
    input  wire       baud_locked,   // from baud_rate_detector -- RX will not
                                       // attempt to frame/deliver bytes until
                                       // this is asserted (see ST_IDLE below)

    output reg  [DATA_BITS-1:0] rx_byte,
    output reg        rx_byte_valid, // 1-cycle strobe: rx_byte is valid (FIFO write)
    output reg        framing_err,
    output reg        parity_err,
    output reg        frame_good,    // 1-cycle strobe: byte completed with no errors
    output wire       rx_idle,       // high when between frames -- safe point for NCO step updates
    output reg        start_edge     // 1-cycle pulse: the genuine start-bit edge that took us
                                       // out of IDLE (NOT every falling edge -- data bits can
                                       // also fall). Used to phase-sync the NCO to this frame.
);

    assign rx_idle = (state == ST_IDLE);

    localparam ST_IDLE          = 3'd0,
               ST_START_CONFIRM = 3'd1,
               ST_DATA          = 3'd2,
               ST_PARITY        = 3'd3,
               ST_STOP          = 3'd4;

    reg [2:0]  state;
    reg [$clog2(OVERSAMPLE)-1:0] os_count;
    reg [3:0]  bit_index;
    reg [DATA_BITS-1:0] shift_reg;
    reg        parity_calc;
    reg        parity_err_latched;

    localparam [$clog2(OVERSAMPLE)-1:0] MID_SAMPLE = (OVERSAMPLE/2) - 1; // tick 7 of 0..15
    localparam [$clog2(OVERSAMPLE)-1:0] OS_MAX      = OVERSAMPLE - 1;

    wire sample_now = os_tick && (os_count == MID_SAMPLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            os_count            <= 0;
            bit_index           <= 0;
            shift_reg           <= 0;
            parity_calc         <= 1'b0;
            parity_err_latched  <= 1'b0;
            rx_byte             <= 0;
            rx_byte_valid       <= 1'b0;
            framing_err         <= 1'b0;
            parity_err          <= 1'b0;
            frame_good          <= 1'b0;
            start_edge          <= 1'b0;
        end else begin
            rx_byte_valid <= 1'b0;
            frame_good    <= 1'b0;
            framing_err   <= 1'b0;
            parity_err    <= 1'b0;
            start_edge    <= 1'b0;

            // Free-running phase counter, active in every state except IDLE.
            // Wraps modulo OVERSAMPLE and is NEVER force-reset mid-frame.
            if (state != ST_IDLE && os_tick) begin
                os_count <= (os_count == OS_MAX) ? {$clog2(OVERSAMPLE){1'b0}} : os_count + 1'b1;
            end

            case (state)
                // -----------------------------------------------------
                ST_IDLE: begin
                    // Do NOT attempt to frame a byte until the BRD has
                    // genuinely locked. Before lock, the oversample clock's
                    // timing relative to any given edge is not yet
                    // trustworthy, and there is no reliable way to tell a
                    // real start-bit edge apart from an ordinary data-bit
                    // transition (a periodic pattern like a 0x55 preamble
                    // makes every bit transition look identical to a start
                    // bit at the single-edge level). Committing to a frame
                    // on an untrustworthy edge can leave the receiver
                    // permanently misaligned to the wrong byte boundary --
                    // consistently wrong in a way that a periodic preamble
                    // can mask for many bytes before a data-dependent
                    // pattern exposes it. The BRD still receives rx_edge
                    // independently of this FSM's state, so pre-lock
                    // traffic still contributes to acquisition; RX just
                    // doesn't try to frame/deliver it as data.
                    if (baud_locked && rx_sync == 1'b0) begin
                        // candidate start bit -- establish phase zero here,
                        // then wait to confirm at the start bit's midpoint
                        os_count   <= 0;
                        bit_index  <= 0;
                        start_edge <= 1'b1;   // phase-sync the NCO to this edge
                        state      <= ST_START_CONFIRM;
                    end
                end

                // -----------------------------------------------------
                ST_START_CONFIRM: begin
                    if (sample_now) begin
                        if (rx_sync == 1'b0) begin
                            // real start bit confirmed; phase counter keeps
                            // running uninterrupted into the data bits
                            parity_calc <= 1'b0;
                            state       <= ST_DATA;
                        end else begin
                            // glitch, not a real start bit -- abandon frame
                            state <= ST_IDLE;
                        end
                    end
                end

                // -----------------------------------------------------
                ST_DATA: begin
                    if (sample_now) begin
                        shift_reg   <= {rx_sync, shift_reg[DATA_BITS-1:1]};
                        parity_calc <= parity_calc ^ rx_sync;

                        if (bit_index == DATA_BITS - 1) begin
                            state <= parity_en ? ST_PARITY : ST_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end
                end

                // -----------------------------------------------------
                ST_PARITY: begin
                    if (sample_now) begin
                        // parity_odd: total ones (data+parity bit) should be odd
                        parity_err_latched <= parity_odd ? ~(parity_calc ^ rx_sync)
                                                          :  (parity_calc ^ rx_sync);
                        state <= ST_STOP;
                    end
                end

                // -----------------------------------------------------
                ST_STOP: begin
                    if (sample_now) begin
                        rx_byte <= shift_reg;
                        if (rx_sync != 1'b1) begin
                            framing_err   <= 1'b1;
                            rx_byte_valid <= 1'b1; // still deliver byte; consumer/error path decides
                        end else if (parity_en && parity_err_latched) begin
                            parity_err    <= 1'b1;
                            rx_byte_valid <= 1'b1;
                        end else begin
                            rx_byte_valid <= 1'b1;
                            frame_good    <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
