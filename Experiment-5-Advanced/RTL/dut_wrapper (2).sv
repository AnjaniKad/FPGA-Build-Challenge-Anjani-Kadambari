// -----------------------------------------------------------------------------
// dut_wrapper.sv
// PLACEHOLDER for the Tessent-scan-inserted b17 benchmark netlist described in
// RTL_ARCHITECTURE.md 3.1. This is a small hand-built sequential circuit with
// the SAME port interface the real b17 wrapper will have, so scan_ctrl and
// its testbench are real and verifiable now, without Tessent access.
//
// SWAP-IN PLAN: once Tessent scan insertion + the fi_cell instrumentation
// script exist, replace the body of this module (everything below the port
// list) with the generated b17 netlist, re-parameterizing NUM_CHAINS/
// CHAIN_LEN/NUM_PI/NUM_PO/NUM_FAULTS to the real values (8/175/32/32/256+).
// scan_ctrl, fi_cell, fail_mask_collector and the testbenches' structure
// should carry over. cone_intersect's cone table will NOT: it is hand-derived
// from THIS file's equations and must be regenerated (or replaced by real
// graph traversal) for any other netlist.
//
// Internal structure (this placeholder only):
//   - NUM_CHAINS*CHAIN_LEN scan flip-flops, split evenly across chains.
//   - 8 combinational nets feed through fi_cell instrumentation (candidate
//     fault sites), matching the doc's guidance to instrument a SAMPLED
//     subset of nets, not all of them.
//   - Instrumented nets drive both next-state (so faults are captured into
//     scan-observable state) and primary outputs. NOTE: the diagnosis flow
//     only observes scan cells; the primary outputs are never compared, so a
//     fault visible only at `po` would go undetected.
//   - Chain 1 (cells 8-15) has no instrumented net in its next-state logic,
//     so in a single functional edge it can only show scan-CHAIN faults, not
//     fi_cell faults.
//   - A second, independent injector (chain_fault_*) corrupts the scan SHIFT
//     PATH itself: stuck cell, broken (self-hold) cell, slow (one-cycle-late)
//     cell. See the README, "Chain-path fault injection".
// -----------------------------------------------------------------------------
module dut_wrapper #(
    parameter int NUM_CHAINS = 2,
    parameter int CHAIN_LEN  = 8,
    parameter int NUM_PI     = 4,
    parameter int NUM_PO     = 4,
    parameter int NUM_FAULTS = 8      // injectable sites in THIS placeholder
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          scan_en,
    input  logic [NUM_CHAINS-1:0]         scan_in,
    output logic [NUM_CHAINS-1:0]         scan_out,
    input  logic [NUM_PI-1:0]             pi,
    output logic [NUM_PO-1:0]             po,
    // fault injection
    input  logic                          fi_active,
    input  logic [$clog2(NUM_FAULTS)-1:0] fi_site,
    input  logic [1:0]                    fi_type,
    // Chain-path fault injection: distinct from fi_cell/fi_active above,
    // which only touches functional combinational nets. This instruments
    // the scan SHIFT PATH itself, per PROJECT_CONTEXT.md's three named
    // "must ship" chain fault classes: stuck chain cell, broken chain,
    // slow chain. See the per-cell mux below for exactly what each models
    // and does NOT model.
    input  logic                          chain_fault_active,
    input  logic [$clog2(NUM_CHAINS)-1:0] chain_fault_chain,
    input  logic [$clog2(CHAIN_LEN)-1:0]  chain_fault_cell,
    input  logic [1:0]                    chain_fault_type  // 00=none 01=stuck 10=broken 11=slow
);

    localparam int TOTAL_CELLS = NUM_CHAINS * CHAIN_LEN;

    // q[idx] is scan cell `idx`, where idx = chain*CHAIN_LEN + position,
    // position 0 = nearest scan_in, position CHAIN_LEN-1 = drives scan_out.
    logic [TOTAL_CELLS-1:0] q;
    logic [TOTAL_CELLS-1:0] d_func;   // functional next-state value per cell
    logic [TOTAL_CELLS-1:0] d_sel;    // mux(scan_en) output actually clocked in

    genvar c, p;
    generate
        for (c = 0; c < NUM_CHAINS; c = c + 1) begin : CHAIN
            for (p = 0; p < CHAIN_LEN; p = p + 1) begin : CELL
                localparam int IDX = c * CHAIN_LEN + p;

                logic scan_d_raw;
                if (p == 0)
                    assign scan_d_raw = scan_in[c];
                else
                    assign scan_d_raw = q[IDX-1];

                // One-cycle-late copy of this cell's own shift input, used
                // only by the "slow" chain fault model below. Like fi_cell's
                // transition fault, this is a discrete one-extra-cycle
                // approximation, NOT a model of real continuous propagation
                // delay -- a zero-delay behavioral simulation has no delay
                // to be "too slow" relative to, at any clock rate. A fault
                // that genuinely passes at reduced speed and fails at full
                // speed needs gate-level simulation with real timing
                // (SDF-backed), which is out of scope here.
                logic scan_d_delayed;
                always_ff @(posedge clk) scan_d_delayed <= scan_d_raw;

                logic chain_fault_sel;
                assign chain_fault_sel = chain_fault_active &&
                                         (chain_fault_chain == c) &&
                                         (chain_fault_cell  == p);

                logic scan_d;
                always_comb begin
                    unique case ({chain_fault_sel, chain_fault_type})
                        3'b101:  scan_d = 1'b0;             // stuck chain cell
                        3'b110:  scan_d = q[IDX];            // broken chain: self-hold,
                                                              // never accepts a new shifted
                                                              // value -- see header note on
                                                              // why this can look identical
                                                              // to stuck-at-0 from a q=0 reset
                        3'b111:  scan_d = scan_d_delayed;    // slow chain (see note above)
                        default: scan_d = scan_d_raw;
                    endcase
                end

                assign d_sel[IDX] = scan_en ? scan_d : d_func[IDX];

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) q[IDX] <= 1'b0;
                    else        q[IDX] <= d_sel[IDX];
                end
            end
            assign scan_out[c] = q[c*CHAIN_LEN + (CHAIN_LEN-1)];
        end
    endgenerate

    // -------------------------------------------------------------------
    // Instrumented combinational cloud: 8 candidate fault sites (NUM_FAULTS)
    // -------------------------------------------------------------------
    logic [7:0] net_raw, net_fi;

    assign net_raw[0] = pi[0] ^ q[0];
    assign net_raw[1] = pi[1] & q[1];
    assign net_raw[2] = pi[2] | q[2];
    assign net_raw[3] = pi[3] ^ q[3];
    assign net_raw[4] = net_fi[0] & net_fi[1];
    assign net_raw[5] = net_fi[2] ^ net_fi[3];
    assign net_raw[6] = q[4] ^ net_fi[4];
    assign net_raw[7] = q[5] & net_fi[5];

    generate
        for (genvar g = 0; g < 8; g = g + 1) begin : FI
            fi_cell #(.SITE_ID(g), .NUM_FAULTS(NUM_FAULTS)) u_fi (
                .clk(clk), .net_in(net_raw[g]), .net_out(net_fi[g]),
                .fi_active(fi_active), .fi_site(fi_site), .fi_type(fi_type)
            );
        end
    endgenerate

    // Next-state: cells 0-7 (chain 0) driven substantially by instrumented
    // nets, so faults are captured into scan-observable state.
    assign d_func[0] = net_fi[6];
    assign d_func[1] = net_fi[7];
    assign d_func[2] = q[6] ^ pi[0];
    assign d_func[3] = q[7] & pi[1];
    assign d_func[4] = net_fi[0] ^ q[8 % TOTAL_CELLS];
    assign d_func[5] = net_fi[1] | q[9 % TOTAL_CELLS];
    assign d_func[6] = q[10 % TOTAL_CELLS] ^ net_fi[2];
    assign d_func[7] = q[11 % TOTAL_CELLS] ^ net_fi[3];

    // Cells 8-15 (chain 1): uninstrumented shift/XOR network, gives the
    // circuit real sequential depth without adding more injection sites.
    generate
        if (TOTAL_CELLS > 8) begin : CHAIN1_LOGIC
            assign d_func[8]  = q[0] ^ pi[2 % NUM_PI];
            assign d_func[9]  = q[1] ^ pi[3 % NUM_PI];
            assign d_func[10] = q[2] & q[9 % TOTAL_CELLS];
            assign d_func[11] = q[3] | q[10 % TOTAL_CELLS];
            assign d_func[12] = q[4] ^ q[11 % TOTAL_CELLS];
            assign d_func[13] = q[5] ^ q[12 % TOTAL_CELLS];
            assign d_func[14] = q[6] & q[13 % TOTAL_CELLS];
            assign d_func[15] = q[7] | q[14 % TOTAL_CELLS];
        end
    endgenerate

    // Primary outputs: mix of state and instrumented nets, so faults are
    // also directly observable without a scan cycle.
    assign po[0] = q[0] ^ net_fi[4];
    assign po[1] = q[TOTAL_CELLS > 8 ? 8 : 0] ^ net_fi[5];
    assign po[2] = q[TOTAL_CELLS-1];
    assign po[3] = net_fi[6] ^ net_fi[7];

endmodule
