//tmr fault model. three copies of the integrator, the chosen one built from
//dffq cells that take a free flip pattern on their input
`default_nettype none

module tmr_flt #(
    parameter W = 19
) (
    input  wire         clk,
    input  wire [W-1:0] d,
    input  wire [W-1:0] ft,
    output wire [W-1:0] q
);

    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin : b
            (* keep *) gf180mcu_fd_sc_mcu7t5v0__dffq_1_f u_ff (.CLK(clk), .D(d[i]), .FT(ft[i]), .Q(q[i]));
        end
    endgenerate

endmodule

module tmr_f (
    input wire        clk,
    input wire [18:0] d,
    input wire [18:0] ft
);

    localparam W = 19;

    wire [W-1:0] q0, q1, q2;

    tmr_reg #(.W(W)) u_r0 (.clk(clk), .d(d), .q(q0));
    tmr_reg #(.W(W)) u_r2 (.clk(clk), .d(d), .q(q2));
    tmr_flt #(.W(W)) u_r1 (.clk(clk), .d(d), .ft(ft), .q(q1));  //the chosen copy

    wire [W-1:0] vote = (q0 & q1) | (q1 & q2) | (q0 & q2);

    //the copies are loaded on the first clock, so they are known from then on
    reg seen = 1'b0;
    always @(posedge clk) seen <= 1'b1;

    always @(posedge clk) begin
        //the two clean copies hold the same word
        assert (!seen || q0 == q2);
        //a flip on the chosen copy, one bit or many, never shows in the vote
        assert (!seen || vote == q0);
        //and it is gone one clock later, since all copies load the same d
        assert (!seen || $past(ft) != 19'd0 || q1 == q0);
    end

    always @(posedge clk) cover (ft != 19'd0);

endmodule
