`timescale 1ns/1ps

module mesh_tb;

localparam FLIT_SIZE = 40;
localparam COORD_W = 4;
localparam BUFFER_DEPTH = 8;
localparam NUM_VCS = 2;
localparam MESH_X = 2;
localparam MESH_Y = 2;
localparam NUM_ROUTERS = MESH_X * MESH_Y;

reg clk = 0;
reg rst_n = 0;
always #5 clk = ~clk;

reg [NUM_ROUTERS*FLIT_SIZE-1:0] local_in_flit_flat;
reg [NUM_ROUTERS-1:0] local_in_valid;
reg [NUM_ROUTERS*NUM_VCS-1:0] local_in_vc_flat;
wire [NUM_ROUTERS*FLIT_SIZE-1:0] local_out_flit_flat;
wire [NUM_ROUTERS-1:0] local_out_valid;
wire [NUM_ROUTERS*NUM_VCS-1:0] local_out_vc_flat;
wire [NUM_ROUTERS*NUM_VCS-1:0] local_credit_flat;
reg [NUM_ROUTERS*NUM_VCS-1:0] local_ds_credit_flat;

mesh #(
    .FLIT_SIZE(FLIT_SIZE),
    .COORD_W(COORD_W),
    .BUFFER_DEPTH(BUFFER_DEPTH),
    .NUM_VCS(NUM_VCS),
    .MESH_X(MESH_X),
    .MESH_Y(MESH_Y)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .local_in_flit_flat(local_in_flit_flat),
    .local_in_valid(local_in_valid),
    .local_in_vc_flat(local_in_vc_flat),
    .local_out_flit_flat(local_out_flit_flat),
    .local_out_valid(local_out_valid),
    .local_out_vc_flat(local_out_vc_flat),
    .local_credit_flat(local_credit_flat),
    .local_ds_credit_flat(local_ds_credit_flat)
);

function [FLIT_SIZE-1:0] mkflit;
    input is_head, is_tail;
    input [COORD_W-1:0] dx, dy;
    input [31:0] payload;
    localparam PAY_W = FLIT_SIZE - 3 - 2*COORD_W;
    begin
        mkflit = {1'b1, is_head, is_tail, dx, dy, payload[PAY_W-1:0]};
    end
endfunction

task automatic send_packet;
    input integer source;
    input [COORD_W-1:0] dx, dy;
    input [31:0] payload;
    begin
        @(negedge clk);
        local_in_flit_flat[source*FLIT_SIZE +: FLIT_SIZE] =
            mkflit(1, 0, dx, dy, payload);
        local_in_valid[source] = 1'b1;
        local_in_vc_flat[source*NUM_VCS +: NUM_VCS] = 2'b01;
        @(negedge clk);
        local_in_flit_flat[source*FLIT_SIZE +: FLIT_SIZE] =
            mkflit(0, 1, dx, dy, payload + 1'b1);
        @(negedge clk);
        local_in_flit_flat[source*FLIT_SIZE +: FLIT_SIZE] = 0;
        local_in_valid[source] = 1'b0;
        local_in_vc_flat[source*NUM_VCS +: NUM_VCS] = 0;
    end
endtask

reg [FLIT_SIZE-1:0] seen_flit [0:NUM_ROUTERS-1][0:1];
reg [NUM_VCS-1:0] seen_vc [0:NUM_ROUTERS-1][0:1];
integer seen_count [0:NUM_ROUTERS-1];
integer n;
always @(posedge clk) begin
    #1;
    for (n=0; n<NUM_ROUTERS; n=n+1)
        if (local_out_valid[n]) begin
            if (seen_count[n] < 2) begin
                seen_flit[n][seen_count[n]] =
                    local_out_flit_flat[n*FLIT_SIZE +: FLIT_SIZE];
                seen_vc[n][seen_count[n]] =
                    local_out_vc_flat[n*NUM_VCS +: NUM_VCS];
            end
            seen_count[n] = seen_count[n] + 1;
        end
end

integer errors = 0;
integer i;
initial begin
    local_in_flit_flat = 0;
    local_in_valid = 0;
    local_in_vc_flat = 0;
    local_ds_credit_flat = {(NUM_ROUTERS*NUM_VCS){1'b1}};
    for (i=0; i<NUM_ROUTERS; i=i+1)
        seen_count[i] = 0;

    #40 rst_n = 1;
    repeat (2) @(posedge clk);

    send_packet(0, 1, 1, 32'h100);
    repeat (10) @(posedge clk);
    if (seen_count[3] != 2 ||
        seen_flit[3][0] !== mkflit(1, 0, 1, 1, 32'h100) ||
        seen_flit[3][1] !== mkflit(0, 1, 1, 1, 32'h101) ||
        seen_vc[3][0] !== 2'b01 || seen_vc[3][1] !== 2'b01)
        errors = errors + 1;

    send_packet(3, 0, 0, 32'h200);
    repeat (10) @(posedge clk);
    if (seen_count[0] != 2 ||
        seen_flit[0][0] !== mkflit(1, 0, 0, 0, 32'h200) ||
        seen_flit[0][1] !== mkflit(0, 1, 0, 0, 32'h201) ||
        seen_vc[0][0] !== 2'b01 || seen_vc[0][1] !== 2'b01)
        errors = errors + 1;

    if (seen_count[1] != 0 || seen_count[2] != 0)
        errors = errors + 1;

    if (errors == 0) begin
        $display("MESH TEST PASSED");
        $finish;
    end
    $display("MESH TEST FAILED: %0d errors", errors);
    $finish_and_return(1);
end

initial begin
    #2000;
    $display("MESH TEST FAILED: watchdog timeout");
    $finish_and_return(1);
end

endmodule
