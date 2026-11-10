//checker bound into the tdc. it pairs every start with its hit, and ties
//its own count to the tdc's so the proof goes through by induction
`default_nettype none

module tdc_chk #(
    parameter N = 44
) (
    input wire       clk,
    input wire       rst_n,
    input wire       start,
    input wire       hit,
    input wire [6:0] code,
    input wire       busy,
    input wire [6:0] left
);

    //pending: a start is waiting for its hit, age: clocks since that start
    reg       pending = 1'b0, ok = 1'b0;
    reg [6:0] age = 7'd0;

    always @(posedge clk) begin
        if (!rst_n) ok <= 1'b1;
        if (!rst_n) begin
            pending <= 1'b0;
            age     <= 7'd0;
        end else if (start) begin
            pending <= 1'b1;
            age     <= 7'd1;
        end else if (pending) begin
            if (hit) begin
                pending <= 1'b0;
                age     <= 7'd0;
            end else
                age <= age + 7'd1;
        end
    end

    always @(*)
        if (ok) begin
            //start and its hit are never on the same clock
            assert (!(start && hit));
            //no second start while one is waiting for its hit
            assert (!start || !pending);
            //one hit per start, exactly n - 1 clocks after it, never missed
            assert (!hit || (pending && age == N - 1));
            assert (!(pending && age == N - 1) || hit);
            //the code counts at most all the taps
            assert (code <= N);

            //the tdc's own count matches, which is what makes it inductive
            assert (!start || (busy && left == N - 1));
            assert (!(pending && !hit) || (busy && age >= 1 && age + left == N - 1));
            assert (!hit || !busy);
            assert (pending || start || (!busy && age == 0));
            assert (!busy || (left >= 1 && code <= N - left));
        end

endmodule
