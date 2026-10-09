`timescale 1ns/1ps

module router_tb;

parameter FLIT_SIZE    = 40;
parameter COORD_W      = 4;
parameter BUFFER_DEPTH = 8;
parameter NUM_VCS      = 2;
parameter ROUTER_X_ID  = 2;
parameter ROUTER_Y_ID  = 2;

localparam LOCAL = 0;
localparam NORTH = 1;
localparam SOUTH = 2;
localparam EAST  = 3;
localparam WEST  = 4;

reg clk, rst_n;
initial begin clk = 0; rst_n = 0; #40 rst_n = 1; end
always #5 clk = ~clk;

reg [FLIT_SIZE-1:0] drive_flit [0:4];
reg [4:0] drive_valid;
reg [NUM_VCS-1:0] drive_vc [0:4];
reg [5*FLIT_SIZE-1:0] in_flit_flat;
reg [5*NUM_VCS-1:0] in_vc_flat;

integer mux_p;
always @(*) begin
    for (mux_p=0; mux_p<5; mux_p=mux_p+1) begin
        in_flit_flat[mux_p*FLIT_SIZE +: FLIT_SIZE] = drive_flit[mux_p];
        in_vc_flat[mux_p*NUM_VCS +: NUM_VCS] = drive_vc[mux_p];
    end
end

wire [5*FLIT_SIZE-1:0] out_flit_flat;
wire [4:0] out_valid;
wire [5*NUM_VCS-1:0] out_vc_flat;
wire [5*NUM_VCS-1:0] credit_flat;
reg  [5*NUM_VCS-1:0] ds_credit_flat;

router #(
    .FLIT_SIZE(FLIT_SIZE),
    .COORD_W(COORD_W),
    .BUFFER_DEPTH(BUFFER_DEPTH),
    .NUM_VCS(NUM_VCS),
    .ROUTER_X_ID(ROUTER_X_ID),
    .ROUTER_Y_ID(ROUTER_Y_ID)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .in_flit_flat(in_flit_flat),
    .in_valid(drive_valid),
    .in_vc_flat(in_vc_flat),
    .out_flit_flat(out_flit_flat),
    .out_valid(out_valid),
    .out_vc_flat(out_vc_flat),
    .credit_flat(credit_flat),
    .ds_credit_flat(ds_credit_flat)
);

function [FLIT_SIZE-1:0] mkflit;
    input is_head, is_tail;
    input [COORD_W-1:0] dx, dy;
    input [31:0] payload;
    localparam PAY_W = FLIT_SIZE - 3 - 2*COORD_W;
    begin
        mkflit = {1'b1, is_head, is_tail, dx, dy, payload[PAY_W-1:0]};
    end
endfunction

reg [FLIT_SIZE-1:0] seen_flit [0:4][0:511];
reg [NUM_VCS-1:0] seen_vc [0:4][0:511];
integer seen_count [0:4];
integer credit_count [0:4][0:NUM_VCS-1];
integer mon_p, mon_v;
always @(posedge clk) begin
    #1;
    for (mon_p=0; mon_p<5; mon_p=mon_p+1) begin
        if (out_valid[mon_p]) begin
            seen_flit[mon_p][seen_count[mon_p]] =
                out_flit_flat[mon_p*FLIT_SIZE +: FLIT_SIZE];
            seen_vc[mon_p][seen_count[mon_p]] =
                out_vc_flat[mon_p*NUM_VCS +: NUM_VCS];
            seen_count[mon_p] = seen_count[mon_p] + 1;
        end
        for (mon_v=0; mon_v<NUM_VCS; mon_v=mon_v+1)
            if (credit_flat[mon_p*NUM_VCS+mon_v])
                credit_count[mon_p][mon_v] = credit_count[mon_p][mon_v] + 1;
    end
end

integer errors;
task automatic check;
    input condition;
    input [8*80-1:0] label;
    begin
        if (condition)
            $display("[PASS] %0s", label);
        else begin
            errors = errors + 1;
            $display("[FAIL] %0s", label);
        end
    end
endtask

task automatic inject_pkt;
    input integer port, vc, plen;
    input [COORD_W-1:0] dx, dy;
    input [31:0] payload_base;
    integer f;
    begin
        for (f=0; f<plen; f=f+1) begin
            @(negedge clk);
            drive_flit[port] = mkflit(f == 0, f == plen-1, dx, dy,
                                      payload_base + f);
            drive_valid[port] = 1'b1;
            drive_vc[port] = (1 << vc);
        end
        @(negedge clk);
        drive_flit[port] = 0;
        drive_valid[port] = 1'b0;
        drive_vc[port] = 0;
    end
endtask

task automatic check_packet;
    input integer port, start, vc, plen;
    input [COORD_W-1:0] dx, dy;
    input [31:0] payload_base;
    input [8*80-1:0] label;
    integer f;
    reg [FLIT_SIZE-1:0] expected;
    begin
        for (f=0; f<plen; f=f+1) begin
            expected = mkflit(f == 0, f == plen-1, dx, dy,
                              payload_base + f);
            if (seen_flit[port][start+f] !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s flit %0d expected=%h got=%h",
                         label, f, expected, seen_flit[port][start+f]);
            end
            if (seen_vc[port][start+f] !== (1 << vc)) begin
                errors = errors + 1;
                $display("[FAIL] %0s flit %0d VC expected=%b got=%b",
                         label, f, (1 << vc), seen_vc[port][start+f]);
            end
        end
    end
endtask

task automatic route_test;
    input integer input_port, vc, output_port, plen;
    input [COORD_W-1:0] dx, dy;
    input [31:0] payload_base;
    input [8*80-1:0] label;
    integer before [0:4];
    integer p;
    begin
        for (p=0; p<5; p=p+1)
            before[p] = seen_count[p];
        inject_pkt(input_port, vc, plen, dx, dy, payload_base);
        repeat (5) @(posedge clk);
        #2;
        check(seen_count[0] == before[0] + ((output_port == 0) ? plen : 0) &&
              seen_count[1] == before[1] + ((output_port == 1) ? plen : 0) &&
              seen_count[2] == before[2] + ((output_port == 2) ? plen : 0) &&
              seen_count[3] == before[3] + ((output_port == 3) ? plen : 0) &&
              seen_count[4] == before[4] + ((output_port == 4) ? plen : 0),
              label);
        check_packet(output_port, before[output_port], vc, plen,
                     dx, dy, payload_base, label);
    end
endtask

task automatic inject_interleaved_vcs;
    input integer port, plen;
    input [31:0] payload0, payload1;
    integer f;
    begin
        for (f=0; f<plen; f=f+1) begin
            @(negedge clk);
            drive_flit[port] = mkflit(f == 0, f == plen-1,
                                      ROUTER_X_ID+1, ROUTER_Y_ID, payload0+f);
            drive_valid[port] = 1'b1;
            drive_vc[port] = 2'b01;
            @(negedge clk);
            drive_flit[port] = mkflit(f == 0, f == plen-1,
                                      ROUTER_X_ID-1, ROUTER_Y_ID, payload1+f);
            drive_vc[port] = 2'b10;
        end
        @(negedge clk);
        drive_flit[port] = 0;
        drive_valid[port] = 1'b0;
        drive_vc[port] = 0;
    end
endtask

task automatic inject_single_then_west;
    begin
        @(negedge clk);
        drive_flit[LOCAL] = mkflit(1, 1, ROUTER_X_ID+1, ROUTER_Y_ID, 32'h6000);
        drive_valid[LOCAL] = 1'b1;
        drive_vc[LOCAL] = 2'b01;
        @(negedge clk);
        drive_flit[LOCAL] = mkflit(1, 0, ROUTER_X_ID-1, ROUTER_Y_ID, 32'h6100);
        @(negedge clk);
        drive_flit[LOCAL] = mkflit(0, 1, ROUTER_X_ID-1, ROUTER_Y_ID, 32'h6101);
        @(negedge clk);
        drive_flit[LOCAL] = 0;
        drive_valid[LOCAL] = 1'b0;
        drive_vc[LOCAL] = 0;
    end
endtask

task automatic inject_stress;
    input integer packets, plen;
    integer packet, f;
    begin
        for (packet=0; packet<packets; packet=packet+1)
            for (f=0; f<plen; f=f+1) begin
                @(negedge clk);
                drive_flit[LOCAL] = mkflit(f == 0, f == plen-1,
                                           ROUTER_X_ID+1, ROUTER_Y_ID,
                                           32'h90000000 + packet*plen + f);
                drive_valid[LOCAL] = 1'b1;
                drive_vc[LOCAL] = 2'b01;
            end
        @(negedge clk);
        drive_flit[LOCAL] = 0;
        drive_valid[LOCAL] = 1'b0;
        drive_vc[LOCAL] = 0;
    end
endtask

integer init_p;
integer before [0:4];
integer first_a;
integer packet, flit;
initial begin
    errors = 0;
    drive_valid = 0;
    ds_credit_flat = {(5*NUM_VCS){1'b1}};
    for (init_p=0; init_p<5; init_p=init_p+1) begin
        drive_flit[init_p] = 0;
        drive_vc[init_p] = 0;
        seen_count[init_p] = 0;
        for (flit=0; flit<NUM_VCS; flit=flit+1)
            credit_count[init_p][flit] = 0;
    end

    @(posedge rst_n);
    repeat (2) @(posedge clk);

    route_test(LOCAL, 0, EAST, 3, ROUTER_X_ID+1, ROUTER_Y_ID,
               32'h1000, "TC1 LOCAL to EAST exact packet");
    route_test(LOCAL, 0, WEST, 3, ROUTER_X_ID-1, ROUTER_Y_ID,
               32'h2000, "TC2 LOCAL to WEST exact packet");
    route_test(LOCAL, 0, SOUTH, 3, ROUTER_X_ID, ROUTER_Y_ID+1,
               32'h3000, "TC3 LOCAL to SOUTH exact packet");
    route_test(LOCAL, 0, NORTH, 3, ROUTER_X_ID, ROUTER_Y_ID-1,
               32'h4000, "TC4 LOCAL to NORTH exact packet");
    route_test(LOCAL, 0, LOCAL, 2, ROUTER_X_ID, ROUTER_Y_ID,
               32'h5000, "TC5 LOCAL loopback exact packet");

    for (init_p=0; init_p<5; init_p=init_p+1)
        before[init_p] = seen_count[init_p];
    inject_single_then_west;
    repeat (5) @(posedge clk);
    #2;
    check(seen_count[EAST] == before[EAST] + 1,
          "TC6 single-flit worm releases EAST");
    check(seen_count[WEST] == before[WEST] + 2,
          "TC6 following packet routes WEST");
    check(seen_count[LOCAL] == before[LOCAL] &&
          seen_count[NORTH] == before[NORTH] &&
          seen_count[SOUTH] == before[SOUTH],
          "TC6 no unexpected output");
    check_packet(EAST, before[EAST], 0, 1, ROUTER_X_ID+1, ROUTER_Y_ID,
                 32'h6000, "TC6 single-flit packet");
    check_packet(WEST, before[WEST], 0, 2, ROUTER_X_ID-1, ROUTER_Y_ID,
                 32'h6100, "TC6 following packet");

    for (init_p=0; init_p<5; init_p=init_p+1)
        before[init_p] = seen_count[init_p];
    inject_interleaved_vcs(LOCAL, 3, 32'h7000, 32'h7100);
    repeat (8) @(posedge clk);
    #2;
    check(seen_count[EAST] == before[EAST] + 3,
          "TC7 VC0 reaches EAST once per flit");
    check(seen_count[WEST] == before[WEST] + 3,
          "TC7 VC1 reaches WEST once per flit");
    check(seen_count[LOCAL] == before[LOCAL] &&
          seen_count[NORTH] == before[NORTH] &&
          seen_count[SOUTH] == before[SOUTH],
          "TC7 no unexpected output");
    check_packet(EAST, before[EAST], 0, 3, ROUTER_X_ID+1, ROUTER_Y_ID,
                 32'h7000, "TC7 VC0 packet");
    check_packet(WEST, before[WEST], 1, 3, ROUTER_X_ID-1, ROUTER_Y_ID,
                 32'h7100, "TC7 VC1 packet");

    for (init_p=0; init_p<5; init_p=init_p+1)
        before[init_p] = seen_count[init_p];
    fork
        inject_pkt(LOCAL, 0, 4, ROUTER_X_ID+1, ROUTER_Y_ID, 32'h8000);
        inject_pkt(NORTH, 0, 4, ROUTER_X_ID+1, ROUTER_Y_ID, 32'h8100);
    join
    repeat (12) @(posedge clk);
    #2;
    check(seen_count[EAST] == before[EAST] + 8,
          "TC8 contending packets both complete");
    check(seen_count[LOCAL] == before[LOCAL] &&
          seen_count[NORTH] == before[NORTH] &&
          seen_count[SOUTH] == before[SOUTH] &&
          seen_count[WEST] == before[WEST],
          "TC8 no unexpected output");
    first_a = seen_flit[EAST][before[EAST]] ==
              mkflit(1, 0, ROUTER_X_ID+1, ROUTER_Y_ID, 32'h8000);
    if (first_a) begin
        check_packet(EAST, before[EAST], 0, 4, ROUTER_X_ID+1, ROUTER_Y_ID,
                     32'h8000, "TC8 first locked packet");
        check_packet(EAST, before[EAST]+4, 0, 4, ROUTER_X_ID+1, ROUTER_Y_ID,
                     32'h8100, "TC8 second locked packet");
    end else begin
        check_packet(EAST, before[EAST], 0, 4, ROUTER_X_ID+1, ROUTER_Y_ID,
                     32'h8100, "TC8 first locked packet");
        check_packet(EAST, before[EAST]+4, 0, 4, ROUTER_X_ID+1, ROUTER_Y_ID,
                     32'h8000, "TC8 second locked packet");
    end

    for (init_p=0; init_p<5; init_p=init_p+1)
        before[init_p] = seen_count[init_p];
    inject_stress(32, 4);
    repeat (6) @(posedge clk);
    #2;
    check(seen_count[EAST] == before[EAST] + 128,
          "TC9 32 back-to-back packets produce 128 transfers");
    check(seen_count[LOCAL] == before[LOCAL] &&
          seen_count[NORTH] == before[NORTH] &&
          seen_count[SOUTH] == before[SOUTH] &&
          seen_count[WEST] == before[WEST],
          "TC9 no unexpected output");
    for (packet=0; packet<32; packet=packet+1)
        for (flit=0; flit<4; flit=flit+1)
            if (seen_flit[EAST][before[EAST]+packet*4+flit] !==
                    mkflit(flit == 0, flit == 3, ROUTER_X_ID+1, ROUTER_Y_ID,
                           32'h90000000 + packet*4 + flit) ||
                seen_vc[EAST][before[EAST]+packet*4+flit] !== 2'b01) begin
                errors = errors + 1;
                $display("[FAIL] TC9 packet=%0d flit=%0d data mismatch", packet, flit);
            end

    for (init_p=0; init_p<5; init_p=init_p+1)
        before[init_p] = seen_count[init_p];
    @(negedge clk);
    ds_credit_flat[EAST*NUM_VCS+0] = 1'b0;
    inject_pkt(LOCAL, 0, BUFFER_DEPTH+3, ROUTER_X_ID+1, ROUTER_Y_ID,
               32'hA000);
    repeat (5) @(posedge clk);
    #2;
    check(seen_count[EAST] == before[EAST] + BUFFER_DEPTH,
          "TC10 output stops when downstream credits reach zero");
    @(negedge clk);
    ds_credit_flat[EAST*NUM_VCS+0] = 1'b1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    ds_credit_flat[EAST*NUM_VCS+0] = 1'b0;
    repeat (3) @(posedge clk);
    #2;
    check(seen_count[EAST] == before[EAST] + BUFFER_DEPTH + 3,
          "TC10 returned credits release buffered flits");
    check(seen_count[LOCAL] == before[LOCAL] &&
          seen_count[NORTH] == before[NORTH] &&
          seen_count[SOUTH] == before[SOUTH] &&
          seen_count[WEST] == before[WEST],
          "TC10 no unexpected output");
    check_packet(EAST, before[EAST], 0, BUFFER_DEPTH+3,
                 ROUTER_X_ID+1, ROUTER_Y_ID, 32'hA000,
                 "TC10 back-pressure packet");
    check(credit_count[LOCAL][0] == 163 &&
          credit_count[LOCAL][1] == 3 &&
          credit_count[NORTH][0] == 4,
          "credit returns match consumed input flits");

    if (errors == 0) begin
        $display("ALL TESTS PASSED");
        $finish;
    end else begin
        $display("TESTS FAILED: %0d errors", errors);
        $finish_and_return(1);
    end
end

initial begin
    $dumpfile("../sim/router_waves.vcd");
    $dumpvars(0, router_tb);
end

initial begin
    #2000000;
    $display("[FAIL] watchdog timeout");
    $finish_and_return(1);
end

endmodule
