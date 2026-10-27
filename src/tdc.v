//delay line tdc. an edge runs down N delay cells and every clock snaps the
//taps. the first snap with anything in the line holds how long before that
//clock edge the edge arrived, in taps, and it is shifted out and counted
`default_nettype none

module tdc #(
    parameter N = 44
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in,
    output reg        start,  //an edge was caught on this clock's snap
    output reg        hit,    //its code is ready
    output reg  [6:0] code
);

    wire [N:0] tap;
    assign tap[0] = in;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g
            (* keep *) gf180mcu_fd_sc_mcu7t5v0__dlyd_1 u_dly (.I(tap[i]), .Z(tap[i+1]));
        end
    endgenerate

    reg [N-1:0] snap;
    reg [6:0]   left;
    reg         busy, empty;

    always @(posedge clk)
        if (busy) snap <= {1'b0, snap[N-1:1]};
        else      snap <= tap[N:1];

    //bubbles at the edge are counted rather than decoded
    always @(posedge clk)
        if (!rst_n) begin
            busy  <= 1'b0;
            empty <= 1'b1;
            start <= 1'b0;
            hit   <= 1'b0;
            left  <= 7'd0;
            code  <= 7'd0;
        end else begin
            start <= 1'b0;
            hit   <= 1'b0;
            if (busy) begin
                code <= code + {6'd0, snap[0]};
                left <= left - 7'd1;
                if (left == 7'd1) begin
                    busy  <= 1'b0;
                    hit   <= 1'b1;
                    empty <= 1'b0;
                end
            end else begin
                empty <= ~|snap;
                if (empty && |snap) begin
                    busy  <= 1'b1;
                    start <= 1'b1;
                    left  <= N[6:0];
                    code  <= 7'd0;
                end
            end
        end

endmodule
