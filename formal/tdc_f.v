//tdc proof wrapper. the dut runs on free taps and a free input after a
//short reset, the checks are in tdc_chk.v
`default_nettype none

module tdc_f (
    input wire clk,
    input wire rst_n,
    input wire in
);

    localparam N = 44;

    //hold reset for the first clocks, so the proof starts from a state that
    //is fully known, and arm the checks after it
    reg [1:0] boot  = 2'd0;
    reg       armed = 1'b0;
    wire      rst_n_i = rst_n && boot == 2'd3;

    always @(posedge clk) begin
        if (boot != 2'd3) boot <= boot + 2'd1;
        if (boot == 2'd3) armed <= 1'b1;
    end

    wire       start, hit;
    wire [6:0] code;

    tdc #(.N(N)) u_tdc (
        .clk(clk), .rst_n(rst_n_i), .in(in),
        .start(start), .hit(hit), .code(code)
    );

    //both ends of the pairing are reachable, so the proof is not vacuous
    always @(posedge clk) begin
        cover (armed && start);
        cover (armed && hit);
    end

endmodule
