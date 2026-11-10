//checker bound into loop. it sees the three integrator copies, the voted
//word, the next state word and the dac word
`default_nettype none

module loop_chk (
    input wire               clk,
    input wire               rst_n,
    input wire               upd,
    input wire               hold,
    input wire signed [14:0] err,
    input wire [1:0]         gain,
    input wire [18:0]        i0,
    input wire [18:0]        i1,
    input wire [18:0]        i2,
    input wire signed [18:0] integ,
    input wire [18:0]        d,
    input wire [15:0]        dac
);

    localparam signed [19:0] IMAX = 20'sd262143;
    localparam signed [19:0] IMIN = -20'sd262144;

    wire signed [19:0] sum = $signed({integ[18], integ}) + $signed({{5{err[14]}}, err});

    //the word loop would load, saturating at the rails instead of wrapping
    function signed [18:0] sat(input signed [19:0] s);
        sat = (s > IMAX) ? 19'sd262143 : (s < IMIN) ? -19'sd262143 : s[18:0];
    endfunction

    //the dac word for a given integrator value and gain setting
    function [15:0] dacof(input [18:0] v, input [1:0] g);
        reg signed [20:0] iw, w;
        begin
            iw = {{2{v[18]}}, v};
            case (g)
                2'd1:    w = iw <<< 1;
                2'd2:    w = iw >>> 1;
                2'd3:    w = iw >>> 2;
                default: w = iw;
            endcase
            dacof = (&w[20:15] || ~|w[20:15]) ? {~w[15], w[14:0]} : {16{~w[20]}};
        end
    endfunction

    //the copies are loaded on the first clock, so they are known from then on
    reg seen = 1'b0;
    always @(posedge clk) seen <= 1'b1;

    always @(posedge clk) begin
        //the vote is the bitwise majority
        assert (integ == ((i0 & i1) | (i1 & i2) | (i0 & i2)));

        //every copy is loaded from the same d, so one clock after any upset
        //all three copies agree again
        assert (!seen || (i0 == i1 && i1 == i2));

        //with the two clean copies equal, any flip pattern in the third copy,
        //one bit or many, leaves the voted word and the dac word unchanged
        assert (!(i0 == i1) || integ == i0);
        assert (!(i0 == i1) || dac == dacof(i0, gain));

        //the dac word is the integrator as 16 bit offset binary, on a rail
        //when it does not fit
        assert (dac == dacof(integ, gain));

        //the integrator saturates instead of wrapping
        assert (rst_n || d == 19'd0);
        assert (!(rst_n && upd && !hold) || d == sat(sum));
        assert (!(rst_n && (!upd || hold)) || d == integ);
    end

endmodule
