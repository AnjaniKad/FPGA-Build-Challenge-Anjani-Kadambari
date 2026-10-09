// -----------------------------------------------------------------------------
// cone_intersect.sv
// Stage 1 per RTL_ARCHITECTURE.md/PROJECT_CONTEXT.md: for each failing
// pattern, trace backward through the structural fan-in cone of the failing
// cells; intersect across patterns as more are run.
//
// SCOPE, STATED HONESTLY: the real system stores the netlist as a CSR graph
// in DDR (tens of thousands of nodes, "the main DDR consumer" per the docs)
// and does memory-bandwidth-bound backward graph traversal. For this
// placeholder DUT (8 fault sites, 16 cells), the entire cone table is a
// fixed 16-entry lookup, hand-derived directly from dut_wrapper.sv's source
// (the derivation is written out in the project README, "Stage 1") and
// implemented as a case-statement function. It models a SINGLE functional
// edge between shift-in and shift-out; stage1_milestone_top therefore never
// feeds it two_pattern_mode patterns (see its LIMIT note). This is NOT a
// generic graph-traversal engine -- building
// one only makes sense against a real, large netlist (b17), which isn't
// available in this environment. Swapping in a real graph means replacing
// this lookup with real traversal hardware, not just changing parameters.
//
// ALGORITHM: this module intentionally implements only the "intersect
// cones of failing cells" half of the spec's "intersect failing patterns,
// subtract passing cones" description. A site that could affect a passing
// cell is NOT excluded here, because purely structural reachability doesn't
// tell you whether that site's fault would ACTUALLY have been observed on
// that passing cell for this specific test vector (a real fault could be
// masked there, as this project's own fault-masking findings during
// verification repeatedly demonstrated). Confirming that requires fault
// SIMULATION against the specific vector, which is Stage 2's job, not
// Stage 1's. Intersecting only the failing cells' cones is the defensible,
// conservative structural narrowing step; treating "didn't fail" as proof
// of "couldn't be the cause" would silently produce wrong answers.
// -----------------------------------------------------------------------------
module cone_intersect #(
    parameter int NUM_CELLS = 16,
    parameter int NUM_SITES = 8
)(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      new_session,      // clears accumulated candidates to "all sites"
    input  logic                      pattern_valid,     // pulse: fail_mask below is ready to fold in
    input  logic [NUM_CELLS-1:0]      fail_mask,         // which cells mismatched THIS pattern
    output logic [NUM_SITES-1:0]      candidate_sites,   // accumulated remaining suspects
    output logic                      any_cell_failed    // informational: was this pattern clean?
);

    // Structural fan-in cone table for the placeholder dut_wrapper.sv,
    // derived directly from its source (not from simulation -- structure
    // doesn't depend on test vectors). cone_table[cell] = bitmask of sites
    // that can structurally influence that cell's next-state value.
    // NOTE: the argument is named `cell_idx`, deliberately NOT `cell` --
    // `cell` is a reserved keyword in Verilog (used in `config` blocks), and
    // using it as an identifier produces a bare, locationless "syntax
    // error" in Icarus. This cost real debugging time during development:
    // an initial theory blamed `int` arguments and parameter-width return
    // types, which turned out to be wrong -- minimal bisected repros all
    // used the name `cell` and all failed, and every variant that worked
    // happened to use a different name. Always rule out reserved-word
    // collisions before blaming the tool.
    function automatic logic [NUM_SITES-1:0] cone_table(input int cell_idx);
        begin
        case (cell_idx)
            0:  cone_table = 8'b01010011; // {0,1,4,6}
            1:  cone_table = 8'b10101100; // {2,3,5,7}
            2:  cone_table = 8'b00000000;
            3:  cone_table = 8'b00000000;
            4:  cone_table = 8'b00000001; // {0}
            5:  cone_table = 8'b00000010; // {1}
            6:  cone_table = 8'b00000100; // {2}
            7:  cone_table = 8'b00001000; // {3}
            default: cone_table = 8'b00000000; // cells 8-15 (chain 1): no site reaches these
        endcase
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            candidate_sites <= '1; // start a session assuming every site is a suspect
            any_cell_failed <= 1'b0;
        end else begin
            if (new_session) candidate_sites <= '1;

            if (pattern_valid) begin
                logic [NUM_SITES-1:0] this_pattern_intersection;
                logic                 saw_failure;
                this_pattern_intersection = '1; // identity for AND-reduction below
                saw_failure = 1'b0;

                for (int c = 0; c < NUM_CELLS; c++) begin
                    if (fail_mask[c]) begin
                        saw_failure = 1'b1;
                        this_pattern_intersection = this_pattern_intersection & cone_table(c);
                    end
                end

                any_cell_failed <= saw_failure;
                // A clean pattern (no failures) narrows nothing -- leave
                // candidate_sites as-is rather than ANDing with the
                // all-ones identity, which would be a no-op anyway, but
                // being explicit here avoids relying on that coincidence
                // if the identity value above is ever changed.
                if (saw_failure)
                    candidate_sites <= candidate_sites & this_pattern_intersection;
            end
        end
    end

endmodule
