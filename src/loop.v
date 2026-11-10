//integral loop. the integrator sums the phase error, in taps, once a second
//and sets the dac. a proportional term only added counter noise here.
//the integrator is triplicated and voted, so one flipped bit is outvoted
//and repaired the next clock
`default_nettype none

module loop #(
    parameter EW = 15,
    parameter IW = 19,
    parameter [EW-1:0] LOCK_ERR = 8,
    parameter LOCK_N = 15
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 upd,
    input  wire signed [EW-1:0] err,
    input  wire [1:0]           gain,
    input  wire                 hold,
    input  wire                 clr,    //holdover drops lock
    output reg  [15:0]          dac,
    output reg                  locked
);

    localparam signed [IW-1:0] IMAX = (1 <<< (IW - 1)) - 1;

    wire [IW-1:0] i0, i1, i2;
    wire signed [IW-1:0] integ = (i0 & i1) | (i1 & i2) | (i0 & i2);

    //sum with saturation, so a long outage cannot wrap it
    wire signed [IW:0] sum = {integ[IW-1], integ} + {{(IW-EW+1){err[EW-1]}}, err};
    wire               ovf = sum[IW] ^ sum[IW-1];
    wire signed [IW-1:0] integ_n = ovf ? (sum[IW] ? -IMAX : IMAX) : sum[IW-1:0];

    wire [IW-1:0] d = !rst_n ? {IW{1'b0}} : (upd && !hold) ? integ_n : integ;

    tmr_reg #(.W(IW)) u_r0 (.clk(clk), .d(d), .q(i0));
    tmr_reg #(.W(IW)) u_r1 (.clk(clk), .d(d), .q(i1));
    tmr_reg #(.W(IW)) u_r2 (.clk(clk), .d(d), .q(i2));

    //gain picks the shift from integrator to dac word, clamped to 16 bits
    //signed and offset to binary by flipping the top bit
    wire signed [IW+1:0] iw = {{2{integ[IW-1]}}, integ};
    reg  signed [IW+1:0] w;
    always @(*)
        case (gain)
            2'd1:    w = iw <<< 1;
            2'd2:    w = iw >>> 1;
            2'd3:    w = iw >>> 2;
            default: w = iw;
        endcase

    wire sat = !(&w[IW+1:15] || ~|w[IW+1:15]);
    always @(*)
        dac = sat ? {16{~w[IW+1]}} : {~w[15], w[14:0]};

    wire inwin = (err < $signed(LOCK_ERR)) && (err > -$signed(LOCK_ERR));
    reg [3:0] good;

    always @(posedge clk)
        if (!rst_n || clr) begin
            good   <= 4'd0;
            locked <= 1'b0;
        end else if (upd) begin
            good   <= !inwin ? 4'd0 : (good == LOCK_N[3:0]) ? good : good + 4'd1;
            locked <= inwin && good >= LOCK_N[3:0] - 4'd1;
        end

endmodule
