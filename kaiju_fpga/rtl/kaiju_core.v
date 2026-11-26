`timescale 1ns / 1ps
//=============================================================================
// Kaiju Rampage : everything on the 25 MHz clock (the testbench starts here)
//
//   vga_sync -> kaiju_render -> VGA pins
//   kaiju_game  <-> tile RAM (port A)      kaiju_render <- tile RAM (port B)
//   map ROM -> kaiju_game (copied into the tile RAM on reset / new game)
//   kaiju_game -> kaiju_sound -> audio jack (SW15 = sound on)
//   microphone -> kaiju_mic -> kaiju_game (roar)
//   score / HP / time -> 7-segment,  progress -> LED15..0,  form -> LED16,  roar -> LED17
//=============================================================================
module kaiju_core #(
    parameter DEMO = 0                  // 1 = Progress Presentation build (half of the work plan)
) (
    input  wire        clk,             // 25 MHz
    input  wire        rst,             // synchronous, active HIGH
    input  wire        BTNU, BTND, BTNL, BTNR, BTNC,
    input  wire [1:0]  SW,              // debug: force a form
    input  wire [1:0]  SW_MIC,          // SW13 SW12: microphone threshold
    input  wire        SW14,            // LED bar shows the microphone level
    input  wire        SW15,            // sound on
    input  wire        M_DATA,
    output wire        M_CLK, M_LRSEL,
    output wire [3:0]  VGA_R, VGA_G, VGA_B,
    output wire        VGA_HS, VGA_VS,
    output wire [15:0] LED,
    output wire        LED16_R, LED16_G, LED16_B,
    output wire        LED17_R, LED17_G, LED17_B,
    output wire [6:0]  SEG,             // {CG, CF, CE, CD, CC, CB, CA}, active LOW
    output wire        DP,
    output wire [7:0]  AN,
    output wire        AUD_PWM,
    output wire        AUD_SD
);
    //---------------- buttons and switches -> this clock (2 flip-flops)
    reg [10:0] in_1 = 0, in_2 = 0;
    always @(posedge clk) begin
        in_1 <= {SW14, SW_MIC, SW15, SW, BTNC, BTNU, BTND, BTNL, BTNR};
        in_2 <= in_1;
    end
    wire [4:0] btn      = in_2[4:0];     // {C, U, D, L, R}
    wire [1:0] sw       = in_2[6:5];
    wire       sound_on = in_2[7];
    wire [1:0] mic_thr  = in_2[9:8];
    wire       mic_led  = in_2[10];

    //---------------- VGA timing
    wire [9:0] x, y;
    wire       hsync, vsync, video_on;
    vga_sync u_sync (.clk(clk), .rst(rst), .x(x), .y(y),
                     .hsync(hsync), .vsync(vsync), .video_on(video_on));

    // one pulse per frame, at the first blank line: the game may change things now
    wire tick = (x == 10'd0) && (y == 10'd480);

    //---------------- memories
    wire [13:0] ram_addr, rom_addr, tile_addr;
    wire        ram_we;
    wire [3:0]  ram_din, ram_dout, rom_dout, tile_id;

    tile_ram #(.FILE("map.mem")) u_tiles (
        .clk(clk),
        .a_addr(ram_addr), .a_we(ram_we), .a_din(ram_din), .a_dout(ram_dout),
        .b_addr(tile_addr), .b_dout(tile_id));

    rom_1p #(.DW(4), .AW(14), .DEPTH(16384), .FILE("map.mem")) u_map_rom (
        .clk(clk), .addr(rom_addr), .q(rom_dout));

    //---------------- microphone
    wire       roar_req;
    wire [7:0] mic_level;
    kaiju_mic u_mic (.clk(clk), .thr_sel(mic_thr), .M_DATA(M_DATA), .M_CLK(M_CLK), .M_LRSEL(M_LRSEL),
                     .roar_req(roar_req), .level(mic_level));

    //---------------- game
    wire [10:0] cam_x, cam_y, spr_x, spr_y, shd_x, shd_y, it_x, it_y;
    wire [1:0]  spr_form, spr_frame, form, it_type;
    wire [2:0]  gstate, ov_page;
    wire        spr_mirror, spr_flash, spr_show, spr_shield, shd_on, fire_phase, dark, dark_spr;
    wire        ov_on, ov_blink, it_on, it_hide, music_on, shield_on, speed_on, roar_ready;
    wire [7:0]  anim, e_on_v, e_face_v, e_flash_v, b_on_v;
    wire [15:0] e_type_v, b_kind_v;
    wire [87:0] e_x_v, e_y_v, b_x_v, b_y_v;
    wire [3:0]  bm_on_v, bm_fr_v, hp;
    wire [43:0] bm_x_v, bm_y_v;
    wire [13:0] score;
    wire [7:0]  time_s;
    wire [15:0] led_bar;
    wire [8:0]  sfx;

    kaiju_game #(.DEMO(DEMO)) u_game (
        .clk(clk), .rst(rst), .tick(tick), .btn(btn), .sw(sw), .roar_req(roar_req),
        .ram_addr(ram_addr), .ram_we(ram_we), .ram_din(ram_din), .ram_dout(ram_dout),
        .rom_addr(rom_addr), .rom_dout(rom_dout),
        .cam_x(cam_x), .cam_y(cam_y), .spr_x(spr_x), .spr_y(spr_y),
        .spr_form(spr_form), .spr_frame(spr_frame), .spr_mirror(spr_mirror), .spr_flash(spr_flash),
        .spr_show(spr_show), .spr_shield(spr_shield),
        .shd_on(shd_on), .shd_x(shd_x), .shd_y(shd_y), .fire_phase(fire_phase),
        .dark(dark), .dark_spr(dark_spr), .ov_on(ov_on), .ov_page(ov_page), .ov_blink(ov_blink),
        .anim(anim),
        .e_on_v(e_on_v), .e_type_v(e_type_v), .e_x_v(e_x_v), .e_y_v(e_y_v),
        .e_face_v(e_face_v), .e_flash_v(e_flash_v),
        .b_on_v(b_on_v), .b_x_v(b_x_v), .b_y_v(b_y_v), .b_kind_v(b_kind_v),
        .bm_on_v(bm_on_v), .bm_x_v(bm_x_v), .bm_y_v(bm_y_v), .bm_fr_v(bm_fr_v),
        .it_on(it_on), .it_type(it_type), .it_x(it_x), .it_y(it_y), .it_hide(it_hide),
        .sfx(sfx), .music_on(music_on),
        .score(score), .time_s(time_s), .hp(hp), .form(form), .gstate(gstate), .led_bar(led_bar),
        .shield_on(shield_on), .speed_on(speed_on), .roar_ready(roar_ready));

    //---------------- picture
    kaiju_render u_render (
        .clk(clk), .x(x), .y(y), .hsync(hsync), .vsync(vsync), .video_on(video_on),
        .cam_x(cam_x), .cam_y(cam_y), .spr_x(spr_x), .spr_y(spr_y),
        .spr_form(spr_form), .spr_frame(spr_frame), .spr_mirror(spr_mirror), .spr_flash(spr_flash),
        .spr_show(spr_show), .spr_shield(spr_shield),
        .shd_on(shd_on), .shd_x(shd_x), .shd_y(shd_y), .fire_phase(fire_phase),
        .dark(dark), .dark_spr(dark_spr), .ov_on(ov_on), .ov_page(ov_page), .ov_blink(ov_blink),
        .anim(anim),
        .e_on_v(e_on_v), .e_type_v(e_type_v), .e_x_v(e_x_v), .e_y_v(e_y_v),
        .e_face_v(e_face_v), .e_flash_v(e_flash_v),
        .b_on_v(b_on_v), .b_x_v(b_x_v), .b_y_v(b_y_v), .b_kind_v(b_kind_v),
        .bm_on_v(bm_on_v), .bm_x_v(bm_x_v), .bm_y_v(bm_y_v), .bm_fr_v(bm_fr_v),
        .it_on(it_on), .it_hide(it_hide), .it_type(it_type), .it_x(it_x), .it_y(it_y),
        .tile_addr(tile_addr), .tile_id(tile_id),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS));

    //---------------- sound
    kaiju_sound u_sound (.clk(clk), .rst(rst), .tick(tick), .en(sound_on && !DEMO), .music_on(music_on),
                         .sfx(sfx), .AUD_PWM(AUD_PWM), .AUD_SD(AUD_SD));

    //---------------- 7-segment:  SCORE (4) | HP (1) | TIME (3)
    //   decimal point of the HP digit = shield, of the last digit = speed item
    wire [15:0] score_bcd;
    wire [15:0] time_bcd;
    bin2bcd #(.W(14), .D(4)) u_bcd_score (.clk(clk), .bin(score), .bcd(score_bcd));
    bin2bcd #(.W(8),  .D(4)) u_bcd_time  (.clk(clk), .bin(time_s), .bcd(time_bcd));

    localparam [2:0] G_PLAY = 0, G_EVOLVE = 1, G_WIN = 2, G_OVER = 3, G_TITLE = 4;

    wire [31:0] digits = (gstate == G_TITLE) ? 32'hEEEE_FEEE                       // title: "---- ---"
                                             : {score_bcd, DEMO ? {2'b0, form} + 4'd1 : hp, time_bcd[11:0]};
    wire [7:0]  dps    = (gstate == G_TITLE) ? 8'h00 : {4'b0, shield_on, 2'b0, speed_on};
    seg7_mux u_seg (.clk(clk), .digits(digits), .dp(dps), .seg(SEG), .an(AN), .dp_n(DP));

    //---------------- LEDs
    reg [23:0] slow = 0;
    always @(posedge clk) slow <= slow + 1'b1;

    // title: one LED runs back and forth
    wire [3:0] run = slow[23] ? ~slow[22:19] : slow[22:19];
    // SW14: microphone meter (16 LEDs = level 128)
    wire [4:0] mic_bars = (mic_level >= 8'd128) ? 5'd16 : mic_level[7:3];
    wire [15:0] meter   = (mic_bars == 16) ? 16'hFFFF : ((16'h1 << mic_bars[3:0]) - 16'h1);

    // LED15..0 : progress bar.  WIN: the whole bar blinks.  GAME OVER: off.
    assign LED = mic_led             ? meter :
                 (gstate == G_TITLE) ? (16'h1 << run) :
                 (gstate == G_WIN)   ? {16{slow[22]}} :
                 (gstate == G_OVER)  ? 16'h0000 : led_bar;

    // LED16 : colour of the form (green / yellow / red), dimmed to 1/16, blinks while evolving
    wire dim_on = (slow[3:0] == 4'd0);
    wire rgb_on = dim_on && (gstate != G_TITLE) && !(gstate == G_EVOLVE && slow[21]);
    assign LED16_R = rgb_on && (form != 0);
    assign LED16_G = rgb_on && (form != 2);
    assign LED16_B = 1'b0;

    // LED17 : roar (microphone) blue = ready, red = resting
    wire playing = (gstate == G_PLAY) || (gstate == G_EVOLVE);
    assign LED17_B = !DEMO && dim_on && playing && roar_ready;
    assign LED17_R = !DEMO && dim_on && playing && !roar_ready;
    assign LED17_G = 1'b0;
endmodule
