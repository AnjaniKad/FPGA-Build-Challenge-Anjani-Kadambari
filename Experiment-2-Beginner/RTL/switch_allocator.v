`timescale 1ns/1ps

module switch_allocator #(
    parameter NUM_PORTS = 5
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire [NUM_PORTS*NUM_PORTS-1:0] sa_req,
    output reg  [NUM_PORTS*NUM_PORTS-1:0] sa_grant
);

localparam PTR_W = (NUM_PORTS <= 1) ? 1 : $clog2(NUM_PORTS);
reg [PTR_W-1:0] rr_ptr [0:NUM_PORTS-1];

integer op, offset, candidate;
reg found;
always @(*) begin
    sa_grant = {(NUM_PORTS*NUM_PORTS){1'b0}};
    for (op=0; op<NUM_PORTS; op=op+1) begin
        found = 1'b0;
        for (offset=0; offset<NUM_PORTS; offset=offset+1) begin
            candidate = (rr_ptr[op] + offset) % NUM_PORTS;
            if (!found && sa_req[op*NUM_PORTS+candidate]) begin
                sa_grant[op*NUM_PORTS+candidate] = 1'b1;
                found = 1'b1;
            end
        end
    end
end

integer next_op, winner;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (next_op=0; next_op<NUM_PORTS; next_op=next_op+1)
            rr_ptr[next_op] <= 0;
    end else begin
        for (next_op=0; next_op<NUM_PORTS; next_op=next_op+1)
            for (winner=0; winner<NUM_PORTS; winner=winner+1)
                if (sa_grant[next_op*NUM_PORTS+winner]) begin
                    if (winner == NUM_PORTS-1)
                        rr_ptr[next_op] <= 0;
                    else
                        rr_ptr[next_op] <= winner[PTR_W-1:0] + 1'b1;
                end
    end
end

endmodule
