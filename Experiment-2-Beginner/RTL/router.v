`timescale 1ns/1ps
// Top-level NoC router used to build the mesh.
module router #(
    parameter COORD_W      = 4,
    parameter FLIT_SIZE    = 40,
    parameter BUFFER_DEPTH = 8,
    parameter NUM_VCS      = 2,
    parameter ROUTER_X_ID  = 0,
    parameter ROUTER_Y_ID  = 0
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [5*FLIT_SIZE-1:0] in_flit_flat,
    input  wire [4:0]             in_valid,
    input  wire [5*NUM_VCS-1:0]   in_vc_flat,
    output wire [5*FLIT_SIZE-1:0] out_flit_flat,
    output wire [4:0]             out_valid,
    output reg  [5*NUM_VCS-1:0]   out_vc_flat,
    output wire [5*NUM_VCS-1:0]   credit_flat,
    input  wire [5*NUM_VCS-1:0]   ds_credit_flat
);

localparam NUM_PORTS = 5;
localparam VC_W = (NUM_VCS <= 1) ? 1 : $clog2(NUM_VCS);
localparam CREDIT_W = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH + 1);

wire [FLIT_SIZE-1:0] in_flit [0:NUM_PORTS-1];
wire [NUM_VCS-1:0] in_vc [0:NUM_PORTS-1];

genvar gp, gv;
generate
for (gp=0; gp<NUM_PORTS; gp=gp+1) begin : g_input
    assign in_flit[gp] = in_flit_flat[gp*FLIT_SIZE +: FLIT_SIZE];
    assign in_vc[gp] = in_vc_flat[gp*NUM_VCS +: NUM_VCS];
end
endgenerate

wire [FLIT_SIZE-1:0] buf_out [0:NUM_PORTS-1][0:NUM_VCS-1];
wire buf_empty [0:NUM_PORTS-1][0:NUM_VCS-1];
wire buf_hd_vld [0:NUM_PORTS-1][0:NUM_VCS-1];
wire buf_credit [0:NUM_PORTS-1][0:NUM_VCS-1];
reg  buf_rd_en [0:NUM_PORTS-1][0:NUM_VCS-1];

generate
for (gp=0; gp<NUM_PORTS; gp=gp+1) begin : g_buf_p
    for (gv=0; gv<NUM_VCS; gv=gv+1) begin : g_buf_v
        input_buffer #(
            .FLIT_SIZE(FLIT_SIZE),
            .BUFFER_DEPTH(BUFFER_DEPTH)
        ) ib (
            .clk(clk),
            .rst_n(rst_n),
            .wr_en(in_valid[gp] & in_vc[gp][gv]),
            .flit_in(in_flit[gp]),
            .rd_en(buf_rd_en[gp][gv]),
            .flit_out(buf_out[gp][gv]),
            .full(),
            .empty(buf_empty[gp][gv]),
            .valid_head(buf_hd_vld[gp][gv]),
            .credit_out(buf_credit[gp][gv])
        );
        assign credit_flat[gp*NUM_VCS+gv] = buf_credit[gp][gv];
    end
end
endgenerate

wire [4:0] rc_port [0:NUM_PORTS-1][0:NUM_VCS-1];

generate
for (gp=0; gp<NUM_PORTS; gp=gp+1) begin : g_rc_p
    for (gv=0; gv<NUM_VCS; gv=gv+1) begin : g_rc_v
        route_compute #(
            .FLIT_SIZE(FLIT_SIZE),
            .COORD_W(COORD_W),
            .ROUTER_X(ROUTER_X_ID),
            .ROUTER_Y(ROUTER_Y_ID)
        ) rc (
            .head_flit(buf_out[gp][gv]),
            .head_valid(buf_hd_vld[gp][gv]),
            .out_port(rc_port[gp][gv])
        );
    end
end
endgenerate

reg worm_active [0:NUM_PORTS-1][0:NUM_VCS-1];
reg [4:0] worm_out_port [0:NUM_PORTS-1][0:NUM_VCS-1];
// ponytail: VC IDs stay fixed across hops; add remapping only if measured contention needs it.
reg out_vc_active [0:NUM_PORTS-1][0:NUM_VCS-1];
reg [CREDIT_W-1:0] ds_credit_count [0:NUM_PORTS-1][0:NUM_VCS-1];
reg [VC_W-1:0] input_rr_ptr [0:NUM_PORTS-1];

function [2:0] port_number;
    input [4:0] port_onehot;
    begin
        case (port_onehot)
            5'b00001: port_number = 3'd0;
            5'b00010: port_number = 3'd1;
            5'b00100: port_number = 3'd2;
            5'b01000: port_number = 3'd3;
            default:  port_number = 3'd4;
        endcase
    end
endfunction

reg [VC_W-1:0] selected_vc [0:NUM_PORTS-1];
reg [2:0] selected_port [0:NUM_PORTS-1];
reg selected_valid [0:NUM_PORTS-1];
reg [NUM_PORTS*NUM_PORTS-1:0] sa_req;
integer sel_p, sel_k, sel_v, req_p;

always @(*) begin
    sa_req = {(NUM_PORTS*NUM_PORTS){1'b0}};
    sel_v = 0;
    req_p = 0;
    for (sel_p=0; sel_p<NUM_PORTS; sel_p=sel_p+1) begin
        selected_vc[sel_p] = {VC_W{1'b0}};
        selected_port[sel_p] = 3'd0;
        selected_valid[sel_p] = 1'b0;
        for (sel_k=0; sel_k<NUM_VCS; sel_k=sel_k+1) begin
            sel_v = (input_rr_ptr[sel_p] + sel_k) % NUM_VCS;
            if (!selected_valid[sel_p]) begin
                if (worm_active[sel_p][sel_v] && !buf_empty[sel_p][sel_v]) begin
                    req_p = port_number(worm_out_port[sel_p][sel_v]);
                    if (ds_credit_count[req_p][sel_v] != 0) begin
                        selected_vc[sel_p] = sel_v[VC_W-1:0];
                        selected_port[sel_p] = req_p[2:0];
                        selected_valid[sel_p] = 1'b1;
                    end
                end else if (!worm_active[sel_p][sel_v] && buf_hd_vld[sel_p][sel_v]) begin
                    req_p = port_number(rc_port[sel_p][sel_v]);
                    if (!out_vc_active[req_p][sel_v] &&
                        ds_credit_count[req_p][sel_v] != 0) begin
                        selected_vc[sel_p] = sel_v[VC_W-1:0];
                        selected_port[sel_p] = req_p[2:0];
                        selected_valid[sel_p] = 1'b1;
                    end
                end
            end
        end
        if (selected_valid[sel_p])
            sa_req[selected_port[sel_p]*NUM_PORTS+sel_p] = 1'b1;
    end
end

wire [NUM_PORTS*NUM_PORTS-1:0] sa_grant;

switch_allocator #(.NUM_PORTS(NUM_PORTS)) u_sa (
    .clk(clk),
    .rst_n(rst_n),
    .sa_req(sa_req),
    .sa_grant(sa_grant)
);

integer rd_p, rd_v, rd_o;
always @(*) begin
    out_vc_flat = {(NUM_PORTS*NUM_VCS){1'b0}};
    for (rd_p=0; rd_p<NUM_PORTS; rd_p=rd_p+1)
        for (rd_v=0; rd_v<NUM_VCS; rd_v=rd_v+1)
            buf_rd_en[rd_p][rd_v] = 1'b0;
    for (rd_o=0; rd_o<NUM_PORTS; rd_o=rd_o+1)
        for (rd_p=0; rd_p<NUM_PORTS; rd_p=rd_p+1)
            if (sa_grant[rd_o*NUM_PORTS+rd_p]) begin
                buf_rd_en[rd_p][selected_vc[rd_p]] = 1'b1;
                out_vc_flat[rd_o*NUM_VCS+selected_vc[rd_p]] = 1'b1;
            end
end

integer st_p, st_v, st_o;
wire [NUM_PORTS*NUM_VCS-1:0] sent_flit;
genvar go;
generate
for (go=0; go<NUM_PORTS; go=go+1) begin : g_sent_o
    for (gv=0; gv<NUM_VCS; gv=gv+1) begin : g_sent_v
        assign sent_flit[go*NUM_VCS+gv] =
            out_valid[go] && out_vc_flat[go*NUM_VCS+gv];
    end
end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (st_p=0; st_p<NUM_PORTS; st_p=st_p+1) begin
            input_rr_ptr[st_p] <= 0;
            for (st_v=0; st_v<NUM_VCS; st_v=st_v+1) begin
                worm_active[st_p][st_v] <= 1'b0;
                worm_out_port[st_p][st_v] <= 5'b0;
                out_vc_active[st_p][st_v] <= 1'b0;
                ds_credit_count[st_p][st_v] <= BUFFER_DEPTH;
            end
        end
    end else begin
        for (st_o=0; st_o<NUM_PORTS; st_o=st_o+1)
            for (st_v=0; st_v<NUM_VCS; st_v=st_v+1)
                case ({sent_flit[st_o*NUM_VCS+st_v],
                       ds_credit_flat[st_o*NUM_VCS+st_v]})
                    2'b01: if (ds_credit_count[st_o][st_v] < BUFFER_DEPTH)
                                ds_credit_count[st_o][st_v] <= ds_credit_count[st_o][st_v] + 1'b1;
                    2'b10: if (ds_credit_count[st_o][st_v] != 0)
                                ds_credit_count[st_o][st_v] <= ds_credit_count[st_o][st_v] - 1'b1;
                    default: ;
                endcase

        for (st_o=0; st_o<NUM_PORTS; st_o=st_o+1)
            for (st_p=0; st_p<NUM_PORTS; st_p=st_p+1)
                if (sa_grant[st_o*NUM_PORTS+st_p]) begin
                    if (selected_vc[st_p] == NUM_VCS-1)
                        input_rr_ptr[st_p] <= 0;
                    else
                        input_rr_ptr[st_p] <= selected_vc[st_p] + 1'b1;
                    for (st_v=0; st_v<NUM_VCS; st_v=st_v+1)
                        if (selected_vc[st_p] == st_v) begin
                            if (!worm_active[st_p][st_v] && buf_hd_vld[st_p][st_v]) begin
                                if (buf_out[st_p][st_v][FLIT_SIZE-3]) begin
                                    worm_active[st_p][st_v] <= 1'b0;
                                    worm_out_port[st_p][st_v] <= 5'b0;
                                    out_vc_active[st_o][st_v] <= 1'b0;
                                end else begin
                                    worm_active[st_p][st_v] <= 1'b1;
                                    worm_out_port[st_p][st_v] <= rc_port[st_p][st_v];
                                    out_vc_active[st_o][st_v] <= 1'b1;
                                end
                            end else if (worm_active[st_p][st_v] &&
                                         buf_out[st_p][st_v][FLIT_SIZE-3]) begin
                                worm_active[st_p][st_v] <= 1'b0;
                                worm_out_port[st_p][st_v] <= 5'b0;
                                out_vc_active[st_o][st_v] <= 1'b0;
                            end
                        end
                end
    end
end

wire [NUM_PORTS*FLIT_SIZE-1:0] xbar_in_flat;

generate
for (gp=0; gp<NUM_PORTS; gp=gp+1) begin : g_xbar_in
    assign xbar_in_flat[gp*FLIT_SIZE +: FLIT_SIZE] = buf_out[gp][selected_vc[gp]];
end
endgenerate

switch #(
    .FLIT_SIZE(FLIT_SIZE),
    .NUM_PORTS(NUM_PORTS)
) u_xbar (
    .in_flit_flat(xbar_in_flat),
    .grant(sa_grant),
    .out_flit_flat(out_flit_flat),
    .out_valid(out_valid)
);

endmodule
