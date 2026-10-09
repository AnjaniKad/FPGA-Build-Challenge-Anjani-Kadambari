`timescale 1ns / 1ps

module mac_top_tb;

parameter MAX_W = 32;

reg clk;
reg rst_n;
reg [MAX_W-1:0] a;
reg [MAX_W-1:0] b;
reg [1:0] prec_sel;
reg acc_en;

wire [2*MAX_W:0] y;

mac_top #(.MAX_W(MAX_W)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .a(a),
    .b(b),
    .prec_sel(prec_sel),
    .acc_en(acc_en),
    .y(y)
);

always #5 clk = ~clk;

initial begin
    clk = 0;
    rst_n = 0;
    a = 0;
    b = 0;
    prec_sel = 0;
    acc_en = 0;

    #20 rst_n = 1;

    // INT4
    @(posedge clk);
    prec_sel = 2'b00; a = 3; b = 4; acc_en = 1;

    @(posedge clk);
    a = 2; b = 5;

    @(posedge clk);
    acc_en = 0;

    // INT8
    @(posedge clk);
    acc_en = 1; prec_sel = 2'b01;
    a = 8; b = 4;

    // INT16
    @(posedge clk);
    prec_sel = 2'b10;
    a = 16; b = 2;

    // INT32
    @(posedge clk);
    prec_sel = 2'b11;
    a = 100000; b = 2000;

    // SIGNED TESTS
    @(posedge clk);
    prec_sel = 2'b01;
    a = -8'sd3; b = 8'sd4;

    @(posedge clk);
    a = -8'sd8; b = -8'sd2;

    @(posedge clk);
    prec_sel = 2'b10;
    a = -16'sd100; b = 16'sd2;

    repeat(6) @(posedge clk);

    $finish;
end

endmodule