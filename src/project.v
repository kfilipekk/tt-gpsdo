//gps disciplined oscillator controller. clk is the 10 mhz oscillator being
//steered. each gps pps is timed to a delay line tap, about a thirtieth of a
//cycle, the line calibrates itself against clk every second, and an
//integral loop steers the oscillator through a sigma delta dac
`default_nettype none

module tt_um_kfilipekk_gpsdo (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam N = 44;

    wire       pps_in  = ui_in[0];
    wire       hold_in = ui_in[1];
    wire       cal     = ui_in[2];
    wire       ring_on = ui_in[3] | cal;
    wire [1:0] gain    = ui_in[5:4];

    //a 10 mhz second. SIM_SHORT shrinks it for rtl simulation only
`ifdef SIM_SHORT
    localparam [23:0] NOM = 24'd2000;
`else
    localparam [23:0] NOM = 24'd10000000;
`endif

    wire [13:0] rdiv;
    ring u_ring (.rst_n(rst_n), .en(ring_on), .div(rdiv));

    //phase counter, wraps once a nominal second. it is the pps output and
    //the coarse timebase, so missed pulses alias back onto the right phase
    reg [23:0] pcnt;
    reg        launch, l1, l2;
    wire       line_in = (pps_in & !cal) | launch | (rdiv[5] & cal);

    wire       start, hit;
    wire [6:0] code;
    tdc #(.N(N)) u_tdc (
        .clk(clk), .rst_n(rst_n), .in(line_in), .start(start), .hit(hit), .code(code)
    );

    //mid second a one clock pulse goes into the line, the taps it covers by
    //the next edge are the taps in a cycle
    always @(posedge clk)
        if (!rst_n) begin
            launch <= 1'b0;
            l1     <= 1'b0;
            l2     <= 1'b0;
        end else begin
            launch <= !cal && pcnt == NOM / 2;
            l1     <= launch;
            l2     <= l1;
        end

    //classify on start, the code lands N clocks later
    reg self_ev, pps_ev, cal_ev;
    always @(posedge clk)
        if (!rst_n) begin
            self_ev <= 1'b0;
            pps_ev  <= 1'b0;
            cal_ev  <= 1'b0;
        end else if (start) begin
            self_ev <= l2;
            pps_ev  <= !l2 && !cal;
            cal_ev  <= !l2 && cal;
        end

    reg [6:0] taps;
    always @(posedge clk)
        if (!rst_n)                taps <= 7'd29;
        else if (hit && self_ev && code != N) taps <= code;

    wire        locked;
    wire        pps_start = start && !l2 && !cal;
    wire        wrap = pcnt == NOM - 24'd1;
    localparam [23:0] JAM = 24'd8;

    reg [7:0] ph_now, ph_prev;
    reg [6:0] f_prev;
    reg       have, jammed;
    reg [1:0] wraps;

    always @(posedge clk)
        if (!rst_n)                       pcnt <= 24'd0;
        else if (pps_start && !locked)    pcnt <= JAM;
        else if (wrap)                    pcnt <= 24'd0;
        else                              pcnt <= pcnt + 24'd1;

    //holdover once two seconds pass without a pulse
    wire lost = wraps[1];
    always @(posedge clk)
        if (!rst_n || pps_start) wraps <= 2'd0;
        else if (wrap && !lost)  wraps <= wraps + 2'd1;

    //phase error over the last second in taps, positive when clk is slow:
    //cycles short of nominal times taps per cycle, plus the change in code
    wire [7:0] dc   = ph_prev - ph_now;
    wire       near = dc[7:6] == 2'b00 || dc[7:6] == 2'b11;
    //inside a cycle either way the step is exact, further out cycles times
    //32 is close enough while it pulls in
    wire signed [14:0] cyc = (dc == 8'd1)   ?  $signed({8'd0, taps}) :
                             (dc == 8'hFF)  ? -$signed({8'd0, taps}) :
                             $signed({{2{dc[7]}}, dc, 5'd0});
    wire signed [14:0] err = cyc + $signed({8'd0, code}) - $signed({8'd0, f_prev});
    wire upd = hit && pps_ev && have && near && code != N;

    always @(posedge clk)
        if (!rst_n) begin
            ph_now  <= 8'd0;
            ph_prev <= 8'd0;
            f_prev  <= 7'd0;
            have    <= 1'b0;
            jammed  <= 1'b0;
        end else begin
            if (pps_start) begin
                ph_now <= pcnt[7:0];
                jammed <= !locked;
            end
            if (hit && pps_ev) begin
                //a jam put pcnt at JAM on the clock after the start
                ph_prev <= jammed ? JAM[7:0] - 8'd1 : ph_now;
                f_prev  <= code;
                have    <= code != N;
            end else if (hit && cal_ev)
                f_prev  <= code;
            if (lost) have <= 1'b0;
        end

    wire [15:0] dac;
    loop u_loop (
        .clk(clk), .rst_n(rst_n), .upd(upd), .err(err), .gain(gain),
        .hold(hold_in || lost), .dac(dac), .locked(locked)
    );

    reg [16:0] acc;
    always @(posedge clk)
        if (!rst_n) acc <= 17'd0;
        else        acc <= {1'b0, acc[15:0]} + {1'b0, dac};
    wire efc = acc[16];

    wire pps_out = pcnt < NOM / 8;

    reg seen;
    always @(posedge clk)
        if (!rst_n)         seen <= 1'b0;
        else if (pps_start) seen <= ~seen;

    wire tx = 1'b1;

    assign uo_out  = {line_in, seen, rdiv[13], lost, locked, pps_out, efc, tx};
    assign uio_out = dac[15:8];
    assign uio_oe  = 8'hFF;

    wire _unused = &{ena, uio_in, ui_in[7:6], rdiv[12:6], rdiv[4:0], 1'b0};

endmodule
