//one copy of a triplicated register, from kept cells so synthesis cannot
//merge the three copies back into one
`default_nettype none

module tmr_reg #(
    parameter W = 8
) (
    input  wire         clk,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);

    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin : b
            (* keep *) gf180mcu_fd_sc_mcu7t5v0__dffq_1 u_ff (.CLK(clk), .D(d[i]), .Q(q[i]));
        end
    endgenerate

endmodule

`ifdef VERILATOR
module gf180mcu_fd_sc_mcu7t5v0__dffq_1 (input wire CLK, input wire D, output reg Q);
    always @(posedge CLK) Q <= D;
endmodule
`endif
