// baud_rate_detector.v
// Auto-baud detector. Method: track the minimum interval between consecutive
// edges on rx_sync over a window of edges. The minimum edge-to-edge interval
// across a real byte approximates one bit period (1 UI), since some bit
// transition is guaranteed to occur at least once every byte for typical
// data patterns (and reliably so across multiple bytes).
//
// The window is re-armed continuously, so a change in the far-end's baud
// rate is picked up within a window's worth of traffic -- this is the
// "real-time" / self-correcting property.

module baud_rate_detector #(
    parameter CNT_WIDTH      = 20,  // covers slow baud rates at fast clk
    parameter WINDOW_EDGES   = 8,   // edges collected before latching a candidate
    parameter LOCK_THRESHOLD = 4,   // consecutive agreeing windows to declare lock
    parameter TOL_SHIFT      = 5    // tolerance = period >> TOL_SHIFT  (~3%)
) (
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   rx_edge,       // from rx_line_sync
    input  wire                   frame_good,    // from RX FSM: byte framed with no errors
    input  wire                   relock_req,    // from error controller

    output reg  [CNT_WIDTH-1:0]   bit_period,        // filtered, current best estimate
    output reg                    bit_period_valid,  // 1-cycle pulse: bit_period updated
    output reg                    baud_locked
);

    // Free-running counter between edges
    reg [CNT_WIDTH-1:0] edge_cnt;
    reg [CNT_WIDTH-1:0] min_interval;
    reg [$clog2(WINDOW_EDGES+1)-1:0] edge_num;

    reg [CNT_WIDTH-1:0] candidate;
    reg                 candidate_valid;

    reg [3:0] lock_counter;

    // Glitch floor: ignore intervals shorter than this many clk cycles
    localparam [CNT_WIDTH-1:0] MIN_VALID_INTERVAL = 4;

    // ---------------------------------------------------------------
    // Edge-interval timing + per-window minimum tracking
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_cnt        <= 0;
            min_interval    <= {CNT_WIDTH{1'b1}};
            edge_num        <= 0;
            candidate       <= 0;
            candidate_valid <= 1'b0;
        end else begin
            candidate_valid <= 1'b0;
            edge_cnt        <= edge_cnt + 1'b1;

            if (rx_edge) begin
                if (edge_cnt >= MIN_VALID_INTERVAL) begin
                    if (edge_cnt < min_interval)
                        min_interval <= edge_cnt;

                    edge_num <= edge_num + 1'b1;
                    if (edge_num + 1'b1 >= WINDOW_EDGES) begin
                        // Window complete: latch this window's minimum as a candidate
                        candidate       <= min_interval;
                        candidate_valid <= 1'b1;
                        min_interval    <= {CNT_WIDTH{1'b1}};
                        edge_num        <= 0;
                    end
                end
                edge_cnt <= 0;
            end
        end
    end

    // ---------------------------------------------------------------
    // Filter: compare each new candidate to the current bit_period.
    // Agreement within tolerance -> average in, bump lock_counter.
    // Disagreement -> reset lock_counter (treat as noise or real rate change).
    // ---------------------------------------------------------------
    wire [CNT_WIDTH-1:0] tol        = bit_period >> TOL_SHIFT;
    wire [CNT_WIDTH-1:0] diff       = (candidate > bit_period) ?
                                        (candidate - bit_period) : (bit_period - candidate);
    wire                 first_est  = (bit_period == 0);
    wire                 agrees     = first_est || (diff <= tol);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_period       <= 0;
            bit_period_valid <= 1'b0;
            baud_locked      <= 1'b0;
            lock_counter     <= 0;
        end else begin
            bit_period_valid <= 1'b0;

            if (relock_req) begin
                bit_period   <= 0;
                baud_locked  <= 1'b0;
                lock_counter <= 0;
            end else if (candidate_valid) begin
                if (agrees) begin
                    // simple IIR-style average: nudge toward the new candidate
                    bit_period       <= first_est ? candidate
                                                   : (bit_period + candidate) >> 1;
                    bit_period_valid <= 1'b1;
                    if (lock_counter < LOCK_THRESHOLD)
                        lock_counter <= lock_counter + 1'b1;
                    else
                        baud_locked <= 1'b1;
                end else begin
                    // disagreement: could be noise or genuine rate change.
                    // Restart acquisition on this new candidate rather than
                    // keep averaging against a stale estimate.
                    bit_period   <= candidate;
                    lock_counter <= 0;
                    baud_locked  <= 1'b0;
                end
            end

            // Optional: frame_good can be used by an outer supervisor to
            // corroborate lock quality; not required for core lock logic here.
        end
    end

endmodule
