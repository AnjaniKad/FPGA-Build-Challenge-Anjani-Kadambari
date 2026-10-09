// baud_nco.v
// Phase-accumulator based oversample-tick generator. Converts the detector's
// bit_period estimate into a step size; a step-size update mid-stream does
// not glitch the current bit's sampling -- it just gradually re-centers,
// which is the actual "self-correcting" mechanism.
//
// The step-size division is done with a sequential divider (seq_divider),
// not combinationally. A 48-bit-wide combinational divider does not close
// timing on an FPGA; a multi-cycle divide is free here because bit_period
// only updates occasionally (once per BRD lock window), not every cycle.

module baud_nco #(
    parameter CNT_WIDTH = 20,
    parameter ACC_WIDTH = 24,
    parameter OVERSAMPLE = 16
) (
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire [CNT_WIDTH-1:0] bit_period,        // from baud_rate_detector
    input  wire                 bit_period_valid,
    input  wire                 update_en,         // e.g. gate with baud_locked
    input  wire                 phase_sync,        // pulse on detected start-bit edge:
                                                     // realigns phase_acc so the first
                                                     // os_tick timing is deterministic
                                                     // relative to the edge, instead of
                                                     // wherever the free-running phase
                                                     // happened to be (which otherwise
                                                     // varies randomly frame to frame
                                                     // by up to one full oversample tick)

    output reg                  os_tick,           // pulses OVERSAMPLE times per bit period
    output reg                  bit_tick           // pulses once per bit period (os_tick[15])
);

    localparam DIV_WIDTH = 2 * ACC_WIDTH;

    reg [ACC_WIDTH-1:0] phase_acc;
    reg [ACC_WIDTH-1:0] step_reg;
    reg [$clog2(OVERSAMPLE)-1:0] os_count;

    // step = round(2^ACC_WIDTH * OVERSAMPLE / bit_period)
    // Rounding (not truncating) matters: plain integer division always
    // biases the step slightly low, which systematically stretches the
    // generated bit period on every single bit. That bias compounds with
    // any measurement error from the BRD and can accumulate enough phase
    // drift by the end of a frame to mis-sample a bit, especially across
    // long same-value runs where there's no edge to visually reveal it.
    localparam [DIV_WIDTH-1:0] NUMERATOR_BASE = (1 << ACC_WIDTH) * OVERSAMPLE;

    wire [DIV_WIDTH-1:0] divisor_ext = {{(DIV_WIDTH-CNT_WIDTH){1'b0}}, bit_period};
    wire [DIV_WIDTH-1:0] round_term  = divisor_ext >> 1;
    wire [DIV_WIDTH-1:0] dividend    = NUMERATOR_BASE + round_term;

    // Cold-start bypass: if step_reg is still 0, no os_tick has ever been
    // generated, so RX can never reach an idle point to satisfy update_en.
    // Let the very first estimate through unconditionally; every update
    // after that respects update_en (e.g. gated to RX-idle periods).
    wire accept_update = bit_period_valid && (bit_period != 0) &&
                          (update_en || (step_reg == 0));

    // A new accept_update can in principle arrive while a previous divide
    // is still running (48 cycles here, vs. BRD updates that arrive far
    // less often in practice) -- latch it as pending rather than drop it.
    reg pending;
    wire div_busy, div_done;
    wire [DIV_WIDTH-1:0] div_quotient;
    wire div_start = (accept_update || pending) && !div_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
        end else if (accept_update && div_busy) begin
            pending <= 1'b1;
        end else if (div_start) begin
            pending <= 1'b0;
        end
    end

    seq_divider #(.WIDTH(DIV_WIDTH)) u_div (
        .clk(clk), .rst_n(rst_n),
        .start(div_start),
        .dividend(dividend),
        .divisor(divisor_ext),
        .busy(div_busy), .done(div_done), .quotient(div_quotient)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_reg <= 0;
        end else if (div_done) begin
            step_reg <= div_quotient[ACC_WIDTH-1:0];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 0;
            os_tick   <= 1'b0;
            os_count  <= 0;
            bit_tick  <= 1'b0;
        end else if (phase_sync) begin
            // Realign phase to the just-detected start-bit edge. Suppress
            // any tick this cycle so os_count in the RX FSM (which also
            // resets to 0 on this same edge) starts from a clean, known
            // relationship to phase_acc.
            phase_acc <= 0;
            os_tick   <= 1'b0;
            os_count  <= 0;
            bit_tick  <= 1'b0;
        end else begin
            os_tick  <= 1'b0;
            bit_tick <= 1'b0;

            if (step_reg != 0) begin
                {os_tick, phase_acc} <= phase_acc + step_reg;
                if (phase_acc + step_reg < phase_acc) begin
                    // wrapped -> one oversample tick
                    if (os_count == OVERSAMPLE - 1) begin
                        os_count <= 0;
                        bit_tick <= 1'b1;
                    end else begin
                        os_count <= os_count + 1'b1;
                    end
                end
            end
        end
    end

endmodule
