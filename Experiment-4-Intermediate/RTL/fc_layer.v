`timescale 1ns / 1ps

module fc_layer #(
    parameter INPUT_SIZE   = 784,
    parameter OUTPUT_SIZE  = 10,
    parameter WEIGHT_WIDTH = 16,
    parameter ACC_WIDTH    = 32
)(
    input wire clk,
    input wire reset,
    input wire start,

    input wire [INPUT_SIZE-1:0] input_spikes,

    output reg signed [ACC_WIDTH-1:0] current_0,
    output reg signed [ACC_WIDTH-1:0] current_1,
    output reg signed [ACC_WIDTH-1:0] current_2,
    output reg signed [ACC_WIDTH-1:0] current_3,
    output reg signed [ACC_WIDTH-1:0] current_4,
    output reg signed [ACC_WIDTH-1:0] current_5,
    output reg signed [ACC_WIDTH-1:0] current_6,
    output reg signed [ACC_WIDTH-1:0] current_7,
    output reg signed [ACC_WIDTH-1:0] current_8,
    output reg signed [ACC_WIDTH-1:0] current_9,

    output reg done
);

    // 7840 trained weights
    reg signed [WEIGHT_WIDTH-1:0] weights [0:7839];

    // Load trained weights
    initial begin
        $readmemh("C:/Users/Lenovo/PycharmProjects/PythonProject1/weights/fc_weights.mem", weights);
    end

    integer i;

    reg signed [ACC_WIDTH-1:0] sum [0:9];

    always @(posedge clk) begin

        if (reset) begin

            current_0 <= 0;
            current_1 <= 0;
            current_2 <= 0;
            current_3 <= 0;
            current_4 <= 0;
            current_5 <= 0;
            current_6 <= 0;
            current_7 <= 0;
            current_8 <= 0;
            current_9 <= 0;

            done <= 1'b0;

        end

        else begin

            done <= 1'b0;

            if (start) begin

                // Temporary variables for accumulation
                sum[0] = 0;
                sum[1] = 0;
                sum[2] = 0;
                sum[3] = 0;
                sum[4] = 0;
                sum[5] = 0;
                sum[6] = 0;
                sum[7] = 0;
                sum[8] = 0;
                sum[9] = 0;

                // Accumulate all active input spikes
                for (i = 0; i < INPUT_SIZE; i = i + 1) begin

                    if (input_spikes[i]) begin

                        sum[0] = sum[0] + weights[i];
                        sum[1] = sum[1] + weights[784 + i];
                        sum[2] = sum[2] + weights[1568 + i];
                        sum[3] = sum[3] + weights[2352 + i];
                        sum[4] = sum[4] + weights[3136 + i];
                        sum[5] = sum[5] + weights[3920 + i];
                        sum[6] = sum[6] + weights[4704 + i];
                        sum[7] = sum[7] + weights[5488 + i];
                        sum[8] = sum[8] + weights[6272 + i];
                        sum[9] = sum[9] + weights[7056 + i];

                    end
                end

                // Output accumulated currents
                current_0 <= sum[0];
                current_1 <= sum[1];
                current_2 <= sum[2];
                current_3 <= sum[3];
                current_4 <= sum[4];
                current_5 <= sum[5];
                current_6 <= sum[6];
                current_7 <= sum[7];
                current_8 <= sum[8];
                current_9 <= sum[9];

                done <= 1'b1;

            end
        end
    end

endmodule
