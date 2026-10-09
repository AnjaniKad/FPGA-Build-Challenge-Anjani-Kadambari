// -----------------------------------------------------------------------------
// stage1_milestone_top.sv
// Wraps the existing, already-verified stage0_milestone_top with
// fail_mask_collector + cone_intersect, adding Stage 1 (structural cone
// intersection) on top without modifying Stage 0's stable integration.
// Run one pattern at a time (start, wait for done); candidate_sites narrows
// (monotonically shrinks or stays the same) as more patterns are folded in,
// until `new_session` is pulsed to start a fresh diagnosis campaign.
//
// LIMIT -- single functional edge only: cone_intersect's cone table models
// ONE functional clock between shift-in and shift-out. In two_pattern_mode
// there are two, so a fault's effect after the launch edge can reach cells
// the table says are unreachable (e.g. chain 1, whose single-edge cone is
// empty). Measured before this guard existed: with two_pattern_mode=1, 7 of
// the 9 observable faults made Stage 1 return an EMPTY set -- a confident
// wrong answer ("no single site explains this") that excluded the true
// site. So patterns run in two_pattern_mode are deliberately NOT folded
// into the candidate set (pattern_valid below). Supporting them would need
// sequential, multi-edge cones: real future work, not a parameter change.
// -----------------------------------------------------------------------------
module stage1_milestone_top #(
    parameter int NUM_CHAINS = 2,
    parameter int CHAIN_LEN  = 8,
    parameter int NUM_PI     = 4,
    parameter int NUM_PO     = 4,
    parameter int NUM_FAULTS = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,

    input  logic [NUM_PI-1:0]             pi,
    output logic [NUM_PO-1:0]             po,

    input  logic                          fi_active,
    input  logic [$clog2(NUM_FAULTS)-1:0] fi_site,
    input  logic [1:0]                    fi_type,

    input  logic                          chain_fault_active,
    input  logic [$clog2(NUM_CHAINS)-1:0] chain_fault_chain,
    input  logic [$clog2(CHAIN_LEN)-1:0]  chain_fault_cell,
    input  logic [1:0]                    chain_fault_type,

    input  logic                          start,
    input  logic                          chain_test_mode,
    input  logic                          two_pattern_mode,
    input  logic [19:0]                   pattern_id,
    output logic                          busy,
    output logic                          done,

    output logic [$clog2(CHAIN_LEN)-1:0]  shift_index,
    input  logic [NUM_CHAINS-1:0]         shift_in_bits,
    input  logic [NUM_CHAINS-1:0]         golden_bits,

    // Stage 1 control/results
    input  logic                          new_session,      // start a fresh diagnosis campaign
    output logic [NUM_CHAINS*CHAIN_LEN-1:0] fail_mask,      // this pattern's fail bitmap (debug visibility)
    output logic [NUM_FAULTS-1:0]         candidate_sites,  // accumulated remaining suspects
    output logic                          any_cell_failed
);

    logic                          fail_valid;
    logic [19:0]                   fail_pattern_id;
    logic [$clog2(NUM_CHAINS)-1:0] fail_chain_id;
    logic [NUM_CHAINS-1:0]         fail_vec;
    logic [$clog2(CHAIN_LEN)-1:0]  fail_cell_index;
    logic [NUM_CHAINS-1:0]                    chain_ok;
    logic [NUM_CHAINS*$clog2(CHAIN_LEN)-1:0]  chain_first_bad_cell_flat;

    stage0_milestone_top #(
        .NUM_CHAINS(NUM_CHAINS), .CHAIN_LEN(CHAIN_LEN),
        .NUM_PI(NUM_PI), .NUM_PO(NUM_PO), .NUM_FAULTS(NUM_FAULTS)
    ) u_stage0 (
        .clk(clk), .rst_n(rst_n), .pi(pi), .po(po),
        .fi_active(fi_active), .fi_site(fi_site), .fi_type(fi_type),
        .chain_fault_active(chain_fault_active), .chain_fault_chain(chain_fault_chain),
        .chain_fault_cell(chain_fault_cell), .chain_fault_type(chain_fault_type),
        .start(start), .chain_test_mode(chain_test_mode), .two_pattern_mode(two_pattern_mode),
        .pattern_id(pattern_id), .busy(busy), .done(done),
        .shift_index(shift_index), .shift_in_bits(shift_in_bits), .golden_bits(golden_bits),
        .fail_valid(fail_valid), .fail_pattern_id(fail_pattern_id),
        .fail_chain_id(fail_chain_id), .fail_cell_index(fail_cell_index), .fail_vec(fail_vec),
        .chain_ok(chain_ok), .chain_first_bad_cell_flat(chain_first_bad_cell_flat)
    );

    fail_mask_collector #(.NUM_CHAINS(NUM_CHAINS), .CHAIN_LEN(CHAIN_LEN)) u_collector (
        .clk(clk), .rst_n(rst_n), .start(start),
        .fail_valid(fail_valid), .fail_vec(fail_vec), .fail_cell_index(fail_cell_index),
        .fail_mask(fail_mask)
    );

    cone_intersect #(.NUM_CELLS(NUM_CHAINS*CHAIN_LEN), .NUM_SITES(NUM_FAULTS)) u_cone (
        .clk(clk), .rst_n(rst_n),
        .new_session(new_session),
        // Fold this pattern's fail_mask in once it's complete and stable --
        // but only for single-edge patterns (see LIMIT in the header).
        .pattern_valid(done && !two_pattern_mode),
        .fail_mask(fail_mask),
        .candidate_sites(candidate_sites),
        .any_cell_failed(any_cell_failed)
    );

endmodule
