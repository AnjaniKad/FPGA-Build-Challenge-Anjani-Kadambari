`timescale 1ns / 1ps

module mac_core #(
    parameter DATA_W = 32
)(
    input wire clk,
    input wire rst_n,

    input wire signed [DATA_W-1:0] a,
    input wire signed [DATA_W-1:0] b,

    input wire acc_en,

    output reg signed [2*DATA_W:0] y
);

// Stage 1: multiplication
reg signed [2*DATA_W-1:0] mul_reg;

// Stage 2: accumulation
reg signed [2*DATA_W:0] acc_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mul_reg <= 0;
        acc_reg <= 0;
        y       <= 0;
    end 
    else begin
        // Stage 1
        mul_reg <= a * b;

        // Stage 2
        if (acc_en)
            acc_reg <= acc_reg + mul_reg;

        // Output
        y <= acc_reg;
    end
end

endmodule