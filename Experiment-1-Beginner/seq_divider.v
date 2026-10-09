// seq_divider.v
// Sequential restoring-division divider: WIDTH cycles latency, 1 bit/cycle.
// Replaces a wide combinational divider (which won't meet timing on an
// FPGA) with a small iterative circuit. This is appropriate here because
// the NCO only needs a new step value occasionally (once per BRD lock
// window, not every cycle), so a multi-cycle divide is free in context.

module seq_divider #(
    parameter WIDTH = 48
) (
    input  wire             clk,
    input  wire             rst_n,

    input  wire             start,          // pulse to begin a new divide
    input  wire [WIDTH-1:0] dividend,
    input  wire [WIDTH-1:0] divisor,

    output reg              busy,
    output reg              done,           // 1-cycle pulse when quotient is valid
    output reg  [WIDTH-1:0] quotient
);

    reg [WIDTH-1:0] rem;
    reg [WIDTH-1:0] div_shift;
    reg [WIDTH-1:0] quo;
    reg [$clog2(WIDTH+1)-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            done     <= 1'b0;
            quotient <= 0;
            rem       <= 0;
            div_shift <= 0;
            quo       <= 0;
            count     <= 0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                rem       <= 0;
                div_shift <= dividend;
                quo       <= 0;
                count     <= WIDTH[$clog2(WIDTH+1)-1:0];
                busy      <= 1'b1;
            end else if (busy) begin
                // Restoring division, MSB-first: shift the next dividend
                // bit into the remainder, compare against divisor, and
                // either subtract (quotient bit = 1) or keep (bit = 0).
                reg [WIDTH-1:0] rem_shifted;
                reg [WIDTH-1:0] quo_next;
                rem_shifted = {rem[WIDTH-2:0], div_shift[WIDTH-1]};

                if (rem_shifted >= divisor) begin
                    rem      <= rem_shifted - divisor;
                    quo_next = {quo[WIDTH-2:0], 1'b1};
                end else begin
                    rem      <= rem_shifted;
                    quo_next = {quo[WIDTH-2:0], 1'b0};
                end

                quo       <= quo_next;
                div_shift <= div_shift << 1;
                count     <= count - 1'b1;

                if (count == 1) begin
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    quotient <= quo_next;
                end
            end
        end
    end

endmodule
