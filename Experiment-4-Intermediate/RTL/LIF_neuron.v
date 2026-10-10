`timescale 1ns / 1ps

module lif_neuron #(
    parameter DATA_WIDTH = 32,
    parameter LEAK_SHIFT = 3
)(
    input wire clk,
    input wire reset,
    input wire enable,

    input wire signed [DATA_WIDTH-1:0] syn_current,
    input wire signed [DATA_WIDTH-1:0] threshold,

    output reg spike_out
);

    reg signed [DATA_WIDTH-1:0] membrane_potential;

    reg signed [DATA_WIDTH:0] leak_current;
    reg signed [DATA_WIDTH:0] membrane_next;

    always @(posedge clk) begin

        if (reset) begin

            membrane_potential <= 0;
            spike_out <= 1'b0;

        end

        else begin

            spike_out <= 1'b0;

            if (enable) begin

                // Leak = membrane / 2^LEAK_SHIFT
                leak_current = membrane_potential >>> LEAK_SHIFT;

                // LIF membrane update
                membrane_next =
                    membrane_potential
                    + syn_current
                    - leak_current;

                // Threshold check
                if (membrane_next >= threshold) begin

                    spike_out <= 1'b1;
                    membrane_potential <= 0;

                end

                else begin

                    membrane_potential <=
                        membrane_next[DATA_WIDTH-1:0];

                end

            end

        end

    end

endmodule
