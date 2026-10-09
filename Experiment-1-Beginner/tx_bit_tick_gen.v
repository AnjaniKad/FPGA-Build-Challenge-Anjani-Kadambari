// tx_bit_tick_gen.v
// TX doesn't need oversampling -- it just needs one tick per bit period.
// Plain free-running divider, reloaded from whichever bit_period source
// (mirror or fixed) uart_top selects.

module tx_bit_tick_gen #(
    parameter CNT_WIDTH = 20
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [CNT_WIDTH-1:0]   bit_period,
    output reg                    bit_tick
);

    reg [CNT_WIDTH-1:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= 0;
            bit_tick <= 1'b0;
        end else if (bit_period == 0) begin
            cnt      <= 0;
            bit_tick <= 1'b0;   // no valid period yet -- hold off
        end else if (cnt >= bit_period - 1'b1) begin
            cnt      <= 0;
            bit_tick <= 1'b1;
        end else begin
            cnt      <= cnt + 1'b1;
            bit_tick <= 1'b0;
        end
    end

endmodule
