// error_controller.v
// Aggregates RX/FIFO error events. Forces the baud detector back into
// acquisition (relock_req) once errors exceed a configurable threshold
// within a decay window, rather than on the very first glitch.

module error_controller #(
    parameter CNT_WIDTH = 8
) (
    input  wire clk,
    input  wire rst_n,

    input  wire framing_err,
    input  wire parity_err,
    input  wire fifo_overrun,

    input  wire [CNT_WIDTH-1:0] relock_threshold,  // from register interface
    input  wire frame_good,                        // good frame -> decays error count

    output reg  relock_req,     // 1-cycle pulse to baud_rate_detector
    output reg  error_flag,
    output reg  [CNT_WIDTH-1:0] error_count
);

    wire any_error = framing_err | parity_err | fifo_overrun;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_count <= 0;
            error_flag  <= 1'b0;
            relock_req  <= 1'b0;
        end else begin
            error_flag <= any_error;
            relock_req <= 1'b0;

            if (any_error) begin
                if (error_count != {CNT_WIDTH{1'b1}})
                    error_count <= error_count + 1'b1;
            end else if (frame_good && error_count != 0) begin
                error_count <= error_count - 1'b1;  // decay on sustained good frames
            end

            if (error_count >= relock_threshold) begin
                relock_req  <= 1'b1;
                error_count <= 0;
            end
        end
    end

endmodule
