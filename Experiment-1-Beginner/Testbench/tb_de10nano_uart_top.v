// =============================================================================
// tb_de10nano_uart_top.v
// Self-checking board-level testbench for de10nano_uart_top
//
// Target simulator : ModelSim / Questa, Icarus Verilog (-g2012)
// Clock            : 50 MHz (20 ns)
// UART             : Auto-baud; sends 0x55 preamble, then tests echo loopback
//
// Tests
//   T1 Reset defaults: UART TX idle, LEDs clear
//   T2 Auto-baud lock after 0x55 preamble
//   T3 LED[8] indicates baud lock
//   T4 RX byte updates LED[7:0]
//   T5 Received bytes are echoed on uart_tx, in order
//   T6 Multiple bytes and LED reflects the last received byte
//   T7 Error LED behavior (basic observation; pulse may be brief)
//
// Note:
//   This testbench tests the DE10-Nano wrapper, not the internal register bus.
//   The wrapper ties the register interface to constants, so register read/write
//   tests belong in tb_uart_top.v.
// =============================================================================
`timescale 1ns/1ps

module tb_de10nano_uart_top;

    parameter CLK_PERIOD = 20;  // ns
    parameter BIT_CLKS   = 434; // nominal 115200 baud at 50 MHz
    parameter DATA_BITS  = 8;

    reg         clk;
    reg         rst_n;
    reg         uart_rx;
    wire        uart_tx;
    wire [9:0]  LED;

    de10nano_uart_top dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .LED     (LED)
    );

    // Clock generation
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt;
    integer fail_cnt;
    integer i;
    integer preamble_count;
    integer tx_count;
    integer tx_par_err;
    integer tx_stop_err;
    integer tx_bit_clks;

    reg [7:0] tx_received [0:255];
    reg [7:0] expected [0:255];

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition) begin
                pass_cnt = pass_cnt + 1;
                $display("[%0t] PASS: %0s", $time, message);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[%0t] FAIL: %0s", $time, message);
            end
        end
    endtask

    // Drive an 8N1 UART frame, LSB first.
    task uart_send;
        input [7:0] data;
        input integer bit_clks;
        integer b;
        begin
            uart_rx = 1'b0;
            #(bit_clks * CLK_PERIOD);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx = data[b];
                #(bit_clks * CLK_PERIOD);
            end
            uart_rx = 1'b1;
            #(bit_clks * CLK_PERIOD);
        end
    endtask

    task wait_frames;
        input integer n;
        input integer bit_clks;
        begin
            #(n * 10 * bit_clks * CLK_PERIOD);
        end
    endtask

    // Independent UART receiver for uart_tx. Samples data bits near their
    // centers. Assumes 8N1 and a known bit period.
    reg [7:0] tx_shift;
    integer tx_sample;
    always @(negedge uart_tx) begin
        if (rst_n) begin
            // Falling edge is start bit; sample data bit 0 at 1.5 bit periods.
            #(tx_bit_clks * CLK_PERIOD * 3 / 2);
            for (tx_sample = 0; tx_sample < 8; tx_sample = tx_sample + 1) begin
                tx_shift[tx_sample] = uart_tx;
                #(tx_bit_clks * CLK_PERIOD);
            end
            if (uart_tx !== 1'b1)
                tx_stop_err = tx_stop_err + 1;
            tx_received[tx_count] = tx_shift;
            tx_count = tx_count + 1;
        end
    end

    task check_tx_expected;
        input integer n;
        input [8*100-1:0] message;
        integer j;
        reg ok;
        begin
            ok = (tx_count == n);
            for (j = 0; j < n; j = j + 1) begin
                if (tx_received[j] !== expected[j]) begin
                    ok = 1'b0;
                    $display("        TX mismatch index %0d: got %02h expected %02h",
                             j, tx_received[j], expected[j]);
                end
            end
            if (!ok)
                $display("        tx_count=%0d expected_count=%0d", tx_count, n);
            check(ok, message);
        end
    endtask

    // Send enough 0x55 bytes to acquire lock. A lock can occur during a frame,
    // so the loop checks between complete preamble frames.
    task acquire_lock;
        input integer bit_clks;
        begin
            preamble_count = 0;
            while ((LED[8] !== 1'b1) && (preamble_count < 60)) begin
                uart_send(8'h55, bit_clks);
                preamble_count = preamble_count + 1;
            end
            wait_frames(3, bit_clks);
        end
    endtask

    // Watchdog
    initial begin
        #(400_000_000);
        $display("[%0t] ERROR: watchdog timeout", $time);
        $finish;
    end

    initial begin
        pass_cnt      = 0;
        fail_cnt      = 0;
        tx_count      = 0;
        tx_par_err    = 0;
        tx_stop_err   = 0;
        tx_bit_clks   = BIT_CLKS;
        preamble_count = 0;
        rst_n         = 1'b0;
        uart_rx       = 1'b1;

        $display("==============================================================");
        $display(" tb_de10nano_uart_top: start (BIT_CLKS=%0d, CLK=%0d ns)",
                 BIT_CLKS, CLK_PERIOD);
        $display("==============================================================");

        // T1: reset defaults
        $display("\n--- T1: reset state ---");
        #(CLK_PERIOD * 10);
        check(uart_tx === 1'b1, "uart_tx idles high during reset");
        check(LED === 10'b0, "LED outputs are clear during reset");
        @(posedge clk);
        rst_n <= 1'b1;
        #(CLK_PERIOD * 5);

        // T2/T3: auto-baud acquisition and lock LED
        $display("\n--- T2/T3: auto-baud acquisition ---");
        acquire_lock(BIT_CLKS);
        check(LED[8] === 1'b1, "LED[8] asserts after auto-baud lock");
        check(preamble_count < 60, "Auto-baud acquired within 60 preamble bytes");

        // Keep TX monitor aligned to the nominal bit period for this test.
        // For best accuracy, use the measured rate if it is exposed internally;
        // the wrapper does not expose DETECTED_BAUD as a port.
        tx_bit_clks = BIT_CLKS;

        // Ignore any echo traffic from the preamble.
        tx_count = 0;
        wait_frames(2, BIT_CLKS);

        // T4/T5: single-byte echo and LED
        $display("\n--- T4/T5: single-byte echo ---");
        expected[0] = 8'hA5;
        uart_send(8'hA5, BIT_CLKS);
        wait_frames(3, BIT_CLKS);
        check(LED[7:0] === 8'hA5, "LED[7:0] shows last received byte 0xA5");
        check_tx_expected(1, "Single received byte echoed correctly");
        check(tx_stop_err == 0, "Echoed UART frame has a high stop bit");

        // T6: multiple bytes, order, and final LED value
        $display("\n--- T6: multiple-byte echo ---");
        tx_count = 0;
        tx_stop_err = 0;
        expected[0] = 8'h12;
        expected[1] = 8'h3C;
        expected[2] = 8'h00;
        expected[3] = 8'hFF;
        expected[4] = 8'h69;

        for (i = 0; i < 5; i = i + 1) begin
            uart_send(expected[i], BIT_CLKS);
            // Small inter-frame idle gap to allow the echo path/FIFO to settle.
            #(BIT_CLKS * CLK_PERIOD);
        end
        wait_frames(7, BIT_CLKS);
        check(LED[7:0] === expected[4], "LED shows final byte of multi-byte sequence");
        check_tx_expected(5, "Multiple bytes echoed correctly and in order");
        check(tx_stop_err == 0, "All echoed frames have high stop bits");

        // T7: final status observations
        $display("\n--- T7: status LEDs ---");
        check(LED[8] === 1'b1, "Baud-lock LED remains asserted");
        // error_flag is a pulse/status signal and may be low by the time it is
        // sampled here; do not require LED[9] to remain high after good frames.
        check(LED[9] === 1'b0, "Error LED low after valid frames");

        $display("\n==============================================================");
        $display(" SUMMARY: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** SOME TESTS FAILED ***");
        $display("==============================================================");
        $finish;
    end

    initial begin
        $dumpfile("tb_de10nano_uart_top.vcd");
        $dumpvars(0, tb_de10nano_uart_top);
    end

endmodule
