//tdc proof wrapper. the dut runs on free taps and a free input, the monitor
//pairs every start with the single hit it must produce
`default_nettype none

module tdc_f (
    input wire clk,
    input wire rst_n,
    input wire in
);

    localparam N   = 44;
    localparam GAP = N - 1;  //start to hit, both registered

    //hold reset for the first clocks, so the proof starts from a state that
    //is fully known, and arm the checks after it
    reg [1:0] boot  = 2'd0;
    reg       armed = 1'b0;
    wire      rst_n_i = rst_n && boot == 2'd3;

    always @(posedge clk) begin
        if (boot != 2'd3) boot <= boot + 2'd1;
        if (boot == 2'd3) armed <= 1'b1;
    end

    wire       start, hit;
    wire [6:0] code;

    tdc #(.N(N)) u_tdc (
        .clk(clk), .rst_n(rst_n_i), .in(in),
        .start(start), .hit(hit), .code(code)
    );

    //pending: a start is waiting for its hit, age: clocks since that start
    reg       pending;
    reg [7:0] age;

    always @(posedge clk)
        if (!rst_n_i) begin
            pending <= 1'b0;
            age     <= 8'd0;
        end else if (start) begin
            pending <= 1'b1;
            age     <= 8'd1;
        end else if (pending) begin
            if (hit) begin
                pending <= 1'b0;
                age     <= 8'd0;
            end else
                age <= age + 8'd1;
        end

    always @(posedge clk) begin
        //start and its hit are never on the same clock
        assert (!armed || !(start && hit));
        //no second start while one is waiting for its hit
        assert (!armed || !start || !pending);
        //one hit per start, exactly gap clocks after it
        assert (!armed || !hit || (pending && age == GAP));
        //and that hit is never missed
        assert (!armed || !(pending && age == GAP) || hit);
        //the code counts at most all the taps
        assert (!armed || code <= N);
    end

    //both ends of the pairing are reachable, so the proof is not vacuous
    always @(posedge clk) begin
        cover (armed && start);
        cover (armed && hit);
    end

endmodule
