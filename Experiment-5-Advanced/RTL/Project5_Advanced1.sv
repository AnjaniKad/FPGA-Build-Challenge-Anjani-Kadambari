module Project5_Advanced1 (
    input  wire        FPGA_CLK1_50,
    input  wire [1:0]  KEY,
    input  wire [3:0]  SW,
    output wire [7:0]  LED
);

    wire clk   = FPGA_CLK1_50;
    wire rst_n = KEY[0];

    reg key1_prev;
    reg start;
    reg new_session;

    wire busy;
    wire done;
    wire [2:0] shift_index;
    wire [15:0] fail_mask;
    wire [7:0] candidate_sites;
    wire any_cell_failed;

    // Generate a one-cycle start pulse when KEY1 is pressed.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key1_prev  <= 1'b1;
            start      <= 1'b0;
            new_session <= 1'b0;
        end else begin
            key1_prev   <= KEY[1];
            start       <= key1_prev && !KEY[1];
            new_session <= key1_prev && !KEY[1];
        end
    end

    stage1_milestone_top #(
        .NUM_CHAINS (2),
        .CHAIN_LEN  (8),
        .NUM_PI     (4),
        .NUM_PO     (4),
        .NUM_FAULTS (8)
    ) u_stage1 (
        .clk                 (clk),
        .rst_n               (rst_n),
        .pi                  (SW),
        .po                  (),
        .fi_active           (1'b0),
        .fi_site             (3'b000),
        .fi_type             (2'b00),
        .chain_fault_active  (1'b0),
        .chain_fault_chain   (1'b0),
        .chain_fault_cell    (3'b000),
        .chain_fault_type    (2'b00),
        .start               (start),
        .chain_test_mode     (1'b0),
        .two_pattern_mode    (1'b0),
        .pattern_id          (20'b0),
        .busy                (busy),
        .done                (done),
        .shift_index         (shift_index),
        .shift_in_bits       (2'b00),
        .golden_bits         (2'b00),
        .new_session         (new_session),
        .fail_mask           (fail_mask),
        .candidate_sites     (candidate_sites),
        .any_cell_failed     (any_cell_failed)
    );

    assign LED = candidate_sites;

endmodule
