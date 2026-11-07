//formal cell models for sby. the delay line is replaced by free taps, so the
//tdc sees any thermometer code, with or without bubbles and gaps
`default_nettype none

module gf180mcu_fd_sc_mcu7t5v0__dlyd_1 (input wire I, output wire Z);
    (* anyseq *) wire z;
    assign Z = z;
    wire _unused = &{I, 1'b0};
endmodule

module gf180mcu_fd_sc_mcu7t5v0__inv_1 (input wire I, output wire ZN);
    assign ZN = ~I;
endmodule

module gf180mcu_fd_sc_mcu7t5v0__nand2_1 (input wire A1, input wire A2, output wire ZN);
    assign ZN = ~(A1 & A2);
endmodule

module gf180mcu_fd_sc_mcu7t5v0__dffq_1 (input wire CLK, input wire D, output reg Q);
    always @(posedge CLK) Q <= D;
endmodule

//dffq with one free flip pattern on its input, for the tmr fault model
module gf180mcu_fd_sc_mcu7t5v0__dffq_1_f (input wire CLK, input wire D, input wire FT, output reg Q);
    always @(posedge CLK) Q <= D ^ FT;
endmodule
