// sync_fifo.v
// Simple single-clock-domain FIFO, used for both RX and TX buffering.

module sync_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 16                    // must be a power of 2
) (
    input  wire             clk,
    input  wire             rst_n,

    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output wire             full,
    output reg              overrun,

    input  wire             rd_en,
    output wire [WIDTH-1:0] rd_data,
    output wire             empty
);

    localparam PTR_WIDTH = $clog2(DEPTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_WIDTH:0] wr_ptr;   // extra MSB to distinguish full/empty
    reg [PTR_WIDTH:0] rd_ptr;

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[PTR_WIDTH]      != rd_ptr[PTR_WIDTH]) &&
                   (wr_ptr[PTR_WIDTH-1:0]  == rd_ptr[PTR_WIDTH-1:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= 0;
            overrun <= 1'b0;
        end else begin
            overrun <= 1'b0;
            if (wr_en) begin
                if (!full) begin
                    mem[wr_ptr[PTR_WIDTH-1:0]] <= wr_data;
                    wr_ptr <= wr_ptr + 1'b1;
                end else begin
                    overrun <= 1'b1;   // write attempted while full -> dropped
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr  <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr  <= rd_ptr + 1'b1;
        end
    end

    // First-word-fall-through: rd_data is combinational, reflecting the
    // entry at rd_ptr *before* any pop. This is essential for consumers
    // (like uart_tx) that read tx_byte in the same cycle they assert the
    // pop strobe -- a registered read here would hand them stale data.
    assign rd_data = mem[rd_ptr[PTR_WIDTH-1:0]];

endmodule
