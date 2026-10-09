`timescale 1ns / 1ps

module precision_ctrl #(
    parameter MAX_W = 32
)(
    input  wire [MAX_W-1:0] a_in,
    input  wire [MAX_W-1:0] b_in,
    input  wire [1:0] prec_sel,

    output reg [MAX_W-1:0] a_eff,
    output reg [MAX_W-1:0] b_eff
);

always @(*) begin
    // default : zero
    a_eff = {MAX_W{1'b0}};
    b_eff = {MAX_W{1'b0}};

    case (prec_sel)
        2'b00: begin
            // 4bits like its so a can 0 to 15 and b can be 0 to 15 so its 4(bits)x4(bits)
            a_eff = {{(MAX_W-4){a_in[3]}}, a_in[3:0]};
            b_eff = {{(MAX_W-4){b_in[3]}}, b_in[3:0]};
        end

        2'b01: begin
            // 8x8 
            a_eff = {{(MAX_W-8){a_in[7]}}, a_in[7:0]};
            b_eff = {{(MAX_W-8){b_in[7]}}, b_in[7:0]};
        end

        2'b10: begin
            // 16x16
           a_eff = {{(MAX_W-16){a_in[15]}}, a_in[15:0]};
           b_eff = {{(MAX_W-16){b_in[15]}}, b_in[15:0]};
        end

        2'b11: begin // 32x32
            a_eff       = a_in;
            b_eff       = b_in;
        end
    endcase
end

endmodule
