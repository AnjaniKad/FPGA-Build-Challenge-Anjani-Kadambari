`timescale 1ns / 1ps

module tb_synapse_lif;

    reg clk;
    reg reset;

    reg spike_pos;
    reg spike_neg;

    reg signed [7:0]  weight;
    reg signed [15:0] threshold;

    wire signed [15:0] syn_current;
    wire                syn_valid;
    wire                spike_out;

    // Synapse
    synapse #(
        .DATA_WIDTH(16),
        .WEIGHT_WIDTH(8),
        .DECAY_SHIFT(3)
    ) u_synapse (
        .clk(clk),
        .reset(reset),
        .spike_pos(spike_pos),
        .spike_neg(spike_neg),
        .weight(weight),
        .syn_current(syn_current),
        .syn_valid(syn_valid)
    );

    // LIF neuron
    lif_neuron #(
        .DATA_WIDTH(16),
        .LEAK_SHIFT(3),
        .REF_WIDTH(8),
        .REFRACTORY_PERIOD(3)
    ) u_lif (
        .clk(clk),
        .reset(reset),
        .syn_current(syn_current),
        .syn_valid(syn_valid),
        .threshold(threshold),
        .spike_out(spike_out)
    );

    // 100 MHz clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        reset     = 1'b1;
        spike_pos = 1'b0;
        spike_neg = 1'b0;

        // 8-bit signed weight
        weight    = 8'sd100;

        // LIF threshold
        threshold = 16'sd300;

        #20;
        reset = 1'b0;

        // Positive input events
        #10;
        spike_pos = 1'b1;

        #10;
        spike_pos = 1'b0;

        #10;
        spike_pos = 1'b1;

        #10;
        spike_pos = 1'b0;

        #10;
        spike_pos = 1'b1;

        #10;
        spike_pos = 1'b0;

        #10;
        spike_pos = 1'b1;

        #10;
        spike_pos = 1'b0;

        #100;

        $finish;
    end

    // Simulation log
    always @(posedge clk) begin
        $display(
            "t=%0t | pos=%b | neg=%b | valid=%b | current=%d | membrane=%d | spike=%b",
            $time,
            spike_pos,
            spike_neg,
            syn_valid,
            syn_current,
            u_lif.membrane_potential,
            spike_out
        );
    end

    initial begin
        $dumpfile("synapse_lif.vcd");
        $dumpvars(0, tb_synapse_lif);
    end

endmodule
