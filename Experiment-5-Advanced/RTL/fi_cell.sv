// -----------------------------------------------------------------------------
// fi_cell.sv
// Fault injection primitive. Inserted on candidate nets by the preprocessing
// script (per PROJECT_CONTEXT.md / RTL_ARCHITECTURE.md 3.2). Runtime-selects
// one of: no fault, stuck-at-0, stuck-at-1, or a one-cycle-late transition
// ("slow") fault. Cost target: ~2-3 ALMs + 1 FF per instrumented site --
// do NOT instrument every net in the DUT (see dut_wrapper.sv header).
// -----------------------------------------------------------------------------
module fi_cell #(
    parameter int SITE_ID    = 0,
    parameter int NUM_FAULTS = 256   // must match the fi_site width used site-wide
)(
    input  logic clk,
    input  logic net_in,
    output logic net_out,
    input  logic fi_active,
    input  logic [$clog2(NUM_FAULTS)-1:0] fi_site,
    input  logic [1:0]                    fi_type   // 00=none 01=SA0 10=SA1 11=slow
);

    logic sel, dly;
    assign sel = fi_active && (fi_site == SITE_ID);

    always_ff @(posedge clk) dly <= net_in;   // slow-to-transition model: one cycle late

    always_comb begin
        unique case ({sel, fi_type})
            3'b101:  net_out = 1'b0;   // SA0
            3'b110:  net_out = 1'b1;   // SA1
            3'b111:  net_out = dly;    // transition fault (one-cycle late)
            default: net_out = net_in; // not selected, or fi_type == 00 (none)
        endcase
    end

endmodule
