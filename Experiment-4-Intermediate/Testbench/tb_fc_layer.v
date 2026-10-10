`timescale 1ns / 1ps

module tb_fc_layer;

    reg clk;
    reg reset;
    reg start;

    reg [783:0] input_spikes;

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

    wire done;


    // Instantiate FC layer
    fc_layer dut (
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


    // Clock: 10 ns period
    always #5 clk = ~clk;


    initial begin

        clk = 0;
        reset = 1;
        start = 0;
        input_spikes = 784'b0;

        // Reset
        #20;
        reset = 0;

        // ------------------------------------------------
        // Test 1:
        // Activate only input spike 0
        // ------------------------------------------------

        input_spikes[0] = 1'b1;

        #10;
        start = 1'b1;

        #10;
        start = 1'b0;

        #10;

        $display("--------------------------------");
        $display("TEST 1: input_spikes[0] = 1");
        $display("Current 0 = %d", current_0);
        $display("Current 1 = %d", current_1);
        $display("Current 2 = %d", current_2);
        $display("Current 3 = %d", current_3);
        $display("Current 4 = %d", current_4);
        $display("Current 5 = %d", current_5);
        $display("Current 6 = %d", current_6);
        $display("Current 7 = %d", current_7);
        $display("Current 8 = %d", current_8);
        $display("Current 9 = %d", current_9);
        $display("--------------------------------");


        // ------------------------------------------------
        // Test 2:
        // Activate three input spikes
        // ------------------------------------------------

        input_spikes = 784'b0;

        input_spikes[0]   = 1'b1;
        input_spikes[100] = 1'b1;
        input_spikes[500] = 1'b1;

        #10;
        start = 1'b1;

        #10;
        start = 1'b0;

        #10;

        $display("--------------------------------");
        $display("TEST 2: spikes at 0, 100, 500");
        $display("Current 0 = %d", current_0);
        $display("Current 1 = %d", current_1);
        $display("Current 2 = %d", current_2);
        $display("Current 3 = %d", current_3);
        $display("Current 4 = %d", current_4);
        $display("Current 5 = %d", current_5);
        $display("Current 6 = %d", current_6);
        $display("Current 7 = %d", current_7);
        $display("Current 8 = %d", current_8);
        $display("Current 9 = %d", current_9);
        $display("--------------------------------");


        #20;

        $finish;

    end

endmodule
