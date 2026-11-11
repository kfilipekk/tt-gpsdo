//checker inside the top level, at the real 10 mhz second. it covers the
//counter, the wrap handling of the phase, the jam and holdover, which is
//where the phase aliasing and the stuck telemetry lived
`default_nettype none

module top_chk #(
    parameter [23:0] NOM = 24'd10000000,
    parameter [23:0] JAM = 24'd8
) (
    input wire        clk,
    input wire        rst_n,
    input wire [23:0] pcnt,
    input wire        upper,
    input wire [7:0]  ph,
    input wire        pps_start,
    input wire        locked,
    input wire [1:0]  wraps,
    input wire [7:0]  dc
);

    reg        ok = 1'b0, was_rst = 1'b0;
    reg        jam_q = 1'b0;
    reg [23:0] pcnt_q = 24'd0;
    reg [7:0]  ph_q = 8'd0, dc_q = 8'd0;
    reg        start_q = 1'b0, upper_q = 1'b0;

    always @(posedge clk) begin
        if (!rst_n) ok <= 1'b1;
        was_rst <= !rst_n;
        jam_q   <= pps_start && !locked;
        pcnt_q  <= pcnt;
        ph_q    <= ph;
        dc_q    <= dc;
        start_q <= pps_start;
        upper_q <= upper;
    end

    //the clock is a free input in a multiclock proof, make it tick
    reg clk_g = 1'b0;
    always @($global_clock) begin
        clk_g <= !clk_g;
        assume (clk == clk_g);
    end

    //the phase as it should be, the offset from the nearest wrap
    wire [23:0] off   = upper ? pcnt - NOM : pcnt;
    wire [23:0] off_q = upper_q ? pcnt_q - NOM : pcnt_q;

    always @(*)
        if (ok && !was_rst) begin
            //the counter stays inside a second
            assert (pcnt < NOM);
            //the top half flag is exactly the top half of the count
            assert (upper == (pcnt > NOM / 2));
            //so the phase is the low byte of the offset from the wrap
            assert (ph == off[7:0]);
            //a clock on, the phase is one more, across the wrap too, except
            //where the count crosses the middle or a jam put it back
            assert (jam_q || pcnt_q == NOM / 2 || ph == ph_q + 8'd1);
            //a jam puts the counter at JAM
            assert (!jam_q || pcnt == JAM);
            //what was seen a clock ago lines up, which makes it inductive
            assert (pcnt_q < NOM && upper_q == (pcnt_q > NOM / 2) && ph_q == off_q[7:0]);
            assert (jam_q || pcnt == ((pcnt_q == NOM - 24'd1) ? 24'd0 : pcnt_q + 24'd1));
            //holdover counts at most two empty seconds
            assert (wraps != 2'd3);
            //the cycles short held for the telemetry only move with a pulse
            assert (start_q || dc == dc_q);
        end

endmodule
