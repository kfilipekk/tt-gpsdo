//inverter ring with a ripple divider. its rate is the chip's own gate delay,
//and the slow taps feed the tdc calibration
`default_nettype none

module ring #(
    parameter STAGES = 31,  //odd, the nand counts as one
    parameter DIV    = 10
) (
    input  wire           rst_n,
    input  wire           en,
    output wire [DIV-1:0] div
);

    wire [STAGES-1:0] r;

    (* keep *) gf180mcu_fd_sc_mcu7t5v0__nand2_1 u_en (.A1(en), .A2(r[STAGES-1]), .ZN(r[0]));

    genvar i;
    generate
        for (i = 1; i < STAGES; i = i + 1) begin : g
            (* keep *) gf180mcu_fd_sc_mcu7t5v0__inv_1 u_inv (.I(r[i-1]), .ZN(r[i]));
        end
    endgenerate

    //each stage toggles on the one before, so the ring is the only fast net
    genvar j;
    generate
        for (j = 0; j < DIV; j = j + 1) begin : d
            reg q;
            wire c = (j == 0) ? r[STAGES-1] : ~div[j > 0 ? j - 1 : 0];
            always @(posedge c or negedge rst_n)
                if (!rst_n) q <= 1'b0;
                else        q <= ~q;
            assign div[j] = q;
        end
    endgenerate

endmodule
