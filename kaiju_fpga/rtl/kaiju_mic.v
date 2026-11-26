`timescale 1ns / 1ps
//=============================================================================
// Kaiju Rampage : shout detector on the on-board PDM microphone       (Feature 3.7)
//
// The microphone sends 1 bit per M_CLK.  The more 1s in a short window, the
// higher the sound wave is at that moment; silence gives about half 1s.
//   M_CLK  = 25 MHz / 10 = 2.5 MHz, M_LRSEL = 0 (data is read on the rising edge)
//   window = 256 bits (0.1 ms):    amp   = | ones - 128 |
//   period = 128 windows (13 ms):  level = biggest amp in the period
//   loud   = level > threshold     (SW13 SW12: 00 normal 32, 01 easy 20, 10 hard 48, 11 harder 72)
//   3 loud periods in a row (~40 ms) -> roar_req (one clock)
//=============================================================================
module kaiju_mic (
    input  wire       clk,              // 25 MHz
    input  wire [1:0] thr_sel,
    input  wire       M_DATA,
    output reg        M_CLK = 0,
    output wire       M_LRSEL,
    output reg        roar_req = 0,
    output reg  [7:0] level = 0         // for the LED meter (SW14)
);
    assign M_LRSEL = 1'b0;

    reg [3:0] div = 0;
    reg       d_1 = 0, d_2 = 0;         // M_DATA moved to this clock
    always @(posedge clk) begin
        div   <= (div == 4'd9) ? 4'd0 : div + 1'b1;
        M_CLK <= (div >= 4'd4) && (div <= 4'd8);    // high for 5 clocks, low for 5
        d_1 <= M_DATA;  d_2 <= d_1;
    end
    wire sample = (div == 4'd3);        // just before M_CLK rises (the data is still steady)

    reg  [7:0] nbit = 0;                // bits in this window
    reg  [8:0] ones = 0;
    reg  [6:0] nwin = 0;                // windows in this period
    reg  [7:0] peak = 0;
    reg  [1:0] loud_run = 0;
    wire [8:0] ones_n = ones + d_2;
    wire [8:0] amp9   = (ones_n >= 9'd128) ? ones_n - 9'd128 : 9'd128 - ones_n;
    wire [7:0] amp    = amp9[8] ? 8'd255 : amp9[7:0];
    wire [7:0] thr    = (thr_sel == 2'd1) ? 8'd20 : (thr_sel == 2'd2) ? 8'd48 : (thr_sel == 2'd3) ? 8'd72 : 8'd32;

    always @(posedge clk) begin
        roar_req <= 1'b0;
        if (sample) begin
            if (nbit == 8'd255) begin                       // end of a window
                nbit <= 0;  ones <= 0;
                if (nwin == 7'd127) begin                   // end of a period
                    nwin  <= 0;
                    level <= (amp > peak) ? amp : peak;
                    peak  <= 0;
                    if (((amp > peak) ? amp : peak) > thr) begin
                        if (loud_run == 2'd2) begin roar_req <= 1'b1; loud_run <= 0; end
                        else loud_run <= loud_run + 1'b1;
                    end else
                        loud_run <= 0;
                end else begin
                    nwin <= nwin + 1'b1;
                    if (amp > peak) peak <= amp;
                end
            end else begin
                nbit <= nbit + 1'b1;
                ones <= ones_n;
            end
        end
    end
endmodule
