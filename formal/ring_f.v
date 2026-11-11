//ring stand-in for the top level proof. a closed inverter loop has no
//formal meaning, so the divider outputs are free
`default_nettype none

module ring #(
    parameter STAGES = 31,
    parameter DIV    = 10
) (
    input  wire           rst_n,
    input  wire           en,
    output wire [DIV-1:0] div
);

    (* anyseq *) wire [DIV-1:0] d;
    assign div = d;
    wire _unused = &{rst_n, en, 1'b0};

endmodule
