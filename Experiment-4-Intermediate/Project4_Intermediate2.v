`timescale 1ns / 1ps

// Lightweight DE10-Nano bring-up design for Project 4.
// This is a hardware demo of one LIF neuron, NOT the full MNIST classifier.
// It deliberately avoids the 784 x 10 fully-parallel datapath that did not fit.

module Project4_Intermediate2 (
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,       // active-low push buttons
    input  wire [3:0]  SW,
    output reg  [7:0]  LED
);

    // KEY[0] is reset; released = 1, pressed = 0.
    wire reset = ~KEY[0];

    // Slow the 50 MHz board clock down to a visible update rate.
    // Tick occurs once every 50,000 clock cycles (1 kHz).
    reg [15:0] divider = 16'd0;
    reg tick = 1'b0;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            divider <= 16'd0;
            tick    <= 1'b0;
        end else if (divider == 16'd49999) begin
            divider <= 16'd0;
            tick    <= 1'b1;
        end else begin
            divider <= divider + 1'b1;
            tick    <= 1'b0;
        end
    end

    // Generate a small current pulse on every tick.
    // SW[0] selects pulse strength; SW[1] can disable pulses for observation.
    wire signed [15:0] syn_current =
        (SW[1]) ? 16'sd0 : (SW[0] ? 16'sd160 : 16'sd80);

    wire spike;
    wire signed [15:0] threshold = 16'sd256;

    lif_neuron #(
        .DATA_WIDTH(16),
        .LEAK_SHIFT(3)
    ) demo_neuron (
        .clk(CLOCK_50),
        .reset(reset),
        .enable(tick),
        .syn_current(syn_current),
        .threshold(threshold),
        .spike_out(spike)
    );

    // Hold the most recent spike on LED[0] long enough to see it.
    // LED[7:4] show a simple activity counter; LED[3:1] identify demo mode.
    reg [23:0] hold_counter = 24'd0;
    reg [3:0] spike_count = 4'd0;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            hold_counter <= 24'd0;
            spike_count  <= 4'd0;
            LED           <= 8'b00000000;
        end else begin
            if (spike) begin
                hold_counter <= 24'd8_000_000; // about 160 ms at 50 MHz
                spike_count  <= spike_count + 1'b1;
            end else if (hold_counter != 0) begin
                hold_counter <= hold_counter - 1'b1;
            end

            LED[0]   <= (hold_counter != 0) | spike;
            LED[3:1] <= 3'b101;               // indicates the LIF demo is running
            LED[7:4] <= spike_count;
        end
    end

endmodule
