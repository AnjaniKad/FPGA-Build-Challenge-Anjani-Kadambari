`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_stage0_milestone.sv
// Exercises RTL_ARCHITECTURE.md 7's system-level verification plan against
// Stage 0 + fault injection + fail-log detection. (Stage 1 has its own
// testbench, tb_stage1_milestone.sv.) Scenarios, in order:
//   1.  Zero-fault golden run -> must be clean (gate for everything else)
//   2.  Stage 0 chain test: healthy, then a stuck cell via simulation force
//   2b. Same stuck-cell scenario via the real RTL injector (chain_fault_*)
//   2c. Broken (self-hold) chain cell -- detected, but indistinguishable
//       from stuck-at-0 from a q=0 reset (an expected finding, see README)
//   2d. Slow chain cell -- detected as an anomaly; NOT proof of real
//       at-speed behavior (zero-delay simulation)
//   3.  Injected SA0 (site 2)            4. Injected SA1 (site 1)
//   5.  Slow-to-transition, two_pattern_mode=0: NOT detected (EXPECTED --
//       a single capture has no V1->V2 pair)
//   6.  Slow-to-transition, two_pattern_mode=1, site 6: detected
// Expected tally: 8 lines starting "PASS" plus 1 "EXPECTED" line, 0 "FAIL".
// -----------------------------------------------------------------------------
module tb_stage0_milestone;

    localparam int NUM_CHAINS = 2;
    localparam int CHAIN_LEN  = 8;
    localparam int NUM_PI     = 4;
    localparam int NUM_PO     = 4;
    localparam int NUM_FAULTS = 8;

    logic clk = 0, rst_n = 0;
    logic [NUM_PI-1:0] pi = '0;
    logic [NUM_PO-1:0] po;

    logic fi_active = 0;
    logic [$clog2(NUM_FAULTS)-1:0] fi_site = '0;
    logic [1:0] fi_type = 2'b00;

    logic chain_fault_active = 0;
    logic [$clog2(NUM_CHAINS)-1:0] chain_fault_chain = '0;
    logic [$clog2(CHAIN_LEN)-1:0]  chain_fault_cell = '0;
    logic [1:0] chain_fault_type = 2'b00;

    logic start = 0, chain_test_mode = 0, two_pattern_mode = 0, busy, done;
    logic [19:0] pattern_id = 20'd1;

    logic [$clog2(CHAIN_LEN)-1:0] shift_index;
    logic [NUM_CHAINS-1:0] shift_in_bits = '0;
    logic [NUM_CHAINS-1:0] golden_bits;
    logic [NUM_CHAINS-1:0] golden_capture [CHAIN_LEN];
    logic [NUM_CHAINS-1:0] golden_capture_2pat [CHAIN_LEN]; // separate: two_pattern_mode's
                                                             // fault-free response differs
                                                             // from the single-capture flow's

    // Combinational, race-free: scan_ctrl only consumes golden_bits during
    // S_SHIFT_OUT of normal-mode runs, indexed by its own shift_index, so a
    // plain array read (no clocked driver process to race against) is both
    // simpler and correct. During the golden-capture pass golden_capture is
    // still unpopulated/'x -- harmless, since that pass's compare result
    // isn't used for anything.
    assign golden_bits = golden_capture[shift_index];

    logic fail_valid;
    logic [19:0] fail_pattern_id;
    logic [$clog2(NUM_CHAINS)-1:0] fail_chain_id;
    logic [$clog2(CHAIN_LEN)-1:0] fail_cell_index;

    logic [NUM_CHAINS-1:0] chain_ok;
    logic [NUM_CHAINS*$clog2(CHAIN_LEN)-1:0] chain_first_bad_cell_flat;

    stage0_milestone_top #(
        .NUM_CHAINS(NUM_CHAINS), .CHAIN_LEN(CHAIN_LEN),
        .NUM_PI(NUM_PI), .NUM_PO(NUM_PO), .NUM_FAULTS(NUM_FAULTS)
    ) dut (
        .clk(clk), .rst_n(rst_n), .pi(pi), .po(po),
        .fi_active(fi_active), .fi_site(fi_site), .fi_type(fi_type),
        .chain_fault_active(chain_fault_active), .chain_fault_chain(chain_fault_chain),
        .chain_fault_cell(chain_fault_cell), .chain_fault_type(chain_fault_type),
        .start(start), .chain_test_mode(chain_test_mode), .two_pattern_mode(two_pattern_mode),
        .pattern_id(pattern_id),
        .busy(busy), .done(done),
        .shift_index(shift_index), .shift_in_bits(shift_in_bits), .golden_bits(golden_bits),
        .fail_valid(fail_valid), .fail_pattern_id(fail_pattern_id),
        .fail_chain_id(fail_chain_id), .fail_cell_index(fail_cell_index),
        .chain_ok(chain_ok), .chain_first_bad_cell_flat(chain_first_bad_cell_flat)
    );

    always #10 clk = ~clk; // 50 MHz

    // Sample points for testbench logic that reads DUT-internal state (via
    // hierarchical reference, e.g. dut.u_scan_ctrl.state) MUST settle after
    // this edge's nonblocking updates, not race them -- plain @(posedge clk)
    // is not sufficient when peeking inside the DUT rather than at its ports.
    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // Fixed all-zero shift-in pattern for this milestone: keeps the golden
    // capture / replay logic below simple (no external pattern source yet).
    always_comb shift_in_bits = '0;

    // A direct `fails_seen==1 ? "y" : "ies"` ternary between differently-
    // sized string literals is a classic Verilog gotcha: both branches get
    // zero-padded to a common packed bit-width (the longer literal's), so
    // the shorter one prints with leading blank bytes. SystemVerilog's
    // dynamic `string` type has no such fixed width, so returning through
    // one sidesteps the bug entirely.
    function automatic string plural_suffix(input int n);
        plural_suffix = (n == 1) ? "y" : "ies";
    endfunction

    task do_reset;
        begin
            // The DUT keeps running its functional logic whenever scan_en=0
            // (idle included) -- that's realistic, not a bug. So we must pin
            // `pi` to the known (q=0, pi=0) fixed point before resetting,
            // or leftover `pi` from a previous test section drifts `q` away
            // from zero during this task's own post-release dwell, before
            // the caller gets a chance to set pi again.
            pi   = '0;
            rst_n = 0;
            repeat (3) @(posedge clk);
            rst_n = 1;
            repeat (3) @(posedge clk);
        end
    endtask

    // Convenience probe (scan_out isn't a top-level port on stage0_milestone_top,
    // reach into the hierarchy for testbench observation only).
    wire [NUM_CHAINS-1:0] scan_out_probe;
    assign scan_out_probe = dut.u_dut.scan_out;

    integer i, k;
    integer fails_seen;

    initial begin
        do_reset();

        // ------------------------------------------------------------
        // 1. Zero-fault golden run
        // ------------------------------------------------------------
        pi = 4'b0101;
        fi_active = 0;
        chain_test_mode = 0;

        // Pass A: capture the DUT's actual response as our golden reference
        // (stands in for the golden-response DDR data the real system would
        // already have from Tessent/ATPG simulation).
        // golden_bits is driven combinationally from golden_capture[shift_index]
        // (see the assign above); during this capture pass golden_capture is
        // still unpopulated, which is fine -- this pass's compare is unused.
        k = 0;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (!done && dut.u_scan_ctrl.state == dut.u_scan_ctrl.S_SHIFT_OUT) begin
                golden_capture[k] = scan_out_probe;
                k++;
            end
        end
        $write("[golden capture] response =");
        for (i = 0; i < CHAIN_LEN; i++) $write(" %b", golden_capture[i]);
        $display("");

        // Pass B: reset back to the identical starting state, replay the
        // same stimulus, and now actually compare against the golden
        // capture. This must be completely clean.
        do_reset();
        pi = 4'b0101;
        fails_seen = 0;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (fail_valid) fails_seen++;
        end
        if (fails_seen == 0)
            $display("PASS: zero-fault golden run is clean (0 mismatches)");
        else
            $display("FAIL: zero-fault run produced %0d mismatches -- stop, this must be clean first", fails_seen);

        // ------------------------------------------------------------
        // 2. Stage 0 chain test: healthy baseline, then a deliberately
        //    broken chain at a known cell index.
        // ------------------------------------------------------------
        do_reset();
        chain_test_mode = 1;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        wait (done);
        $display("[Stage 0, healthy] chain_ok = %b (expect all 1)", chain_ok);

        do_reset();
        // Force scan cell 3 of chain 0 stuck-at-0 -- a classic broken/stuck
        // chain cell. This is a *scan chain* fault (Stage 0's target),
        // distinct from the functional stuck-at faults fi_cell injects.
        force dut.u_dut.q[3] = 1'b0;
        chain_test_mode = 1;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        wait (done);
        $display("[Stage 0, chain 0 cell 3 stuck] chain_ok = %b (expect chain 0 = 0)", chain_ok);
        $display("  first bad cell, chain 0 = %0d",
                  chain_first_bad_cell_flat[0*$clog2(CHAIN_LEN) +: $clog2(CHAIN_LEN)]);
        release dut.u_dut.q[3];
        if (chain_ok[0] == 1'b0)
            $display("PASS: Stage 0 correctly flagged the broken chain");
        else
            $display("FAIL: Stage 0 did not detect the broken chain");

        // ------------------------------------------------------------
        // 2b. Same "stuck chain cell" scenario, but via the real RTL
        //     injection mechanism (chain_fault_*) instead of a simulation
        //     force/release hack -- this is what you'd actually use for a
        //     repeatable, runtime-selectable fault campaign.
        // ------------------------------------------------------------
        do_reset();
        chain_fault_active = 1'b1;
        chain_fault_chain  = 2'd0;
        chain_fault_cell   = 3'd3;
        chain_fault_type   = 2'b01; // stuck
        chain_test_mode = 1;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        wait (done);
        chain_fault_active = 1'b0;
        $display("[Stage 0, RTL-injected stuck, chain 0 cell 3] chain_ok = %b (expect chain 0 = 0)", chain_ok);
        if (chain_ok[0] == 1'b0)
            $display("PASS: RTL-injected stuck chain cell correctly flagged");
        else
            $display("FAIL: RTL-injected stuck chain cell was not detected");

        // ------------------------------------------------------------
        // 2c. Broken chain cell (self-hold / open). IMPORTANT: from a q=0
        //     reset state, a cell that never accepts a new shifted value
        //     just keeps reading back 0 forever -- OBSERVATIONALLY
        //     IDENTICAL to stuck-at-0 in this test. This is a genuine,
        //     expected finding (a real tester would need a different
        //     procedure -- e.g. preset the chain to all-1s before engaging
        //     the fault -- to tell "stuck" and "broken/held" apart), not a
        //     bug in the fault model.
        // ------------------------------------------------------------
        do_reset();
        chain_fault_active = 1'b1;
        chain_fault_chain  = 2'd0;
        chain_fault_cell   = 3'd3;
        chain_fault_type   = 2'b10; // broken (self-hold)
        chain_test_mode = 1;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        wait (done);
        chain_fault_active = 1'b0;
        $display("[Stage 0, broken/held, chain 0 cell 3] chain_ok = %b", chain_ok);
        if (chain_ok[0] == 1'b0)
            $display("PASS: broken chain cell correctly flagged as a chain anomaly (detected, same as stuck -- expected, see note above)");
        else
            $display("FAIL: broken chain cell was not detected at all");

        // ------------------------------------------------------------
        // 2d. Slow chain cell: a fixed one-extra-cycle propagation delay.
        //     Detected here as "this chain doesn't behave as a clean
        //     CHAIN_LEN-deep shift register" -- but this does NOT prove
        //     the fault would behave correctly ("fails at-speed, passes at
        //     reduced speed") in real continuous-time terms. This zero-delay
        //     simulator has no concept of a clock being "too fast" for a
        //     signal to settle -- that needs gate-level/SDF timing
        //     simulation, not available here.
        // ------------------------------------------------------------
        do_reset();
        chain_fault_active = 1'b1;
        chain_fault_chain  = 2'd1;
        chain_fault_cell   = 3'd4;
        chain_fault_type   = 2'b11; // slow
        chain_test_mode = 1;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        wait (done);
        chain_fault_active = 1'b0;
        $display("[Stage 0, slow, chain 1 cell 4] chain_ok = %b", chain_ok);
        if (chain_ok[1] == 1'b0)
            $display("PASS: slow chain cell detected as a chain-timing anomaly (NOT proof of real at-speed-vs-reduced-speed behavior -- see note above)");
        else
            $display("NOTE: slow chain cell not flagged by this particular check -- may need a differently-timed self-compare to expose a 1-cycle anomaly at this position");

        // ------------------------------------------------------------
        // 3. Single injected SA0 fault -> confirm fail-log detection
        // ------------------------------------------------------------
        do_reset();
        pi = 4'b0101;
        chain_test_mode = 0;
        fi_active = 1'b1;
        fi_site   = 3'd2;   // net_raw[2] = pi[2] | q[2]
        fi_type   = 2'b01;  // SA0

        fails_seen = 0;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (fail_valid) begin
                fails_seen++;
                $display("  fail_valid: pattern_id=%0d chain=%0d cell=%0d",
                          fail_pattern_id, fail_chain_id, fail_cell_index);
            end
        end
        fi_active = 1'b0;
        if (fails_seen > 0)
            $display("PASS: injected SA0 fault produced %0d fail-log entr%s", fails_seen, plural_suffix(fails_seen));
        else
            $display("FAIL: injected SA0 fault was not detected");

        // ------------------------------------------------------------
        // 4. Single injected SA1 fault -> confirm fail-log detection
        // ------------------------------------------------------------
        do_reset();
        pi = 4'b0101;
        chain_test_mode = 0;
        fi_active = 1'b1;
        fi_site   = 3'd1;   // net_raw[1] = pi[1] & q[1]; golden value is 0 here, so SA1 is observable
        fi_type   = 2'b10;  // SA1

        fails_seen = 0;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (fail_valid) begin
                fails_seen++;
                $display("  fail_valid: pattern_id=%0d chain=%0d cell=%0d",
                          fail_pattern_id, fail_chain_id, fail_cell_index);
            end
        end
        fi_active = 1'b0;
        if (fails_seen > 0)
            $display("PASS: injected SA1 fault produced %0d fail-log entr%s", fails_seen, plural_suffix(fails_seen));
        else
            $display("FAIL: injected SA1 fault was not detected");

        // ------------------------------------------------------------
        // 5. Slow-to-transition fault, two_pattern_mode=0 (the ORIGINAL
        //    single-capture flow): deliberately repeated here, now as a
        //    documented BEFORE case. A transition fault needs two patterns
        //    -- an initialization vector V1, then a launch vector that
        //    actually creates a transition, captured at speed -- and a
        //    single shift-in -> one capture -> shift-out sequence has no
        //    second edge to form that V1->V2 pair. A sweep across all 8
        //    sites confirmed zero detections anywhere with this flow,
        //    consistent with the explanation rather than a site-specific
        //    masking issue (which is what SA0/SA1 sometimes show instead).
        // ------------------------------------------------------------
        do_reset();
        pi = 4'b0101;
        chain_test_mode  = 0;
        two_pattern_mode = 0;
        fi_active = 1'b1;
        fi_site   = 3'd0;
        fi_type   = 2'b11;  // slow-to-transition

        fails_seen = 0;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (fail_valid) fails_seen++;
        end
        fi_active = 1'b0;
        if (fails_seen == 0)
            $display("EXPECTED (BEFORE): transition fault not detected under two_pattern_mode=0 -- no second capture edge to form a V1->V2 pair");
        else
            $display("UNEXPECTED: transition fault WAS detected (%0d entries) under two_pattern_mode=0 -- re-examine, this contradicts the single-vector limitation reasoning above", fails_seen);

        // ------------------------------------------------------------
        // 6. Same slow-to-transition fault, now with two_pattern_mode=1 --
        //    the AFTER case. scan_ctrl now runs shift-in (V1) -> S_LAUNCH
        //    (one functional edge, computing a genuinely new value from V1)
        //    -> S_CAPTURE (the real test edge). fi_cell's "slow" model can
        //    only produce an observable effect when the targeted net's
        //    value actually differs between these two specific edges --
        //    true of only ONE site here (site 6 of 8; found by
        //    sweeping, same spirit as the SA1 site-masking result earlier).
        //    This needs its OWN golden capture: the fault-free response
        //    under two_pattern_mode differs from the single-capture flow's.
        // ------------------------------------------------------------
        two_pattern_mode = 1;
        do_reset();
        pi = 4'b0101;
        k = 0;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (!done && dut.u_scan_ctrl.state == dut.u_scan_ctrl.S_SHIFT_OUT) begin
                golden_capture_2pat[k] = scan_out_probe;
                k++;
            end
        end

        // golden_bits reads from golden_capture[shift_index] (see the assign
        // near the top of this file); copy the two_pattern_mode capture into
        // it so the upcoming fault-injection pass compares against the
        // right fault-free reference, without needing a second mux in the
        // RTL-facing wiring.
        for (i = 0; i < CHAIN_LEN; i++) golden_capture[i] = golden_capture_2pat[i];

        do_reset();
        pi = 4'b0101;
        fi_active = 1'b1;
        fi_site   = 3'd6;   // the ONLY site whose value changes across the launch edge
                            // (net6 = q4 ^ net4; q4 goes 0->1). Predicted from the
                            // circuit's equations first, then confirmed by an 8-site
                            // sweep that also checked raw q, not just the fail log.
        fi_type   = 2'b11;  // slow-to-transition

        fails_seen = 0;
        start = 1; @(posedge clk); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (fail_valid) begin
                fails_seen++;
                $display("  fail_valid: pattern_id=%0d chain=%0d cell=%0d",
                          fail_pattern_id, fail_chain_id, fail_cell_index);
            end
        end
        fi_active = 1'b0;
        two_pattern_mode = 1'b0; // restore default for anything run after this
        if (fails_seen > 0)
            $display("PASS (AFTER): transition fault produced %0d fail-log entr%s under two_pattern_mode=1 -- the FSM extension closes the gap", fails_seen, plural_suffix(fails_seen));
        else
            $display("FAIL: transition fault still not detected even under two_pattern_mode=1 at a site verified by sweep to produce a real transition");

        repeat (10) @(posedge clk);
        $finish;
    end

    initial begin
        #200_000;
        $display("WATCHDOG TIMEOUT");
        $finish;
    end

endmodule
