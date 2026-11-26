`timescale 1ns / 1ps
//=============================================================================
// CPE222 Final Project : Kaiju Rampage  (Group04)   Nexys A7-100T
//
//   BTNU / BTND / BTNL / BTNR   walk            BTNC        start / jump
//   CPU RESET                   restart (the city is rebuilt)
//   SW1 SW0                     debug: 00 normal, 01 / 10 / 11 force form 1 / 2 / 3
//   SW13 SW12                   microphone threshold: 00 normal, 01 easy, 10 hard, 11 harder
//   SW14                        LED15..0 show the microphone level
//   SW15                        sound on (mono audio jack)
//   microphone                  shout -> roar, enemies nearby are stunned
//   VGA                         640 x 480 @ 60 Hz, game picture 320 x 240 shown 2x
//   7-segment                   SCORE (4 digits) | HP | TIME (seconds left)
//                               dot after HP = shield, dot after TIME = speed item
//   LED15..0                    progress to the next goal
//   LED16                       form colour: green / yellow / red
//   LED17                       roar: blue = ready, red = resting
//=============================================================================
module kaiju_top #(
    parameter DEMO = 0                  // 1 = Progress Presentation build (build.tcl demo)
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNU, BTND, BTNL, BTNR, BTNC,
    input  wire [1:0]  SW,
    input  wire        SW12, SW13, SW14, SW15,
    input  wire        M_DATA,
    output wire        M_CLK, M_LRSEL,
    output wire [3:0]  VGA_R, VGA_G, VGA_B,
    output wire        VGA_HS, VGA_VS,
    output wire [15:0] LED,
    output wire        LED16_R, LED16_G, LED16_B,
    output wire        LED17_R, LED17_G, LED17_B,
    output wire        CA, CB, CC, CD, CE, CF, CG, DP,
    output wire [7:0]  AN,
    output wire        AUD_PWM, AUD_SD
);
    // 100 MHz -> 25 MHz pixel clock
    wire clk, locked;
    clk_gen u_clk (.clk100(CLK100MHZ), .clk25(clk), .locked(locked));

    // reset, moved to the 25 MHz clock
    reg rst_1 = 1'b1, rst = 1'b1;
    always @(posedge clk) {rst, rst_1} <= {rst_1, ~(locked & CPU_RESETN)};

    wire [6:0] seg;
    kaiju_core #(.DEMO(DEMO)) u_core (
        .clk(clk), .rst(rst),
        .BTNU(BTNU), .BTND(BTND), .BTNL(BTNL), .BTNR(BTNR), .BTNC(BTNC),
        .SW(SW), .SW_MIC({SW13, SW12}), .SW14(SW14), .SW15(SW15),
        .M_DATA(M_DATA), .M_CLK(M_CLK), .M_LRSEL(M_LRSEL),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .LED(LED), .LED16_R(LED16_R), .LED16_G(LED16_G), .LED16_B(LED16_B),
        .LED17_R(LED17_R), .LED17_G(LED17_G), .LED17_B(LED17_B),
        .SEG(seg), .DP(DP), .AN(AN), .AUD_PWM(AUD_PWM), .AUD_SD(AUD_SD));

    assign {CG, CF, CE, CD, CC, CB, CA} = seg;
endmodule
