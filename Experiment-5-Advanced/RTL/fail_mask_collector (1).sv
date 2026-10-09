// -----------------------------------------------------------------------------
// fail_mask_collector.sv
// scan_ctrl's serial fail-log names at most ONE chain per cycle and is meant
// to be drained toward mem_arbiter/DDR in the real system. Stage 1's cone
// intersection needs the opposite shape: the COMPLETE set of which cells
// mismatched in a single pattern, all at once. This module bridges that
// gap: each cycle it reads scan_ctrl's `fail_vec` (every chain mismatching
// that cycle, so none is lost) and accumulates a persistent per-cell bitmap,
// cleared at the start of each new pattern.
//
// IMPORTANT INDEXING NOTE: scan_ctrl's `fail_cell_index` is a shift-out
// CYCLE COUNT, not a cell position -- shift-out reveals the chain in
// REVERSE position order (the cell nearest scan_out comes out first, at
// cyc=0). The mapping back to a global cell index (matching dut_wrapper's
// d_func/q numbering, chain*CHAIN_LEN + position) is:
//   global_index = chain*CHAIN_LEN + (CHAIN_LEN-1 - fail_cell_index)
// This mapping is only valid because scan_ctrl's shift-out is a pure shift.
// It was NOT, originally: an unintended second functional edge ran before the
// first shift, so the stream mixed two circuit states and a chain-1 mismatch
// appeared that the circuit's structure said was impossible. That
// contradiction was the symptom that exposed the scan_ctrl bug (see the
// README, "Bugs found"); the reversed ordering itself was never the problem.
// -----------------------------------------------------------------------------
module fail_mask_collector #(
    parameter int NUM_CHAINS = 2,
    parameter int CHAIN_LEN  = 8
)(
    input  logic                                    clk,
    input  logic                                    rst_n,
    input  logic                                    start,          // clears the mask for a new pattern
    input  logic                                    fail_valid,
    input  logic [NUM_CHAINS-1:0]                   fail_vec,       // ALL chains mismatching this cycle
    input  logic [$clog2(CHAIN_LEN)-1:0]            fail_cell_index,
    output logic [NUM_CHAINS*CHAIN_LEN-1:0]         fail_mask
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fail_mask <= '0;
        end else begin
            if (start) fail_mask <= '0;
            if (fail_valid) begin
                // Uses the full per-chain vector, not the serial chain id:
                // several chains can mismatch on the same shift-out cycle and
                // the serial entry can only name one of them.
                for (int c = 0; c < NUM_CHAINS; c++) begin
                    if (fail_vec[c])
                        fail_mask[c * CHAIN_LEN + (CHAIN_LEN - 1 - fail_cell_index)] <= 1'b1;
                end
            end
        end
    end

endmodule
