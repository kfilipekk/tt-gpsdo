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
    localparam [23:0] NOM = 24'd1664;  //same remainder mod 1024 as 10 mhz
    localparam [6:0]  DIV = 7'd4;
`else
    localparam [23:0] NOM = 24'd10000000;
    localparam [6:0]  DIV = 7'd87;  //115200 baud
`endif

    wire [9:0] rdiv;
    ring u_ring (.rst_n(rst_n), .en(ring_on), .div(rdiv));

    //phase counter, wraps once a nominal second. it is the pps output and
    //the coarse timebase, so missed pulses alias back onto the right phase
    reg [23:0] pcnt;
    reg        launch, launch_n, half, l1, l2;
    wire       mid = pcnt == NOM / 2;
    wire       line_in = (pps_in & !cal) | (half ? launch_n : launch) | (rdiv[5] & cal);

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
            launch <= !cal && mid;
            l1     <= launch;
            l2     <= l1;
        end

    //on a fast die the cycle can be longer than the line, then the pulse
    //goes in on the falling edge and covers half a cycle
    always @(negedge clk)
        if (!rst_n) launch_n <= 1'b0;
        else        launch_n <= launch;

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

    //a full line switches to half cycles, and back once a full cycle fits
    //with a few taps to spare
    reg [6:0] taps;
    always @(posedge clk)
        if (!rst_n) begin
            taps <= 7'd29;
            half <= 1'b0;
        end else if (hit && self_ev) begin
            if (code == N) half <= 1'b1;
            else if (half) begin
                taps <= {code[5:0], 1'b0};
                half <= code > N / 2 - 2;
            end else
                taps <= code;
        end

    wire        locked;
    wire        pps_start = start && !l2 && !cal;
    wire        wrap = pcnt == NOM - 24'd1;
    localparam [23:0] JAM = 24'd8;

    reg       busy;
    reg [7:0] ph_now, ph_prev;
    reg [6:0] f_prev;
    reg       have, jammed, upper;
    reg [1:0] wraps;

    always @(posedge clk)
        if (!rst_n)                       pcnt <= 24'd0;
        else if (pps_start && !locked)    pcnt <= JAM;
        else if (wrap)                    pcnt <= 24'd0;
        else                              pcnt <= pcnt + 24'd1;

    //the phase is kept as the low byte of the offset from the nearest wrap.
    //a second is 128 mod 256 clocks, so the top half of the count has that
    //taken off, which only flips bit 7, else a pulse either side of the
    //wrap would look 128 clocks apart
    always @(posedge clk)
        if (!rst_n || wrap || (pps_start && !locked)) upper <= 1'b0;
        else if (mid)                                 upper <= 1'b1;
    wire [7:0] ph = {pcnt[7] ^ (upper & NOM[7]), pcnt[6:0]};

    //holdover once two seconds pass without a pulse
    wire lost = wraps[1];
    always @(posedge clk)
        if (!rst_n || pps_start) wraps <= 2'd0;
        else if (wrap && !lost)  wraps <= wraps + 2'd1;

    //phase error over the last second in taps, positive when clk is slow:
    //cycles short of nominal times taps per cycle, plus the change in code
    //it pulls in from up to 63 clocks a second either way, 6 ppm
    wire [7:0] dc   = ph_prev - ph_now;
    wire       near = dc[7:6] == 2'b00 || dc[7:6] == 2'b11;
    //inside a cycle either way the step is exact, further out cycles times
    //32 is close enough while it pulls in
    wire signed [14:0] cyc = (dc == 8'd1)   ?  $signed({8'd0, taps}) :
                             (dc == 8'hFF)  ? -$signed({8'd0, taps}) :
                             $signed({{2{dc[7]}}, dc, 5'd0});
    wire signed [14:0] err = cyc + $signed({8'd0, code}) - $signed({8'd0, f_prev});
    wire upd = hit && pps_ev && have && near;

    always @(posedge clk)
        if (!rst_n) begin
            ph_now  <= 8'd0;
            ph_prev <= 8'd0;
            f_prev  <= 7'd0;
            have    <= 1'b0;
            jammed  <= 1'b0;
        end else begin
            if (pps_start) begin
                ph_now <= ph;
                jammed <= !locked;
            end
            if (hit && pps_ev) begin
                //a jam put pcnt at JAM on the clock after the start
                ph_prev <= jammed ? JAM[7:0] - 8'd1 : ph_now;
                f_prev  <= code;
                have    <= 1'b1;
            end else if (hit && cal_ev && !busy)
                f_prev  <= code;
            if (lost) have <= 1'b0;
        end

    wire [15:0] dac;
    loop u_loop (
        .clk(clk), .rst_n(rst_n), .upd(upd), .err(err), .gain(gain),
        .hold(hold_in || lost), .clr(lost), .dac(dac), .locked(locked)
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

    //telemetry, one line per pps: cycles short of nominal, code, taps per
    //cycle, dac word, status. in cal mode the code of each ring edge.
    //everything shown holds still until the next pulse
    reg [3:0] idx;
    reg       short;
    wire      tx_ready;

    function [7:0] hx(input [3:0] v);
        hx = (v < 4'd10) ? 8'h30 + {4'd0, v} : 8'h37 + {4'd0, v};
    endfunction

    //cycles short, clamped to what two hex digits can show
    wire       dc_big = !(&dc[9:7] || ~|dc[9:7]);
    wire [7:0] dc_tx  = have ? dc : 8'd0;
    wire [3:0] status = {have, cal, lost, locked};

    reg [3:0] nib;
    always @(*)
        case (idx)
            4'd0:    nib = dc_tx[7:4];
            4'd1:    nib = dc_tx[3:0];
            4'd3:    nib = {1'b0, f_prev[6:4]};
            4'd4:    nib = f_prev[3:0];
            4'd6:    nib = {1'b0, taps[6:4]};
            4'd7:    nib = taps[3:0];
            4'd9:    nib = dac[15:12];
            4'd10:   nib = dac[11:8];
            4'd11:   nib = dac[7:4];
            4'd12:   nib = dac[3:0];
            default: nib = status;
        endcase
    wire       gap = idx == 4'd2 || idx == 4'd5 || idx == 4'd8 || idx == 4'd13;
    wire [7:0] ch  = idx == 4'd15 ? 8'h0A : gap ? 8'h20 : hx(nib);

    reg tx_valid;
    wire send = hit && (pps_ev || cal_ev);
    always @(posedge clk)
        if (!rst_n) begin
            idx      <= 4'd0;
            busy     <= 1'b0;
            short    <= 1'b0;
            tx_valid <= 1'b0;
        end else if (!busy) begin
            if (send) begin
                busy     <= 1'b1;
                short    <= cal_ev;
                idx      <= cal_ev ? 4'd3 : 4'd0;
                tx_valid <= 1'b1;
            end
        end else if (tx_ready && !tx_valid) begin
            tx_valid <= 1'b1;
        end else if (tx_valid && tx_ready) begin
            tx_valid <= 1'b0;
            if (idx == 4'd15)
                busy <= 1'b0;
            else
                idx <= (short && idx == 4'd4) ? 4'd15 : idx + 4'd1;
        end

    wire tx;
    uart_tx u_uart (
        .clk(clk), .rst_n(rst_n), .div(DIV), .data(ch), .valid(tx_valid),
        .ready(tx_ready), .tx(tx)
    );

    assign uo_out  = {line_in, seen, rdiv[9], lost, locked, pps_out, efc, tx};
    assign uio_out = dac[15:8];
    assign uio_oe  = 8'hFF;

    wire _unused = &{ena, uio_in, ui_in[7:6], rdiv[8:6], rdiv[4:0], 1'b0};

endmodule
