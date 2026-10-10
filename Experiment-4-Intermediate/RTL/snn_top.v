`timescale 1ns / 1ps

module snn_top #(
    parameter INPUT_SIZE = 784,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset,
    input wire start,
    input wire [INPUT_SIZE-1:0] input_spikes,

    output wire [9:0] output_spikes,
    output wire done
);

    // =========================================================
    // FC currents
    // =========================================================

    wire signed [31:0] current_0;
    wire signed [31:0] current_1;
    wire signed [31:0] current_2;
    wire signed [31:0] current_3;
    wire signed [31:0] current_4;
    wire signed [31:0] current_5;
    wire signed [31:0] current_6;
    wire signed [31:0] current_7;
    wire signed [31:0] current_8;
    wire signed [31:0] current_9;


    // =========================================================
    // FC layer
    // =========================================================

    fc_layer fc_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .input_spikes(input_spikes),

        .current_0(current_0),
        .current_1(current_1),
        .current_2(current_2),
        .current_3(current_3),
        .current_4(current_4),
        .current_5(current_5),
        .current_6(current_6),
        .current_7(current_7),
        .current_8(current_8),
        .current_9(current_9),

        .done(done)
    );


    // =========================================================
    // LIF enable
    //
    // FC asserts done when a new set of currents is ready.
    // We use done as the one-cycle LIF update enable.
    // =========================================================

    wire lif_enable;

    assign lif_enable = done;


    // =========================================================
    // LIF NEURON 0
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_0 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_0[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[0])
    );


    // =========================================================
    // LIF NEURON 1
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_1 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_1[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[1])
    );


    // =========================================================
    // LIF NEURON 2
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_2 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_2[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[2])
    );


    // =========================================================
    // LIF NEURON 3
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_3 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_3[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[3])
    );


    // =========================================================
    // LIF NEURON 4
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_4 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_4[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[4])
    );


    // =========================================================
    // LIF NEURON 5
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_5 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_5[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[5])
    );


    // =========================================================
    // LIF NEURON 6
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_6 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_6[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[6])
    );


    // =========================================================
    // LIF NEURON 7
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_7 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_7[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[7])
    );


    // =========================================================
    // LIF NEURON 8
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_8 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_8[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[8])
    );


    // =========================================================
    // LIF NEURON 9
    // =========================================================

    lif_neuron #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEAK_SHIFT(3)
    ) lif_9 (
        .clk(clk),
        .reset(reset),
        .enable(lif_enable),
        .syn_current(current_9[DATA_WIDTH-1:0]),
        .threshold(32'sd1280),
        .spike_out(output_spikes[9])
    );

endmodule
