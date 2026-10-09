// rx_line_sync.v
// Double-flop synchronizer for the async RX pad, plus edge strobes used by
// the baud detector and RX FSM. This is the ONLY block that touches the raw
// pad signal directly; everything downstream uses rx_sync.

module rx_line_sync (
    input  wire clk,
    input  wire rst_n,
    input  wire rx_line,      // raw async pad input

    output reg  rx_sync,      // synchronized, glitch-free (metastability-safe)
    output wire rx_edge,      // pulses 1 clk on any transition (rise or fall)
    output wire rx_fall,      // pulses 1 clk on falling edge (start-bit candidate)
    output wire rx_rise       // pulses 1 clk on rising edge
);

    reg meta_ff;
    reg sync_ff;
    reg sync_ff_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_ff   <= 1'b1;
            sync_ff   <= 1'b1;
            sync_ff_d <= 1'b1;
        end else begin
            meta_ff   <= rx_line;
            sync_ff   <= meta_ff;
            sync_ff_d <= sync_ff;
        end
    end

    always @(*) rx_sync = sync_ff;

    assign rx_edge = (sync_ff != sync_ff_d);
    assign rx_fall = (sync_ff_d == 1'b1) && (sync_ff == 1'b0);
    assign rx_rise = (sync_ff_d == 1'b0) && (sync_ff == 1'b1);

endmodule
