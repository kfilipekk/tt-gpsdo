//8n1, div clocks per bit
`default_nettype none

module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [6:0] div,
    input  wire [7:0] data,
    input  wire       valid,
    output wire       ready,
    output wire       tx
);

    reg [9:0] shift;
    reg [3:0] bits;
    reg [6:0] baud;

    assign tx    = shift[0];
    assign ready = bits == 4'd0;

    always @(posedge clk)
        if (!rst_n) begin
            shift <= 10'h3FF;
            bits  <= 4'd0;
            baud  <= 7'd0;
        end else if (bits == 4'd0) begin
            if (valid) begin
                shift <= {1'b1, data, 1'b0};
                bits  <= 4'd10;
                baud  <= 7'd0;
            end
        end else if (baud == div - 7'd1) begin
            baud  <= 7'd0;
            shift <= {1'b1, shift[9:1]};
            bits  <= bits - 4'd1;
        end else
            baud <= baud + 7'd1;

endmodule
