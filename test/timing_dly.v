//simulation model of the dlyd cell for the sdf timing run. the pdk wrapper
//drives its output from a submodule, which icarus x's under -gspecify, so
//the buffer is a plain assign and the sdf sets the delay of each cell
`timescale 1ns / 1ps

module gf180mcu_fd_sc_mcu7t5v0__dlyd_1 (
    input  wire I,
    output wire Z,
    inout  wire VDD,
    inout  wire VSS,
    inout  wire VNW,
    inout  wire VPW
);

    assign Z = I;

    specify
        (I => Z) = (1.0, 1.0);
    endspecify

endmodule
