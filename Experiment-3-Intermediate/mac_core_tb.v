`timescale 1ns / 1ps

module mac_core_tb;

parameter DATA_W = 32;

reg clk;
reg rst_n;
reg signed [DATA_W-1:0] a;
reg signed [DATA_W-1:0] b;
reg acc_en;

wire signed [2*DATA_W:0] y;

mac_core #(.DATA_W(DATA_W)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .a(a),
    .b(b),
    .acc_en(acc_en),
    .y(y)
);

always #5 clk = ~clk;

initial begin
    clk = 0;
    rst_n = 0;
    a = 0;
    b = 0;
    acc_en = 0;

    #20 rst_n = 1;

    // 3 * 4
    @(posedge clk);
    a = 3; b = 4; acc_en = 1;

    // 2 * 5
    @(posedge clk);
    a = 2; b = 5;

    // hold
    @(posedge clk);
    acc_en = 0;

    // 1 * 6
    @(posedge clk);
    acc_en = 1;
    a = 1; b = 6;

    repeat(5) @(posedge clk);

    $finish;
end

endmodule