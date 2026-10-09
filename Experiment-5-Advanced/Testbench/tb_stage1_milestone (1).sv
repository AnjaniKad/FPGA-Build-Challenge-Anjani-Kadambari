`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_stage1_milestone.sv
// Verifies Stage 1 (structural cone intersection). Every expected value below
// was predicted BEFORE running, from an independently verified observability
// sweep (inject each site, sample q at the true post-capture moment, diff
// against golden) plus the structural cone table derived from dut_wrapper's
// source -- so a passing result is a real cross-check, not a tautology.
//
// What Stage 1 can and can't do is part of what's being verified here:
//   - It must always keep the TRUE injected site in the candidate set.
//   - It can narrow to a unique site only when the failing cells' cones
//     happen to intersect to one site; otherwise a genuine ambiguity remains
//     (sites that share a failure signature), which is Stage 2/3's job.
//   - It must REFUSE to reason about two_pattern_mode patterns (its cone
//     table models a single functional edge). Without that guard, 7 of 9
//     observable faults produced a wrongly EMPTY candidate set.
// Expected tally: 15 checks, all PASS.
// -----------------------------------------------------------------------------
module tb_stage1_milestone;

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
    logic start = 0, chain_test_mode = 0, two_pattern_mode = 0, busy, done;
    logic [19:0] pattern_id = 20'd1;
    logic [$clog2(CHAIN_LEN)-1:0] shift_index;
    logic [NUM_CHAINS-1:0] shift_in_bits = '0;
    logic [NUM_CHAINS-1:0] golden_bits;
    logic [NUM_CHAINS-1:0] golden_capture [CHAIN_LEN];
    assign golden_bits = golden_capture[shift_index];

    logic new_session = 0;
    logic [NUM_CHAINS*CHAIN_LEN-1:0] fail_mask;
    logic [NUM_FAULTS-1:0] candidate_sites;
    logic any_cell_failed;

    stage1_milestone_top #(
        .NUM_CHAINS(NUM_CHAINS), .CHAIN_LEN(CHAIN_LEN),
        .NUM_PI(NUM_PI), .NUM_PO(NUM_PO), .NUM_FAULTS(NUM_FAULTS)
    ) dut (
        .clk(clk), .rst_n(rst_n), .pi(pi), .po(po),
        .fi_active(fi_active), .fi_site(fi_site), .fi_type(fi_type),
        .chain_fault_active(1'b0), .chain_fault_chain(1'b0),
        .chain_fault_cell(3'd0), .chain_fault_type(2'b00),
        .start(start), .chain_test_mode(chain_test_mode), .two_pattern_mode(two_pattern_mode),
        .pattern_id(pattern_id), .busy(busy), .done(done),
        .shift_index(shift_index), .shift_in_bits(shift_in_bits), .golden_bits(golden_bits),
        .new_session(new_session), .fail_mask(fail_mask),
        .candidate_sites(candidate_sites), .any_cell_failed(any_cell_failed)
    );

    always #10 clk = ~clk;

    task step;
        begin @(posedge clk); #1; end
    endtask

    // Pin pi to the known (q=0, pi=0) fixed point first: the DUT keeps
    // running its functional logic whenever scan_en=0, so leftover pi would
    // otherwise drift q away from zero during this task's own dwell.
    task do_reset;
        begin
            pi = '0; rst_n = 0;
            repeat (3) @(posedge clk);
            rst_n = 1;
            repeat (3) @(posedge clk);
        end
    endtask

    // NOTE on pulsing `start`: it must be raised and then cleared on
    // opposite sides of a clock edge (raise, step() = edge+#1, clear). The
    // tempting `start = 1; @(posedge clk); start = 0;` clears it in the SAME
    // time step the DUT samples it on that edge -- a race that silently
    // dropped the pulse here (FSM stayed in IDLE forever) even though the
    // identical pattern happened to work earlier in the file.
    // Runs one pattern to completion, then lets Stage 1's outputs settle
    // (cone_intersect folds fail_mask in on `done`, so its result appears a
    // cycle or two later).
    task run_pattern;
        begin
            start = 1; step(); start = 0;
            wait (busy);
            while (!done) step();
            repeat (3) step();
        end
    endtask

    task start_session;
        begin
            new_session = 1; step(); new_session = 0; step();
        end
    endtask

    integer k, passes = 0, fails = 0;

    task check(input string name, input logic [NUM_FAULTS-1:0] got,
               input logic [NUM_FAULTS-1:0] expected);
        begin
            if (got === expected) begin
                $display("PASS: %-34s candidates=%b", name, got);
                passes++;
            end else begin
                $display("FAIL: %-34s candidates=%b expected=%b", name, got, expected);
                fails++;
            end
        end
    endtask

    // Inject one fault, run one fresh-session pattern, return nothing but
    // leave candidate_sites/any_cell_failed readable for the caller.
    task inject_and_run(input logic [2:0] site, input logic [1:0] ftype);
        begin
            do_reset(); pi = 4'b0101;
            start_session();
            fi_active = 1; fi_site = site; fi_type = ftype;
            run_pattern();
            fi_active = 0;
        end
    endtask

    initial begin
        #2_000_000;
        $display("WATCHDOG TIMEOUT");
        $finish;
    end

    initial begin
        // Golden (fault-free) capture, sampled at each shift-out cycle.
        do_reset(); pi = 4'b0101;
        k = 0;
        start = 1; step(); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (!done && dut.u_stage0.u_scan_ctrl.state == dut.u_stage0.u_scan_ctrl.S_SHIFT_OUT) begin
                golden_capture[k] = dut.u_stage0.u_dut.scan_out;
                k++;
            end
        end
        repeat (3) step();

        // ---- Clean pattern: nothing failed, nothing learned ----
        start_session();
        do_reset(); pi = 4'b0101;
        run_pattern();
        check("clean pattern (no fault)", candidate_sites, 8'hFF);
        if (any_cell_failed === 1'b0) begin $display("PASS: any_cell_failed=0 on clean pattern"); passes++; end
        else begin $display("FAIL: any_cell_failed=%b on clean pattern", any_cell_failed); fails++; end

        // ---- Faults that narrow to exactly one site ----
        inject_and_run(3'd0, 2'b01); check("site0 SA0 -> unique {0}",     candidate_sites, 8'b00000001);
        inject_and_run(3'd1, 2'b10); check("site1 SA1 -> unique {1}",     candidate_sites, 8'b00000010);
        inject_and_run(3'd2, 2'b01); check("site2 SA0 -> unique {2}",     candidate_sites, 8'b00000100);
        inject_and_run(3'd3, 2'b10); check("site3 SA1 -> unique {3}",     candidate_sites, 8'b00001000);

        // ---- Genuinely ambiguous: true site is INSIDE the set, with impostors ----
        inject_and_run(3'd4, 2'b10); check("site4 SA1 -> ambiguous {0,1,4,6}", candidate_sites, 8'b01010011);
        inject_and_run(3'd6, 2'b10); check("site6 SA1 -> ambiguous {0,1,4,6}", candidate_sites, 8'b01010011);
        inject_and_run(3'd7, 2'b10); check("site7 SA1 -> ambiguous {2,3,5,7}", candidate_sites, 8'b10101100);

        // ---- Masked fault: site5's effect never reaches a cell with this vector ----
        inject_and_run(3'd5, 2'b01);
        check("site5 SA0 -> masked, nothing learned", candidate_sites, 8'hFF);

        // ---- Narrowing is monotonic: a later clean pattern never widens ----
        do_reset(); pi = 4'b0101; start_session();
        fi_active = 1; fi_site = 3'd0; fi_type = 2'b01; run_pattern(); fi_active = 0;
        check("session: after site0 SA0", candidate_sites, 8'b00000001);
        // No do_reset() between patterns inside a session: rst_n would also
        // reset cone_intersect's accumulated candidates and silently erase
        // exactly what this test checks. Shift-in overwrites every cell with
        // zeros anyway, so the DUT doesn't need a reset to be repeatable.
        run_pattern(); // fault removed, same session
        check("session: clean pattern doesn't widen", candidate_sites, 8'b00000001);

        // ---- Contradictory evidence empties the set (single-fault assumption violated) ----
        do_reset(); pi = 4'b0101; start_session();
        fi_active = 1; fi_site = 3'd0; fi_type = 2'b01; run_pattern(); fi_active = 0;
        fi_active = 1; fi_site = 3'd2; fi_type = 2'b01; run_pattern(); fi_active = 0;
        check("contradictory patterns -> empty set", candidate_sites, 8'b00000000);

        // ---- two_pattern_mode is outside the cone table's model: must be ignored ----
        // The pattern genuinely FAILS (fail_mask != 0), so the only reason
        // candidate_sites stays all-ones is the guard in stage1_milestone_top.
        // Needs its own golden (two-pattern flow differs from single-capture).
        two_pattern_mode = 1;
        do_reset(); pi = 4'b0101;
        k = 0;
        start = 1; step(); start = 0;
        wait (busy);
        while (!done) begin
            step();
            if (!done && dut.u_stage0.u_scan_ctrl.state == dut.u_stage0.u_scan_ctrl.S_SHIFT_OUT) begin
                golden_capture[k] = dut.u_stage0.u_dut.scan_out;
                k++;
            end
        end
        repeat (3) step();

        do_reset(); pi = 4'b0101; start_session();
        fi_active = 1; fi_site = 3'd0; fi_type = 2'b01; // SA0 at site 0 under two-pattern flow
        run_pattern(); fi_active = 0;
        if (fail_mask !== '0) begin
            $display("PASS: two-pattern run really failed (fail_mask=%b), so the guard is what's tested", fail_mask);
            passes++;
        end else begin
            $display("FAIL: two-pattern run showed no failure; guard test is vacuous");
            fails++;
        end
        check("two_pattern_mode ignored by Stage 1", candidate_sites, 8'hFF);
        two_pattern_mode = 0;

        $display("");
        $display("Stage 1 summary: %0d passed, %0d failed", passes, fails);
        repeat (5) step();
        $finish;
    end

endmodule
