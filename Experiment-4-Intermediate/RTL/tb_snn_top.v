`timescale 1ns / 1ps

module tb_snn_top;

    parameter NUM_IMAGES = 100;
    parameter TIMESTEPS  = 25;
    parameter INPUT_SIZE = 784;

    reg clk;
    reg reset;
    reg start;
    reg [INPUT_SIZE-1:0] input_spikes;

    wire [9:0] output_spikes;
    wire done;

    // ============================================================
    // SPIKE AND LABEL MEMORY
    // ============================================================

    reg [783:0] spike_memory [0:2499];
    reg [3:0]   label_memory [0:99];


    // ============================================================
    // TESTBENCH VARIABLES
    // ============================================================

    integer image;
    integer t;
    integer i;
    integer neuron;

    integer spike_count;

    integer output_spike_counts [0:9];

    integer predicted_digit;
    integer max_spikes;

    integer correct_count;
    integer total_count;


    // ============================================================
    // DUT
    // ============================================================

    snn_top dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .input_spikes(input_spikes),

        .output_spikes(output_spikes),
        .done(done)
    );


    // ============================================================
    // CLOCK
    // ============================================================

    always #5 clk = ~clk;


    // ============================================================
    // LOAD INPUT DATA
    // ============================================================

    initial begin

        $readmemb(
            "C:/Users/Lenovo/PycharmProjects/PythonProject1/weights/mnist_spikes_100.mem",
            spike_memory
        );

        $readmemh(
            "C:/Users/Lenovo/PycharmProjects/PythonProject1/weights/mnist_labels_100.mem",
            label_memory
        );

    end


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        clk = 0;
        reset = 1;
        start = 0;
        input_spikes = 784'b0;

        correct_count = 0;
        total_count = 0;


        // --------------------------------------------------------
        // Initial reset
        // --------------------------------------------------------

        #20;
        reset = 0;


        // --------------------------------------------------------
        // Header
        // --------------------------------------------------------

        $display("");
        $display("========================================");
        $display("       100-IMAGE MNIST SNN TEST");
        $display("========================================");
        $display("Images     = %0d", NUM_IMAGES);
        $display("Timesteps  = %0d", TIMESTEPS);
        $display("Input size = %0d", INPUT_SIZE);
        $display("========================================");
        $display("");


        // ========================================================
        // IMAGE LOOP
        // ========================================================

        for (image = 0; image < NUM_IMAGES; image = image + 1) begin


            // ----------------------------------------------------
            // Reset SNN before every image
            // ----------------------------------------------------

            reset = 1'b1;
            start = 1'b0;
            input_spikes = 784'b0;

            #10;

            reset = 1'b0;


            // ----------------------------------------------------
            // Clear output spike counters
            // ----------------------------------------------------

            for (neuron = 0; neuron < 10; neuron = neuron + 1)
                output_spike_counts[neuron] = 0;


            // ----------------------------------------------------
            // Image information
            // ----------------------------------------------------

            $display("----------------------------------------");

            $display(
                "IMAGE %0d | ACTUAL LABEL = %0d",
                image,
                label_memory[image]
            );

            $display("----------------------------------------");


            // ====================================================
            // TIMESTEP LOOP
            // ====================================================

            for (t = 0; t < TIMESTEPS; t = t + 1) begin


                // ------------------------------------------------
                // Load spike vector for current timestep
                // ------------------------------------------------

                input_spikes =
                    spike_memory[image * TIMESTEPS + t];


                // ------------------------------------------------
                // Count input spikes
                // ------------------------------------------------

                spike_count = 0;

                for (i = 0; i < INPUT_SIZE; i = i + 1) begin

                    if (input_spikes[i])
                        spike_count = spike_count + 1;

                end


                $display(
                    "Timestep %0d | Input spikes = %0d",
                    t,
                    spike_count
                );


                // ------------------------------------------------
                // Start FC computation
                // ------------------------------------------------

                #10;

                start = 1'b1;

                #10;

                start = 1'b0;


                // ------------------------------------------------
                // Wait for FC to finish
                // ------------------------------------------------

                wait(done == 1'b1);

                @(posedge clk);

                #1;


                // =================================================
                // PRINT FC CURRENTS
                // =================================================

                $display(
                    "Currents = %d %d %d %d %d %d %d %d %d %d",
                    dut.current_0,
                    dut.current_1,
                    dut.current_2,
                    dut.current_3,
                    dut.current_4,
                    dut.current_5,
                    dut.current_6,
                    dut.current_7,
                    dut.current_8,
                    dut.current_9
                );


                // =================================================
                // COUNT OUTPUT SPIKES
                // =================================================

                for (neuron = 0; neuron < 10; neuron = neuron + 1) begin

                    if (output_spikes[neuron])
                        output_spike_counts[neuron] =
                            output_spike_counts[neuron] + 1;

                end


                // ------------------------------------------------
                // Print output spikes
                // ------------------------------------------------

                $display(
                    "Timestep %0d | Output spikes = %b",
                    t,
                    output_spikes
                );

            end


            // ====================================================
            // FIND PREDICTED DIGIT
            // ====================================================

            predicted_digit = 0;

            max_spikes = output_spike_counts[0];


            for (neuron = 1; neuron < 10; neuron = neuron + 1) begin

                if (output_spike_counts[neuron] > max_spikes) begin

                    max_spikes =
                        output_spike_counts[neuron];

                    predicted_digit =
                        neuron;

                end

            end


            // ====================================================
            // PRINT SPIKE COUNTS
            // ====================================================

            $display("");

            $display("Spike counts:");

            for (neuron = 0; neuron < 10; neuron = neuron + 1) begin

                $display(
                    "  Neuron %0d = %0d",
                    neuron,
                    output_spike_counts[neuron]
                );

            end


            // ====================================================
            // CHECK PREDICTION
            // ====================================================

            if (predicted_digit == label_memory[image]) begin

                correct_count = correct_count + 1;

                $display(
                    "PREDICTION = %0d | ACTUAL = %0d | CORRECT",
                    predicted_digit,
                    label_memory[image]
                );

            end

            else begin

                $display(
                    "PREDICTION = %0d | ACTUAL = %0d | WRONG",
                    predicted_digit,
                    label_memory[image]
                );

            end


            total_count = total_count + 1;


            $display(
                "Running accuracy = %0d / %0d",
                correct_count,
                total_count
            );

            $display("");

        end


        // ========================================================
        // FINAL RESULTS
        // ========================================================

        $display("");
        $display("========================================");
        $display("        100-IMAGE TEST COMPLETE");
        $display("========================================");

        $display(
            "Correct predictions = %0d",
            correct_count
        );

        $display(
            "Total images        = %0d",
            total_count
        );

        $display(
            "Accuracy             = %0d%%",
            (correct_count * 100) / total_count
        );

        $display("========================================");


        $finish;

    end

endmodule
