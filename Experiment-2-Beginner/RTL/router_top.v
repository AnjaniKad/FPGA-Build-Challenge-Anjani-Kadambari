`timescale 1ns/1ps

module router_top (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [3:0] SW,
    input  wire       KEY1,

    output reg  [1:0] LED
);

    // =========================================================
    // Router parameters
    // =========================================================

    localparam COORD_W      = 4;
    localparam FLIT_SIZE    = 40;
    localparam BUFFER_DEPTH = 8;
    localparam NUM_VCS      = 2;

    // =========================================================
    // Signals INTO router
    // =========================================================

    reg [5*FLIT_SIZE-1:0] in_flit_flat;
    reg [4:0]             in_valid;
    reg [5*NUM_VCS-1:0]   in_vc_flat;

    // No external downstream router in this standalone demo.
    // The router's internal credit counters start full.
    wire [5*NUM_VCS-1:0] ds_credit_flat;

    assign ds_credit_flat = {(5*NUM_VCS){1'b0}};

    // =========================================================
    // Signals OUT of router
    // =========================================================

    wire [5*FLIT_SIZE-1:0] out_flit_flat;
    wire [4:0]             out_valid;
    wire [5*NUM_VCS-1:0]   out_vc_flat;
    wire [5*NUM_VCS-1:0]   credit_flat;

    // =========================================================
    // Router instance
    //
    // This router is located at coordinate (0,0).
    // =========================================================

    router #(
        .COORD_W      (COORD_W),
        .FLIT_SIZE    (FLIT_SIZE),
        .BUFFER_DEPTH (BUFFER_DEPTH),
        .NUM_VCS      (NUM_VCS),
        .ROUTER_X_ID  (0),
        .ROUTER_Y_ID  (0)
    ) u_router (
        .clk            (clk),
        .rst_n          (rst_n),

        .in_flit_flat   (in_flit_flat),
        .in_valid       (in_valid),
        .in_vc_flat     (in_vc_flat),

        .out_flit_flat  (out_flit_flat),
        .out_valid      (out_valid),
        .out_vc_flat    (out_vc_flat),

        .credit_flat    (credit_flat),
        .ds_credit_flat (ds_credit_flat)
    );

    // =========================================================
    // Destination registers
    // =========================================================

    reg [3:0] dest_x;
    reg [3:0] dest_y;

    // One-clock packet injection pulse
    reg send_pending;

    // =========================================================
    // KEY1 edge detection
    //
    // DE10-Nano pushbuttons are active-low.
    // =========================================================

    reg key1_prev;

    wire key1_pressed;

    assign key1_pressed = key1_prev & ~KEY1;

    // =========================================================
    // Build input flit
    //
    // Actual fields from route_compute.v:
    //
    // [38]    = valid/head
    // [37]    = tail
    // [36:33] = destination X
    // [32:29] = destination Y
    //
    // We inject through input port 0, VC0.
    // =========================================================

    always @(*) begin

        in_flit_flat = {(5*FLIT_SIZE){1'b0}};

        // Input port 0
        in_flit_flat[38]    = 1'b1;
        in_flit_flat[37]    = 1'b1;

        in_flit_flat[36:33] = dest_x;
        in_flit_flat[32:29] = dest_y;

    end

    // =========================================================
    // VC selection
    //
    // Port 0 -> VC0
    //
    // NUM_VCS = 2
    // VC0 = bit 0
    // =========================================================

    always @(*) begin

        in_vc_flat = {(5*NUM_VCS){1'b0}};

        // Port 0, VC0
        in_vc_flat[0] = 1'b1;

    end

    // =========================================================
    // Packet injection
    //
    // Packet is injected for exactly one clock.
    // =========================================================

    always @(*) begin

        in_valid = 5'b00000;

        if (send_pending)
            in_valid[0] = 1'b1;

    end

    // =========================================================
    // Main control
    // =========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            key1_prev   <= 1'b1;

            dest_x      <= 4'd0;
            dest_y      <= 4'd0;

            send_pending <= 1'b0;

            LED         <= 2'b00;

        end

        else begin

            // Remember previous KEY1 state
            key1_prev <= KEY1;

            // Default: no packet injection
            send_pending <= 1'b0;

            // -------------------------------------------------
            // KEY1 pressed
            // -------------------------------------------------

            if (key1_pressed) begin

                // SW[3:2] -> destination X
                // SW[1:0] -> destination Y

                dest_x <= {2'b00, SW[3:2]};
                dest_y <= {2'b00, SW[1:0]};

                // Inject packet on next clock
                send_pending <= 1'b1;

            end

            // -------------------------------------------------
            // Display routing direction
            //
            // Router port encoding from route_compute.v:
            //
            // port 0 = LOCAL
            // port 1 = NORTH
            // port 2 = SOUTH
            // port 3 = EAST
            // port 4 = WEST
            // -------------------------------------------------

            if (out_valid[0])
                LED <= 2'b00;

            else if (out_valid[1])
                LED <= 2'b01;

            else if (out_valid[2])
                LED <= 2'b10;

            else if (out_valid[3])
                LED <= 2'b11;

            else if (out_valid[4])
                LED <= 2'b11;

        end

    end

endmodule