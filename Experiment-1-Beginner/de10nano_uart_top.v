`timescale 1ns/1ps

module de10nano_uart_top (
    // DE10-Nano 50 MHz clock
    input  wire clk,

    // Active-low reset
    input  wire rst_n,

    // UART pins
    input  wire uart_rx,
    output wire uart_tx,

    // LEDs
    output wire [7:0] LED
);

    // --------------------------------------------------
    // UART internal signals
    // --------------------------------------------------

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_ready;

    wire [7:0] tx_data;
    wire       tx_valid;
    wire       tx_ready;

    wire       baud_locked;
    wire       error_flag;

    // --------------------------------------------------
    // Register interface
    // Keep UART configuration at reset defaults
    // --------------------------------------------------

    wire [3:0]  reg_addr  = 4'h0;
    wire [31:0] reg_wdata = 32'h00000000;
    wire        reg_we    = 1'b0;
    wire [31:0] reg_rdata;

    // --------------------------------------------------
    // UART core
    // --------------------------------------------------

    uart_top #(
        .CNT_WIDTH  (20),
        .DATA_BITS  (8),
        .FIFO_DEPTH (16)
    ) u_uart (
        .clk          (clk),
        .rst_n        (rst_n),

        .rx_line      (uart_rx),
        .tx_line      (uart_tx),

        .reg_addr     (reg_addr),
        .reg_wdata    (reg_wdata),
        .reg_we       (reg_we),
        .reg_rdata    (reg_rdata),

        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .rx_ready     (rx_ready),

        .tx_data      (tx_data),
        .tx_valid     (tx_valid),
        .tx_ready     (tx_ready),

        .baud_locked_o(baud_locked),
        .error_flag_o (error_flag)
    );

    // --------------------------------------------------
    // UART LOOPBACK / ECHO
    // Every received byte is transmitted back.
    // --------------------------------------------------

    assign tx_data  = rx_data;
    assign tx_valid = rx_valid;
    assign rx_ready = tx_ready;

    // --------------------------------------------------
    // LED display
    //
    // LED[7:0] = last received byte
    // LED[8]   = baud locked
    // LED[9]   = error flag
    // --------------------------------------------------

    reg [7:0] last_byte;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            last_byte <= 8'h00;
        else if (rx_valid)
            last_byte <= rx_data;
    end

    assign LED = last_byte;

endmodule