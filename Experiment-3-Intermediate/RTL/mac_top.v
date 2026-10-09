`timescale 1ns / 1ps

module mac_top #(
    parameter MAX_W = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [MAX_W-1:0]     a,
    input  wire [MAX_W-1:0]     b,
    input  wire [1:0]           prec_sel,  // 00: INT4, 01: INT8, 10: INT16
    input  wire                 acc_en,
    output wire [2*MAX_W:0]     y
);
wire [MAX_W-1:0] a_eff;
wire [MAX_W-1:0] b_eff;

precision_ctrl #(
     .MAX_W(MAX_W)
) u_prec (
        .a_in(a),
        .b_in(b),
        .prec_sel(prec_sel),
        .a_eff(a_eff),
        .b_eff(b_eff)
);

mac_core #(
     .DATA_W(MAX_W)
) u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .a(a_eff),
        .b(b_eff),
        .acc_en(acc_en),
        .y(y)
);

endmodule


