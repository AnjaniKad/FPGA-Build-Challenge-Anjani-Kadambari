// uart_tx.v
// Transmitter: pulls a byte, shifts it out framed with start/parity/stop
// bits, timed by bit_tick (one pulse per bit period).

module uart_tx #(
    parameter DATA_BITS = 8
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [DATA_BITS-1:0] tx_byte,
    input  wire       tx_byte_valid,   // FIFO has data
    output reg         tx_byte_ack,    // pop strobe

    input  wire        bit_tick,       // 1 pulse per bit period
    input  wire        parity_en,
    input  wire        parity_odd,

    output reg          tx_line,
    output reg          tx_busy
);

    localparam ST_IDLE   = 3'd0,
               ST_START  = 3'd1,
               ST_DATA   = 3'd2,
               ST_PARITY = 3'd3,
               ST_STOP   = 3'd4;

    reg [2:0] state;
    reg [3:0] bit_index;
    reg [DATA_BITS-1:0] shift_reg;
    reg       parity_calc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            tx_line     <= 1'b1;      // idle high
            tx_busy     <= 1'b0;
            tx_byte_ack <= 1'b0;
            bit_index   <= 0;
            shift_reg   <= 0;
            parity_calc <= 1'b0;
        end else begin
            tx_byte_ack <= 1'b0;

            case (state)
                ST_IDLE: begin
                    tx_line <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_byte_valid) begin
                        shift_reg   <= tx_byte;
                        tx_byte_ack <= 1'b1;
                        parity_calc <= 1'b0;
                        bit_index   <= 0;
                        tx_busy     <= 1'b1;
                        state       <= ST_START;
                    end
                end

                ST_START: begin
                    if (bit_tick) begin
                        tx_line <= 1'b0;      // start bit
                        state   <= ST_DATA;
                    end
                end

                ST_DATA: begin
                    if (bit_tick) begin
                        tx_line     <= shift_reg[0];
                        parity_calc <= parity_calc ^ shift_reg[0];
                        shift_reg   <= {1'b0, shift_reg[DATA_BITS-1:1]};
                        if (bit_index == DATA_BITS - 1) begin
                            state <= parity_en ? ST_PARITY : ST_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end
                end

                ST_PARITY: begin
                    if (bit_tick) begin
                        tx_line <= parity_odd ? ~parity_calc : parity_calc;
                        state   <= ST_STOP;
                    end
                end

                ST_STOP: begin
                    if (bit_tick) begin
                        tx_line <= 1'b1;      // stop bit
                        state   <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
