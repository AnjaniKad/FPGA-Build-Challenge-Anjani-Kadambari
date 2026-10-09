// -----------------------------------------------------------------------------
// stage0_milestone_top.sv
// Integrates scan_ctrl + dut_wrapper (the first end-to-end milestone,
// RTL_ARCHITECTURE.md 8, items 2-4): functional fault injection (fi_*),
// scan-chain fault injection (chain_fault_*), Stage 0 chain diagnosis,
// shift/capture/compare (single-capture, or two-vector via two_pattern_mode)
// and fail-log reporting (serial entry + the complete per-cycle fail_vec),
// against a placeholder DUT. Stage 1 wraps this module; see
// stage1_milestone_top.sv. csr_regfile / mem_arbiter / Avalon / DDR integration is
// deliberately not attempted here -- see scan_ctrl.sv header for the exact
// list of what's simplified and why.
// -----------------------------------------------------------------------------
module stage0_milestone_top #(
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

    output logic                          fail_valid,
    output logic [19:0]                   fail_pattern_id,
    output logic [$clog2(NUM_CHAINS)-1:0] fail_chain_id,
    output logic [$clog2(CHAIN_LEN)-1:0]  fail_cell_index,
    output logic [NUM_CHAINS-1:0]         fail_vec,

    output logic [NUM_CHAINS-1:0]                   chain_ok,
    output logic [NUM_CHAINS*$clog2(CHAIN_LEN)-1:0] chain_first_bad_cell_flat
);

    logic                  scan_en, launch_pulse, capture_pulse;
    logic [NUM_CHAINS-1:0] scan_in, scan_out;

    scan_ctrl #(.NUM_CHAINS(NUM_CHAINS), .CHAIN_LEN(CHAIN_LEN)) u_scan_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(start), .chain_test_mode(chain_test_mode), .two_pattern_mode(two_pattern_mode),
        .pattern_id(pattern_id),
        .busy(busy), .done(done),
        .shift_index(shift_index), .shift_in_bits(shift_in_bits), .golden_bits(golden_bits),
        .fail_valid(fail_valid), .fail_pattern_id(fail_pattern_id),
        .fail_chain_id(fail_chain_id), .fail_cell_index(fail_cell_index), .fail_vec(fail_vec),
        .chain_ok(chain_ok), .chain_first_bad_cell_flat(chain_first_bad_cell_flat),
        .scan_en(scan_en), .launch_pulse(launch_pulse), .capture_pulse(capture_pulse),
        .scan_in(scan_in), .scan_out(scan_out)
    );

    dut_wrapper #(
        .NUM_CHAINS(NUM_CHAINS), .CHAIN_LEN(CHAIN_LEN),
        .NUM_PI(NUM_PI), .NUM_PO(NUM_PO), .NUM_FAULTS(NUM_FAULTS)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .scan_en(scan_en), .scan_in(scan_in), .scan_out(scan_out),
        .pi(pi), .po(po),
        .fi_active(fi_active), .fi_site(fi_site), .fi_type(fi_type),
        .chain_fault_active(chain_fault_active), .chain_fault_chain(chain_fault_chain),
        .chain_fault_cell(chain_fault_cell), .chain_fault_type(chain_fault_type)
    );

endmodule
