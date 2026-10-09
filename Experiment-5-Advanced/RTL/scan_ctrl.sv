// -----------------------------------------------------------------------------
// scan_ctrl.sv
// Stage 0 (scan chain diagnosis) + the shift/apply/capture/compare sequencer,
// per RTL_ARCHITECTURE.md 3.3. Per PROJECT_CONTEXT.md, Stage 0 runs first,
// always -- a broken chain makes every downstream observation garbage.
//
// KNOWN SIMPLIFICATIONS vs. the full production spec (stated explicitly,
// per this project's own documentation discipline):
//   - Shift-out is NOT overlapped with the next shift-in yet. The full spec
//     calls for overlap once lfsr_prpg/mem_arbiter exist to actually feed a
//     back-to-back pattern stream; there is nothing to overlap with until
//     then, so this is deferred rather than built against nothing.
//   - Golden/pattern data is supplied directly over `shift_in_bits` /
//     `golden_bits` by whatever sits above this module (a testbench today,
//     the DDR prefetch FIFO once mem_arbiter exists) rather than through the
//     real CSR/Avalon-MM register map -- that map isn't built yet.
//   - The serial fail-log (fail_chain_id/fail_cell_index) can only name ONE
//     chain per cycle -- the lowest-numbered mismatching one. The complete
//     per-cycle mismatch set is available separately as `fail_vec`, which
//     is what Stage 1 consumes. A real fail-log FIFO accepting up to
//     NUM_CHAINS entries per cycle is a TODO for when mem_arbiter exists.
//   - `two_pattern_mode` now models the STRUCTURAL two-edge launch-on-capture
//     sequence (shift V1 -> S_LAUNCH -> S_CAPTURE), which is what actually
//     lets a transition fault be excited at all (see tb for the before/after
//     result). What's still not modeled: both edges run on this module's
//     single `clk` -- the real at-speed capture clock needs the
//     clk_sys/clk_cap mux via an ALTCLKCTRL primitive (RTL_ARCHITECTURE.md
//     2), and this simulation has zero gate delay, so there is no sense in
//     which the capture edge is genuinely "at speed" relative to a real
//     propagation delay -- it only proves the right NUMBER of edges happen
//     in the right order, not that a fast capture clock would catch a fault
//     a slow one wouldn't.
// -----------------------------------------------------------------------------
module scan_ctrl #(
    parameter int NUM_CHAINS = 2,
    parameter int CHAIN_LEN  = 8
)(
    input  logic clk,
    input  logic rst_n,

    // control
    input  logic        start,           // pulse: begin one run
    input  logic        chain_test_mode, // 1 = Stage 0 flush test, 0 = normal pattern flow
    input  logic        two_pattern_mode,// 1 = real launch-on-capture (V1 shift -> launch -> capture),
                                          // 0 = original single-capture flow (unchanged, default)
    input  logic [19:0] pattern_id,      // tag for fail-log entries (normal mode)
    output logic        busy,
    output logic         done,

    // normal-mode pattern/golden streaming (bit-serial, one bit/chain/cycle).
    // `shift_index` tells the driver which position in the pattern to present.
    output logic [$clog2(CHAIN_LEN)-1:0] shift_index,
    input  logic [NUM_CHAINS-1:0]        shift_in_bits,
    input  logic [NUM_CHAINS-1:0]        golden_bits,

    // fail log (drain fail_valid / fields every cycle it's high)
    output logic                          fail_valid,
    output logic [19:0]                   fail_pattern_id,
    output logic [$clog2(NUM_CHAINS)-1:0] fail_chain_id,
    output logic [$clog2(CHAIN_LEN)-1:0]  fail_cell_index,
    output logic [NUM_CHAINS-1:0]         fail_vec,  // all chains mismatching this cycle (nonzero iff fail_valid)

    // Stage 0 results (valid once `done` pulses after a chain_test_mode run)
    output logic [NUM_CHAINS-1:0]                    chain_ok,
    output logic [NUM_CHAINS*$clog2(CHAIN_LEN)-1:0]  chain_first_bad_cell_flat,

    // DUT scan interface
    output logic                  scan_en,
    output logic                  launch_pulse,  // 1 cycle, two_pattern_mode only: the V1->V2
                                                  // launch edge (comes before capture_pulse)
    output logic                  capture_pulse, // 1 cycle: dut applies functional next-state --
                                                  // in two_pattern_mode, this is the REAL at-speed
                                                  // capture edge, one cycle after launch_pulse
    output logic [NUM_CHAINS-1:0] scan_in,
    input  logic [NUM_CHAINS-1:0] scan_out
);

    localparam int IDX_W = (CHAIN_LEN <= 1) ? 1 : $clog2(CHAIN_LEN);

    typedef enum logic [2:0] {
        S_IDLE, S_SHIFT_IN, S_LAUNCH, S_CAPTURE, S_SHIFT_OUT, S_DONE
    } state_t;

    state_t state;
    logic [IDX_W-1:0] cyc;               // 0 .. CHAIN_LEN-1 within current phase
    logic [IDX_W+1:0] chain_cyc;         // 0 .. 2*CHAIN_LEN, chain-test only

    // Stage 0 repeating-0011 generator: bit(k) = k[1]
    function automatic logic pat0011(input logic [IDX_W+1:0] k);
        pat0011 = k[1];
    endfunction

    logic [NUM_CHAINS-1:0]                   chain_ok_r;
    logic [NUM_CHAINS*IDX_W-1:0]              chain_bad_r;
    logic [NUM_CHAINS-1:0]                   chain_found_bad; // latched: already recorded a failure this run

    assign shift_index               = cyc;
    assign chain_ok                  = chain_ok_r;
    assign chain_first_bad_cell_flat = chain_bad_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            cyc             <= '0;
            chain_cyc       <= '0;
            scan_en         <= 1'b0;
            launch_pulse    <= 1'b0;
            capture_pulse   <= 1'b0;
            scan_in         <= '0;
            fail_valid      <= 1'b0;
            fail_pattern_id <= '0;
            fail_chain_id   <= '0;
            fail_cell_index <= '0;
            fail_vec        <= '0;
            chain_ok_r      <= '1;
            chain_bad_r     <= '0;
            chain_found_bad <= '0;
        end else begin
            // defaults: these are pulses unless a branch below re-asserts them
            done          <= 1'b0;
            launch_pulse  <= 1'b0;
            capture_pulse <= 1'b0;
            fail_valid    <= 1'b0;
            fail_vec      <= '0;

            unique case (state)

                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy            <= 1'b1;
                        cyc             <= '0;
                        chain_cyc       <= '0;
                        chain_ok_r      <= '1;
                        chain_bad_r     <= '0;
                        chain_found_bad <= '0;
                        scan_en         <= 1'b1; // assert NOW, not one cycle into S_SHIFT_IN --
                                                  // otherwise the first shift-in cycle is silently
                                                  // a functional cycle instead, and the chain only
                                                  // gets CHAIN_LEN-1 real shifts.
                        state           <= S_SHIFT_IN;
                    end
                end

                // ---------------------------------------------------------
                // Stage 0: self-contained chain flush test. Shifts a 0011
                // generator pattern in for CHAIN_LEN cycles, then continues
                // shifting for another CHAIN_LEN cycles while comparing
                // scan_out against the same generator delayed by CHAIN_LEN
                // cycles -- a healthy chain is a pure CHAIN_LEN-deep shift
                // register, so this delayed-self-compare needs no external
                // golden data at all.
                // ---------------------------------------------------------
                S_SHIFT_IN: begin
                    if (chain_test_mode) begin
                        scan_en <= 1'b1;
                        scan_in <= {NUM_CHAINS{pat0011(chain_cyc)}};

                        // Latency from the chain_cyc index used to drive
                        // scan_in to that same bit appearing at scan_out is
                        // CHAIN_LEN (shift-register depth) + 1 (scan_in is
                        // itself a registered output, one more cycle before
                        // the bit it encodes even enters the chain). This is
                        // independent of the S_IDLE scan_en timing fix above
                        // (verified directly against a signal trace, not
                        // assumed -- the chain-test's repeating 0011 pattern
                        // has period 4, which made an earlier CHAIN_LEN-only
                        // guess look right for some samples and silently
                        // wrong for others).
                        if (chain_cyc >= CHAIN_LEN + 1) begin
                            for (int c = 0; c < NUM_CHAINS; c++) begin
                                if (!chain_found_bad[c] &&
                                    scan_out[c] != pat0011(chain_cyc - CHAIN_LEN - 1)) begin
                                    chain_ok_r[c]                          <= 1'b0;
                                    chain_bad_r[c*IDX_W +: IDX_W]          <= (chain_cyc - CHAIN_LEN - 1);
                                    chain_found_bad[c]                     <= 1'b1;
                                end
                            end
                        end

                        if (chain_cyc == 2*CHAIN_LEN) begin
                            scan_en <= 1'b0;
                            state   <= S_DONE;
                        end else begin
                            chain_cyc <= chain_cyc + 1'b1;
                        end
                    end else begin
                        // Normal mode: load one pattern (this is V1, the
                        // initialization vector, when two_pattern_mode=1).
                        scan_en <= 1'b1;
                        scan_in <= shift_in_bits;
                        if (cyc == CHAIN_LEN - 1) begin
                            scan_en <= 1'b0;
                            cyc     <= '0;
                            state   <= two_pattern_mode ? S_LAUNCH : S_CAPTURE;
                        end else begin
                            cyc <= cyc + 1'b1;
                        end
                    end
                end

                // Only entered when two_pattern_mode=1. This is the V1->V2
                // launch edge: the DUT's own combinational function of the
                // scanned-in V1 state computes a new value -- for any net
                // whose V1 and post-launch values differ, this is a genuine
                // transition, not just a static value. The very next edge
                // (S_CAPTURE) is what actually tests whether that transition
                // "completed" -- which is the point of the whole two-vector
                // scheme: fi_cell's transition fault model can only produce
                // an observable effect when the targeted net actually
                // changes value between these two specific edges, not just
                // at some undefined earlier point.
                S_LAUNCH: begin
                    launch_pulse <= 1'b1;
                    state        <= S_CAPTURE;
                end

                S_CAPTURE: begin
                    // One functional cycle: dut_wrapper (outside this module)
                    // must hold PI stable this cycle for a valid launch/capture.
                    // In two_pattern_mode, this is the real capture edge,
                    // immediately following S_LAUNCH.
                    capture_pulse <= 1'b1;
                    // Assert scan_en NOW, at the same edge that performs the
                    // capture (which itself still sees the old scan_en=0 and
                    // so captures functionally). Without this, scan_en stays
                    // 0 through the first S_SHIFT_OUT cycle and the DUT runs
                    // an unintended SECOND functional edge there instead of
                    // shifting -- the shift-out stream was then a mix of two
                    // different circuit states and cell 0 of every chain was
                    // never observed. (Found while building Stage 1: a
                    // trace showed q changing between the first two
                    // shift-out cycles in a way no shift could produce.)
                    scan_en       <= 1'b1;
                    state         <= S_SHIFT_OUT;
                end

                S_SHIFT_OUT: begin
                    scan_en <= 1'b1;
                    scan_in <= '0; // no next pattern preloaded (see header: non-overlapped)

                    // fail_vec: the COMPLETE set of chains that mismatch this
                    // cycle, aligned with fail_valid, so a consumer that needs
                    // every failing cell (Stage 1) never loses any. The serial
                    // fail_chain_id/fail_cell_index fields below can still only
                    // name ONE chain per cycle, and it is the lowest-numbered
                    // one (iterating high-to-low so the last write wins).
                    // The earlier version of this loop tested `!fail_valid`
                    // inside the loop, but that reads the REGISTERED output's
                    // old value (always 0 mid-cycle), so the highest chain
                    // silently won while the comment claimed the lowest.
                    fail_vec <= scan_out ^ golden_bits;
                    if (scan_out != golden_bits) begin
                        fail_valid      <= 1'b1;
                        fail_pattern_id <= pattern_id;
                        fail_cell_index <= cyc;
                        for (int c = NUM_CHAINS - 1; c >= 0; c--) begin
                            if (scan_out[c] != golden_bits[c])
                                fail_chain_id <= c[$clog2(NUM_CHAINS)-1:0];
                        end
                    end

                    if (cyc == CHAIN_LEN - 1) begin
                        scan_en <= 1'b0;
                        state   <= S_DONE;
                    end else begin
                        cyc <= cyc + 1'b1;
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
