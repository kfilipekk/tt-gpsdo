//rtl simulation stand-ins for the hand placed gf180 cells, with typical
//3.3 v delays so the delay line and ring behave. gate level runs use the pdk
`timescale 1ns / 1ps

module gf180mcu_fd_sc_mcu7t5v0__dlyd_1 (input wire I, output wire Z);
    assign #3.4 Z = I;
endmodule

module gf180mcu_fd_sc_mcu7t5v0__inv_1 (input wire I, output wire ZN);
    assign #0.4 ZN = ~I;
endmodule

module gf180mcu_fd_sc_mcu7t5v0__nand2_1 (input wire A1, input wire A2, output wire ZN);
    assign #0.4 ZN = ~(A1 & A2);
endmodule

module gf180mcu_fd_sc_mcu7t5v0__dffq_1 (input wire CLK, input wire D, output reg Q);
    always @(posedge CLK) Q <= D;
endmodule
