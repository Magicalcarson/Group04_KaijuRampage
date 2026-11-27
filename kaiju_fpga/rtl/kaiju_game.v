`timescale 1ns / 1ps
//=============================================================================
// Kaiju Rampage : game logic                                   (Group04, CPE222)
//
// One update per frame.  "tick" comes at the first blank line (y = 480), so the
// game changes the tile RAM, the player and the units while the picture is NOT
// being drawn.
//
//   Feature 1  walk 4 ways, jump with gravity, camera follows the player, the
//              player never leaves the map, collision with obstacles / items / enemies
//   Feature 2  3 forms: baby kaiju -> teen kaiju (20 trees) -> full kaiju (1500 points)
//   Feature 3  3.1 tile map   3.2 sound + music   3.3 score / HP / time
//              3.4 enemies that grow with the kaiju (police car, tank, helicopter,
//                  nuke truck) and their bullets
//              3.5 power-ups (heal, speed, shield)   3.6 the city really breaks
//              3.7 shout into the microphone -> roar -> enemies nearby are stunned
//
// Tile RAM port A belongs to this module only.  A read takes 3 states:
//   state 1 sets ram_addr, state 2 waits (the RAM reads), state 3 uses ram_dout.
// A write is one state: ram_addr / ram_din / ram_we are set, the RAM writes
// on the next clock.
//=============================================================================
module kaiju_game #(
    // DEMO = 1: the Progress Presentation build (work plan up to 19 Nov):
    //   forms 1 -> 2 only, no enemies / bullets / power-ups / roar
    parameter DEMO = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick,            // one pulse per frame (x = 0, y = 480)
    input  wire [4:0]  btn,             // {C, U, D, L, R}, already moved to this clock
    input  wire [1:0]  sw,              // debug: 0 = normal, 1/2/3 = force form 1/2/3
    input  wire        roar_req,        // pulse: the microphone heard a shout

    // tile RAM, port A
    output reg  [13:0] ram_addr = 0,
    output reg         ram_we   = 0,
    output reg  [3:0]  ram_din  = 0,
    input  wire [3:0]  ram_dout,

    // map ROM (the original city, copied to the tile RAM on reset)
    output wire [13:0] rom_addr,
    input  wire [3:0]  rom_dout,

    // for the picture (they change only in the blank lines)
    output reg  [10:0] cam_x = 0, cam_y = 0,     // top-left of the screen, in map pixels
    output reg  [10:0] spr_x = 0, spr_y = 0,     // top-left of the player sprite
    output reg  [1:0]  spr_form   = 0,           // which sprite ROM
    output reg  [1:0]  spr_frame  = 0,           // 0 stand, 1 step, 2 other step, 3 roar
    output reg         spr_mirror = 0,           // sprites face left; mirror to face right
    output reg         spr_flash  = 0,           // white flash while evolving
    output reg         spr_show   = 1,           // 0 = hidden (blinking after a hit)
    output reg         spr_shield = 0,           // shield: blue outline
    output reg         shd_on     = 0,           // shadow on the ground while jumping
    output reg  [10:0] shd_x = 0, shd_y = 0,     // centre of the shadow
    output reg         fire_phase = 0,           // fire tiles flicker
    output reg         dark       = 0,           // title / end: darker city
    output reg         dark_spr   = 0,           // end: darker player too
    output reg         ov_on      = 0,           // text page on top of the picture
    output reg  [2:0]  ov_page    = 0,           // 0 title 1 city cleared 2 time up 3 beast! 4 kaiju! 5 game over
    output reg         ov_blink   = 0,           // "PRESS BTNC" is shown when 1
    output wire [7:0]  anim,                     // frame counter, for unit animation

    // units for the picture: 8 enemies, 8 bullets, 4 explosions, 1 item
    output wire [7:0]  e_on_v,
    output wire [15:0] e_type_v,
    output wire [87:0] e_x_v, e_y_v,             // centres, map pixels
    output wire [7:0]  e_face_v,                 // 1 = facing right
    output wire [7:0]  e_flash_v,                // stunned: blinks white
    output wire [7:0]  b_on_v,
    output wire [87:0] b_x_v, b_y_v,             // centres, map pixels
    output wire [15:0] b_kind_v,                 // 0 police, 1 tank, 2 helicopter
    output wire [3:0]  bm_on_v,
    output wire [43:0] bm_x_v, bm_y_v,           // centres
    output wire [3:0]  bm_fr_v,                  // explosion frame
    output reg         it_on = 0,
    output reg  [1:0]  it_type = 0,              // 0 heal, 1 speed, 2 shield
    output reg  [10:0] it_x = 0, it_y = 0,       // centre
    output reg         it_hide = 0,              // blinking before it goes away

    // sound: one-clock pulses {roar, pickup, hit, over, fanfare, stomp, smash, jump, eat}
    output reg  [8:0]  sfx = 0,
    output wire        music_on,

    // for the board
    output reg  [13:0] score  = 0,
    output reg  [7:0]  time_s = 8'd240,
    output reg  [3:0]  hp     = 4'd3,
    output reg  [1:0]  form   = 0,
    output reg  [2:0]  gstate = 3'd4,
    output reg  [15:0] led_bar = 0,
    output wire        shield_on,
    output wire        speed_on,
    output wire        roar_ready
);
    //-------------------------------------------------------------------------
    // constants
    //-------------------------------------------------------------------------
    localparam [3:0] T_GRASS = 0, T_ROAD_H = 1, T_ROAD_V = 2, T_ROAD_X = 3, T_PLAZA = 4,
                     T_WATER = 5, T_EMBANK = 6, T_TREE = 7, T_CAR = 8, T_HOUSE = 9,
                     T_TWR_TL = 10, T_TWR_TR = 11, T_TWR_BL = 12, T_TWR_BR = 13,
                     T_RUBBLE = 14, T_FIRE = 15;

    localparam [2:0] G_PLAY = 0, G_EVOLVE = 1, G_WIN = 2, G_OVER = 3, G_TITLE = 4;
    localparam [8:0] SFX_EAT = 9'd1, SFX_JUMP = 9'd2, SFX_SMASH = 9'd4, SFX_STOMP = 9'd8,
                     SFX_FANFARE = 9'd16, SFX_OVER = 9'd32, SFX_HIT = 9'd64, SFX_PICKUP = 9'd128,
                     SFX_ROAR = 9'd256;
    localparam [10:0] TITLE_CAM_Y = 11'd300;   // the title shows downtown, panning slowly

    localparam [10:0] START_X = 11'd1080, START_Y = 11'd1388;   // feet of the baby kaiju
    localparam [10:0] MAP_Y1  = 11'd1535;                        // last map pixel row
    localparam        EVO_TREES = 20, EVO_SCORE = 1500;
    localparam        GOAL      = 600;          // 25 % of the 2,399 building tiles
    localparam        TIME_S    = 240;
    localparam        MAP_TILES = 12288;        // 128 x 96

    localparam [7:0] P_TREE = 5, P_CAR = 20, P_HOUSE = 30, P_TOWER = 100, P_UNIT = 50, P_BIG = 100;

    localparam [1:0] E_POLICE = 0, E_TANK = 1, E_HELI = 2, E_NUKE = 3;

    //-------------------------------------------------------------------------
    // numbers for each form (form 3 is never used, it acts like form 2)
    //-------------------------------------------------------------------------
    function [2:0] f_speed;   input [1:0] f; f_speed  = f == 0 ? 3'd4  : f == 1 ? 3'd3  : 3'd2;  endfunction // half px / frame
    function [4:0] f_hbw;     input [1:0] f; f_hbw    = f == 0 ? 5'd5  : f == 1 ? 5'd10 : 5'd14; endfunction // half width of the feet box
    function [3:0] f_bh;      input [1:0] f; f_bh     = f == 0 ? 4'd6  : f == 1 ? 4'd8  : 4'd10; endfunction // height of the feet box
    function [7:0] f_jump;    input [1:0] f; f_jump   = f == 0 ? 8'd26 : f == 1 ? 8'd22 : 8'd20; endfunction // jump speed, 1/8 px
    function [5:0] f_size;    input [1:0] f; f_size   = f == 0 ? 6'd16 : f == 1 ? 6'd32 : 6'd48; endfunction // sprite is size x size
    function [10:0] f_x0;     input [1:0] f; f_x0     = f == 0 ? 11'd8    : f == 1 ? 11'd16   : 11'd24;   endfunction
    function [10:0] f_x1;     input [1:0] f; f_x1     = f == 0 ? 11'd2040 : f == 1 ? 11'd2032 : 11'd2024; endfunction
    // y0 = sprite height - 1 + jump peak (23 / 17 / 14 px), so even the top of a jump stays on the map
    function [10:0] f_y0;     input [1:0] f; f_y0     = f == 0 ? 11'd38   : f == 1 ? 11'd48   : 11'd61;   endfunction
    function [1:0] f_rh;      input [1:0] f; f_rh     = f == 2 ? 2'd3 : 2'd2; endfunction                      // shadow half height
    function [3:0] f_hp;      input [1:0] f; f_hp     = f == 0 ? 4'd3 : f == 1 ? 4'd6 : 4'd9; endfunction       // full HP
    function [4:0] f_hx;      input [1:0] f; f_hx     = f == 0 ? 5'd5 : f == 1 ? 5'd10 : 5'd15; endfunction    // body half width
    function [4:0] f_hy;      input [1:0] f; f_hy     = f == 0 ? 5'd7 : f == 1 ? 5'd14 : 5'd21; endfunction    // body half height
    function [3:0] f_cap;     input [1:0] f; f_cap    = f == 0 ? 4'd4 : f == 1 ? 4'd8 : 4'd8; endfunction       // enemies at most
    function [7:0] f_every;   input [1:0] f; f_every  = f == 0 ? 8'd100 : f == 1 ? 8'd70 : 8'd55; endfunction  // frames between spawns

    // enemy numbers by type
    function [7:0] e_keep;    input [1:0] t; e_keep   = t == E_POLICE ? 8'd80 : t == E_TANK ? 8'd100 : t == E_HELI ? 8'd110 : 8'd0; endfunction
    function [7:0] e_cdbase;  input [1:0] t; e_cdbase = t == E_POLICE ? 8'd110 : t == E_TANK ? 8'd150 : 8'd120; endfunction

    function [13:0] add_pts;  // score, at most 9999
        input [13:0] s; input [7:0] p;
        add_pts = (s + p > 14'd9999) ? 14'd9999 : s + p;
    endfunction

    // vehicles drive on roads, grass, plaza, embankment, rubble and fire
    function v_pass; input [3:0] t;
        v_pass = !(t == T_WATER || t == T_TREE || t == T_CAR || t == T_HOUSE || (t >= T_TWR_TL && t <= T_TWR_BR));
    endfunction
    // items are put on open ground only
    function i_pass; input [3:0] t;
        i_pass = (t <= T_PLAZA) || (t == T_RUBBLE);
    endfunction
    // bullets are stopped by houses and towers
    function b_block; input [3:0] t;
        b_block = (t == T_HOUSE) || (t >= T_TWR_TL && t <= T_TWR_BR);
    endfunction

    // 8 directions: 0 E, 1 SE, 2 S, 3 SW, 4 W, 5 NW, 6 N, 7 NE  ->  unit vector
    function signed [1:0] dir_x; input [2:0] d;
        dir_x = (d == 0 || d == 1 || d == 7) ? 2'sd1 : (d == 3 || d == 4 || d == 5) ? -2'sd1 : 2'sd0;
    endfunction
    function signed [1:0] dir_y; input [2:0] d;
        dir_y = (d == 1 || d == 2 || d == 3) ? 2'sd1 : (d == 5 || d == 6 || d == 7) ? -2'sd1 : 2'sd0;
    endfunction

    //-------------------------------------------------------------------------
    // state
    //-------------------------------------------------------------------------
    localparam [5:0] S_COPY = 0, S_INIT = 1, S_IDLE = 2, S_FRAME = 3, S_STEP = 4, S_AX = 5,
                     S_T_RD = 6, S_T_WAIT = 7, S_T_USE = 8, S_TW0 = 9, S_TW1 = 10, S_TW2 = 11,
                     S_TW3 = 12, S_T_NEXT = 13, S_JUMP = 14, S_LAND = 15, S_EVO = 16,
                     S_CLAMP = 17, S_END = 18, S_CAM = 19, S_SC_RD = 20, S_SC_WAIT = 21,
                     S_SC_USE = 22,
                     S_ITEM = 23, S_IT_WAIT = 24, S_IT_USE = 25,
                     S_E_START = 26, S_E_MOVE = 27, S_E_WAIT = 28, S_E_USE = 29, S_E_FIRE = 30,
                     S_E_SHOT = 31, S_E_NEXT = 32,
                     S_B_START = 33, S_B_WAIT = 34, S_B_USE = 35, S_B_NEXT = 36,
                     S_SP_START = 37, S_SP_WAIT = 38, S_SP_USE = 39;
    reg [5:0] st = S_COPY;

    reg [10:0] px = START_X, py = START_Y;   // point between the feet, map pixels
    reg        face_r = 0;
    reg        acc = 0;                      // half pixel left over
    reg [1:0]  steps_left = 0;               // 1-px steps still to do this frame
    reg        sub = 0;                      // 0: x step next, 1: y step next
    reg        movx = 0, movy = 0, dir_xp = 0, dir_yp = 0;
    reg        axis_y = 0;
    reg [2:0]  walk_t = 0;
    reg [1:0]  walk_phase = 0;
    reg signed [9:0] z  = 0;                 // height above the ground, 1/8 px
    reg signed [7:0] vz = 0;                 // vertical speed, 1/8 px per frame
    reg        jump_req = 0, c_prev = 0;
    reg [4:0]  trees = 0;
    reg [11:0] destroyed = 0;                // building tiles destroyed
    reg [4:0]  shake = 0;
    reg [5:0]  stomp_cd = 0;
    reg [4:0]  roar_t = 0;
    reg [6:0]  evo_t = 0;
    reg [7:0]  frame_cnt = 0;
    reg [5:0]  sec_div = 0;
    reg [1:0]  clamp_form = 0;
    reg [15:0] lfsr = 16'hACE1;
    reg [10:0] title_x = 0;                  // camera x on the title page
    reg        title_dir = 0;                // 0 = pan right

    // HP, power-ups, roar
    reg [6:0]  inv = 0;                      // frames of "can't be hurt" after a hit
    reg        shield = 0;
    reg [9:0]  shield_t = 0, speed_t = 0;
    reg [9:0]  it_t = 0, it_spawn = 0;
    reg [8:0]  roar_cd = 0;
    reg        roar_pend = 0, roar_now = 0, stomp_now = 0;

    // touch loop: tiles (lx0..lx1) x (ly0..ly1), signed because the stomp may reach past the map edge
    reg signed [8:0] lx0 = 0, lx1 = 0, ly0 = 0, ly1 = 0, lx = 0, ly = 0;
    reg [6:0]  ox0 = 0, ox1 = 0, oy0 = 0, oy1 = 0;   // tiles under the feet BEFORE the step
    reg        mode = 0;                     // 0 = step (may block), 1 = stomp
    reg        ok = 0;                       // the step is allowed
    reg [10:0] nx = 0, ny = 0;               // position after the step
    reg [6:0]  tox = 0, toy = 0;             // top-left tile of a tower being smashed
    reg [14:0] copy_i = 0;
    reg [13:0] ci_d = 0;
    reg        cv_d = 0;
    reg [13:0] scan_i = 0;

    //---------------- enemies (8 slots)
    reg [7:0]  e_on = 0, e_face = 0;
    reg [1:0]  e_type [0:7];
    reg [10:0] e_x [0:7], e_y [0:7];         // centre
    reg [7:0]  e_cd [0:7];                   // frames until the next shot
    reg [6:0]  e_stun [0:7];
    reg [1:0]  e_wdir [0:7];                 // wander direction when stuck
    reg [4:0]  e_wt [0:7];                   // wander frames left
    reg [2:0]  ei = 0;
    reg        e_try = 0;                    // 0 = first axis, 1 = second axis
    reg [10:0] cx = 0, cy = 0;               // candidate position
    reg [1:0]  shots = 0;
    reg [1:0]  shot_k = 0;
    reg [2:0]  shot_dir = 0;
    reg [7:0]  spawn_t = 0;

    //---------------- bullets (8 slots), position in half pixels
    reg [7:0]  b_on = 0;
    reg [11:0] b_x [0:7], b_y [0:7];
    reg [2:0]  b_dir [0:7];
    reg [1:0]  b_kind [0:7];
    reg [6:0]  b_t [0:7];
    reg [2:0]  bi = 0;

    //---------------- explosions (4 slots)
    reg [10:0] bm_x [0:3], bm_y [0:3];
    reg [4:0]  bm_t [0:3];
    reg [1:0]  bm_next = 0;

    //---------------- spawn candidate
    reg [10:0] sp_x = 0, sp_y = 0;
    reg [1:0]  sp_type = 0;
    reg [6:0]  it_tx = 0, it_ty = 0;

    wire [1:0] dbg = (DEMO && sw == 2'd3) ? 2'd2 : sw;    // the demo has no form 3
    assign rom_addr = copy_i[13:0];
    assign anim     = frame_cnt;
    assign music_on = (gstate == G_PLAY) || (gstate == G_EVOLVE);
    assign shield_on  = shield;
    assign speed_on   = (speed_t != 0);
    assign roar_ready = (roar_cd == 0);

    // 16-bit LFSR, one step every clock
    always @(posedge clk) lfsr <= lfsr[0] ? ((lfsr >> 1) ^ 16'hB400) : (lfsr >> 1);

    //-------------------------------------------------------------------------
    // units -> flat buses for the picture
    //-------------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_units
            assign e_type_v[2*gi +: 2]  = e_type[gi];
            assign e_x_v[11*gi +: 11]   = e_x[gi];
            assign e_y_v[11*gi +: 11]   = e_y[gi];
            assign e_flash_v[gi]        = (e_stun[gi] != 0) && frame_cnt[2];
            assign b_x_v[11*gi +: 11]   = b_x[gi][11:1];
            assign b_y_v[11*gi +: 11]   = b_y[gi][11:1];
            assign b_kind_v[2*gi +: 2]  = b_kind[gi];
        end
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_booms
            assign bm_on_v[gi]          = (bm_t[gi] != 0);
            assign bm_x_v[11*gi +: 11]  = bm_x[gi];
            assign bm_y_v[11*gi +: 11]  = bm_y[gi];
            assign bm_fr_v[gi]          = (bm_t[gi] <= 5'd12);
        end
    endgenerate
    assign e_on_v   = e_on;
    assign e_face_v = e_face;
    assign b_on_v   = b_on;

    //-------------------------------------------------------------------------
    // helpers (combinational)
    //-------------------------------------------------------------------------
    wire [4:0]  hbw  = f_hbw(form);
    wire [3:0]  bh   = f_bh(form);
    wire [4:0]  hx   = f_hx(form);
    wire [4:0]  hy   = f_hy(form);
    wire [10:0] pcy  = py - {6'b0, f_size(form)} / 2;        // centre of the body
    wire        low  = (z < 10'sd32);                        // under 4 px: enemies can touch us

    // next position for one 1-px step
    wire [10:0] nx_w = axis_y ? px : (dir_xp ? px + 11'd1 : px - 11'd1);
    wire [10:0] ny_w = axis_y ? (dir_yp ? py + 11'd1 : py - 11'd1) : py;
    wire        in_map = (nx_w >= f_x0(form)) && (nx_w <= f_x1(form)) &&
                         (ny_w >= f_y0(form)) && (ny_w <= MAP_Y1);

    // the tile being touched
    wire [3:0]  t        = ram_dout;
    wire        is_tower = (t >= T_TWR_TL) && (t <= T_TWR_BR);
    wire        solid    = (form == 0) ? (t == T_CAR || t == T_HOUSE || is_tower || t == T_WATER) :
                           (form == 1) ? (is_tower || t == T_WATER) : 1'b0;
    wire        in_old   = (lx[6:0] >= ox0) && (lx[6:0] <= ox1) && (ly[6:0] >= oy0) && (ly[6:0] <= oy1);
    wire        out_map  = (lx < 0) || (lx > 9'sd127) || (ly < 0) || (ly > 9'sd95);
    wire        corner   = mode && (lx == lx0 || lx == lx1) && (ly == ly0 || ly == ly1);
    wire [13:0] l_addr   = {ly[6:0], lx[6:0]};

    // jump: z += vz, then vz -= 2 (gravity)
    wire        jump_go  = jump_req && (z == 0) && (vz == 0);
    wire signed [7:0] vz_n = jump_go ? $signed(f_jump(form)) : vz;
    wire signed [9:0] z_n  = z + vz_n;
    wire        in_air   = (z > 0) || (vz_n > 0);

    // stomp centre
    wire [6:0]  st_cx = px[10:4];
    wire [10:0] py_m5 = py - 11'd5;
    wire [6:0]  st_cy = py_m5[10:4];

    //---------------- the enemy being updated (slot ei)
    wire [1:0]  et   = e_type[ei];
    wire [10:0] ex   = e_x[ei];
    wire [10:0] ey   = e_y[ei];
    wire signed [12:0] edx = $signed({2'b0, px})  - $signed({2'b0, ex});   // kaiju - enemy
    wire signed [12:0] edy = $signed({2'b0, pcy}) - $signed({2'b0, ey});
    wire [12:0] eadx = edx[12] ? -edx : edx;
    wire [12:0] eady = edy[12] ? -edy : edy;
    wire [13:0] edist = eadx + eady;
    wire [4:0]  ehw  = (et == E_NUKE) ? 5'd12 : 5'd6;
    wire        e_touch = low && (et != E_HELI) && (eadx < hx + ehw) && (eady < hy + 5'd6);
    wire        e_move_en = (et == E_POLICE) ? 1'b1 : (et == E_TANK) ? !frame_cnt[0] : (frame_cnt[1:0] != 2'd0);
    wire        e_hold  = (et != E_NUKE) && (edist <= {6'b0, e_keep(et)}) && (e_wt[ei] == 0);
    // first move: the axis with the larger distance; wander: the stored direction
    wire        e_xfirst = (eadx >= eady);
    wire [1:0]  e_d1 = (e_wt[ei] != 0) ? e_wdir[ei] :
                       e_xfirst ? (edx[12] ? 2'd1 : 2'd0) : (edy[12] ? 2'd3 : 2'd2);
    wire [1:0]  e_d2 = e_xfirst ? (edy[12] ? 2'd3 : 2'd2) : (edx[12] ? 2'd1 : 2'd0);
    wire        e_d2_ok = (e_wt[ei] == 0) && (e_xfirst ? (eady != 0) : (eadx != 0));
    wire [1:0]  e_dm = e_try ? e_d2 : e_d1;
    wire [10:0] e_cx = (e_dm == 2'd0) ? ex + 11'd1 : (e_dm == 2'd1) ? ex - 11'd1 : ex;
    wire [10:0] e_cy = (e_dm == 2'd2) ? ey + 11'd1 : (e_dm == 2'd3) ? ey - 11'd1 : ey;
    wire        e_cin = (e_cx >= 11'd16) && (e_cx <= 11'd2031) && (e_cy >= 11'd16) && (e_cy <= 11'd1519);
    // aim: 8 directions toward the kaiju
    wire signed [1:0] aim_x = (eady > {eadx, 1'b0}) ? 2'sd0 : (edx[12] ? -2'sd1 : 2'sd1);
    wire signed [1:0] aim_y = (eadx > {eady, 1'b0}) ? 2'sd0 : (edy[12] ? -2'sd1 : 2'sd1);
    wire [2:0]  aim_dir = (aim_x == 1  && aim_y == 0)  ? 3'd0 : (aim_x == 1  && aim_y == 1)  ? 3'd1 :
                          (aim_x == 0  && aim_y == 1)  ? 3'd2 : (aim_x == -1 && aim_y == 1)  ? 3'd3 :
                          (aim_x == -1 && aim_y == 0)  ? 3'd4 : (aim_x == -1 && aim_y == -1) ? 3'd5 :
                          (aim_x == 0  && aim_y == -1) ? 3'd6 : 3'd7;

    // free slots
    integer j;
    initial begin                            // power-up values (the FPGA loads them too)
        for (j = 0; j < 8; j = j + 1) begin
            e_type[j] = 0; e_x[j] = 0; e_y[j] = 0; e_cd[j] = 0; e_stun[j] = 0; e_wdir[j] = 0; e_wt[j] = 0;
            b_x[j] = 0; b_y[j] = 0; b_dir[j] = 0; b_kind[j] = 0; b_t[j] = 0;
        end
        for (j = 0; j < 4; j = j + 1) begin bm_x[j] = 0; bm_y[j] = 0; bm_t[j] = 0; end
    end

    reg [2:0] free_b;  reg has_free_b;
    reg [2:0] free_e;  reg has_free_e;
    reg [3:0] e_count;
    integer k;
    always @(*) begin
        free_b = 0; has_free_b = 0; free_e = 0; has_free_e = 0; e_count = 0;
        for (k = 7; k >= 0; k = k - 1) begin
            if (!b_on[k]) begin free_b = k; has_free_b = 1; end
            if (!e_on[k]) begin free_e = k; has_free_e = 1; end
            e_count = e_count + e_on[k];
        end
    end

    //---------------- the bullet being updated (slot bi): speed in half pixels per frame
    wire [2:0]  bspd = (b_kind[bi] == 0) ? 3'd4 : 3'd3;
    wire signed [13:0] nbx = $signed({2'b0, b_x[bi]}) + dir_x(b_dir[bi]) * $signed({1'b0, bspd});
    wire signed [13:0] nby = $signed({2'b0, b_y[bi]}) + dir_y(b_dir[bi]) * $signed({1'b0, bspd});
    wire        b_out  = (nbx < 0) || (nbx > 14'sd4095) || (nby < 0) || (nby > 14'sd3071);
    wire [10:0] bpx = nbx[11:1], bpy = nby[11:1];
    wire signed [12:0] bdx = $signed({2'b0, bpx}) - $signed({2'b0, px});
    wire signed [12:0] bdy = $signed({2'b0, bpy}) - $signed({2'b0, pcy});
    wire [12:0] badx = bdx[12] ? -bdx : bdx;
    wire [12:0] bady = bdy[12] ? -bdy : bdy;
    wire        b_hit = low && (badx < hx) && (bady < hy);
    wire        b_near_roar = roar_now && (badx + bady < 13'd128);

    //---------------- spawn candidate (from the LFSR), around the kaiju just off the screen
    wire [7:0]  rr = lfsr[9:2];
    wire signed [12:0] spx = (lfsr[1:0] == 0) ? $signed({2'b0, px}) - 13'sd200 :
                             (lfsr[1:0] == 1) ? $signed({2'b0, px}) + 13'sd200 :
                                                $signed({2'b0, px}) - 13'sd128 + $signed({5'b0, rr});
    wire signed [12:0] spy = (lfsr[1:0] == 2) ? $signed({2'b0, pcy}) - 13'sd150 :
                             (lfsr[1:0] == 3) ? $signed({2'b0, pcy}) + 13'sd150 :
                                                $signed({2'b0, pcy}) - 13'sd128 + $signed({5'b0, rr});
    wire        sp_in = (spx >= 13'sd16) && (spx <= 13'sd2031) && (spy >= 13'sd16) && (spy <= 13'sd1519);
    wire [1:0]  sp_t  = (form == 0) ? E_POLICE :
                        (form == 1) ? (lfsr[10] ? E_TANK : E_POLICE) :
                        (lfsr[12:10] <= 3'd1) ? E_POLICE : (lfsr[12:10] <= 3'd4) ? E_TANK :
                        (lfsr[12:10] <= 3'd6) ? E_HELI : E_NUKE;

    //---------------- item candidate tile near the kaiju
    wire signed [8:0] itx_s = $signed({2'b0, px[10:4]})  + $signed({5'b0, lfsr[3:0]}) - 9'sd8;
    wire signed [8:0] ity_s = $signed({2'b0, pcy[10:4]}) + $signed({5'b0, lfsr[7:4]}) - 9'sd8;
    wire        it_in = (itx_s >= 9'sd1) && (itx_s <= 9'sd126) && (ity_s >= 9'sd1) && (ity_s <= 9'sd94);
    wire signed [12:0] idx_ = $signed({2'b0, it_x}) - $signed({2'b0, px});
    wire signed [12:0] idy_ = $signed({2'b0, it_y}) - $signed({2'b0, pcy});
    wire [12:0] iadx = idx_[12] ? -idx_ : idx_;
    wire [12:0] iady = idy_[12] ? -idy_ : idy_;
    wire        it_touch = it_on && (iadx < hx + 5'd7) && (iady < hy + 5'd7);

    //-------------------------------------------------------------------------
    // picture numbers (used in S_CAM)
    //-------------------------------------------------------------------------
    wire [1:0]  dform = (gstate == G_EVOLVE && evo_t[3]) ? form + 2'd1 : form;  // evolving: old / new form in turns
    wire [5:0]  dsize = f_size(dform);
    wire [6:0]  zpx   = (z + 10'sd4) >>> 3;                                    // height in px, rounded
    wire signed [12:0] jx = shake == 0 ? 13'sd0 : (lfsr[2:0] == 0 ? -13'sd2 : lfsr[2:0] == 1 ? -13'sd1 :
                                                  lfsr[2:0] == 2 ? 13'sd1 : lfsr[2:0] == 3 ? 13'sd2 : 13'sd0);
    wire signed [12:0] jy = shake == 0 ? 13'sd0 : (lfsr[5:3] == 0 ? -13'sd2 : lfsr[5:3] == 1 ? -13'sd1 :
                                                  lfsr[5:3] == 2 ? 13'sd1 : lfsr[5:3] == 3 ? 13'sd2 : 13'sd0);
    // camera: player in the middle, but the screen stays on the map (2048 - 320, 1536 - 240)
    wire signed [12:0] cxs = $signed({2'b0, px}) - 13'sd160 + jx;
    wire signed [12:0] cys = $signed({2'b0, py}) - $signed({7'b0, f_size(form)} >>> 1) - 13'sd120 + jy;
    wire [10:0] cam_x_n = cxs < 0 ? 11'd0 : cxs > 13'sd1728 ? 11'd1728 : cxs[10:0];
    wire [10:0] cam_y_n = cys < 0 ? 11'd0 : cys > 13'sd1296 ? 11'd1296 : cys[10:0];

    // LED bar: progress to the NEXT goal (trees -> score -> city destroyed), 16 LEDs = done
    wire [9:0]  lv_t = trees * 10'd13;            // trees * 16 / 20
    wire [23:0] lv_s = score * 24'd700;           // score * 16 / 1500  (>> 16)
    wire [23:0] lv_d = destroyed * 24'd1748;      // destroyed * 16 / 600  (>> 16)
    wire [7:0]  level = (form == 0) ? {3'b0, lv_t[9:4]} : (form == 1) ? lv_s[23:16] : lv_d[23:16];
    wire [15:0] bar   = (level >= 16) ? 16'hFFFF : ((16'h1 << level[3:0]) - 16'h1);

    //-------------------------------------------------------------------------
    // small jobs used by several states
    //-------------------------------------------------------------------------
    task hurt;                                  // damage the kaiju (shield and "can't be hurt" first)
        input [1:0] d;
        begin
            if (inv == 0) begin
                sfx <= SFX_HIT;
                if (shake < 8) shake <= 5'd8;
                if (shield) begin
                    shield <= 1'b0;  shield_t <= 0;  inv <= 7'd60;
                end else begin
                    hp  <= (hp > {2'b0, d}) ? hp - d : 4'd0;
                    inv <= 7'd90;
                end
            end
        end
    endtask

    task boom;                                  // start an explosion (the oldest one is reused)
        input [10:0] bx, by;
        begin
            bm_x[bm_next] <= bx;  bm_y[bm_next] <= by;  bm_t[bm_next] <= 5'd24;
            bm_next <= bm_next + 1'b1;
        end
    endtask

    //-------------------------------------------------------------------------
    // the state machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        ram_we <= 1'b0;                          // a write lasts one clock
        sfx    <= 9'b0;                          // sound pulses last one clock
        if (roar_req) roar_pend <= 1'b1;         // remembered until the next frame

        if (rst) begin
            st     <= S_COPY;
            copy_i <= 0;
            cv_d   <= 1'b0;
        end else case (st)

        //---------------- reset / new game: copy the map ROM into the tile RAM (12,288 clocks)
        S_COPY: begin
            copy_i <= copy_i + 1'b1;
            ci_d   <= copy_i[13:0];
            cv_d   <= (copy_i < MAP_TILES);
            if (cv_d) begin
                ram_addr <= ci_d;
                ram_din  <= rom_dout;
                ram_we   <= 1'b1;
            end
            if (copy_i == MAP_TILES) st <= S_INIT;
        end

        S_INIT: begin
            px <= START_X;  py <= START_Y;  face_r <= 1'b0;  acc <= 1'b0;
            form <= 0;  gstate <= G_TITLE;  score <= 0;  trees <= 0;  destroyed <= 0;
            time_s <= TIME_S;  sec_div <= 0;  z <= 0;  vz <= 0;  c_prev <= 1'b1;
            shake <= 0;  stomp_cd <= 0;  roar_t <= 0;  evo_t <= 0;
            walk_t <= 0;  walk_phase <= 0;  steps_left <= 0;
            hp <= 4'd3;  inv <= 0;  shield <= 0;  shield_t <= 0;  speed_t <= 0;
            roar_cd <= 0;  roar_now <= 0;  stomp_now <= 0;
            e_on <= 0;  b_on <= 0;  it_on <= 0;  it_spawn <= 10'd600;  spawn_t <= 8'd180;
            for (j = 0; j < 4; j = j + 1) bm_t[j] <= 0;
            st <= S_IDLE;
        end

        S_IDLE: if (tick) st <= S_FRAME;

        //---------------- start of a frame
        S_FRAME: begin
            frame_cnt <= frame_cnt + 1'b1;
            if (shake    != 0) shake    <= shake - 1'b1;
            if (stomp_cd != 0) stomp_cd <= stomp_cd - 1'b1;
            if (roar_t   != 0) roar_t   <= roar_t - 1'b1;
            for (j = 0; j < 4; j = j + 1) if (bm_t[j] != 0) bm_t[j] <= bm_t[j] - 1'b1;
            jump_req  <= btn[4] & ~c_prev;       // BTNC pressed since the last frame
            c_prev    <= btn[4];
            roar_now  <= 1'b0;
            stomp_now <= 1'b0;
            roar_pend <= 1'b0;

            if (gstate == G_PLAY || gstate == G_EVOLVE) begin   // 1 second = 60 frames
                if (sec_div == 6'd59) begin
                    sec_div <= 0;
                    if (time_s != 0) time_s <= time_s - 1'b1;
                end else
                    sec_div <= sec_div + 1'b1;
            end

            case (gstate)
            G_TITLE: begin                       // pan the city; BTNC starts the game
                if (title_dir == 0) begin
                    if (title_x >= 11'd1728) title_dir <= 1'b1; else title_x <= title_x + 1'b1;
                end else begin
                    if (title_x == 0) title_dir <= 1'b0; else title_x <= title_x - 1'b1;
                end
                if (btn[4] & ~c_prev) begin
                    gstate <= G_PLAY;
                    sfx <= SFX_FANFARE;
                end
                st <= S_CAM;
            end
            G_WIN, G_OVER: begin                 // BTNC: rebuild the city, back to the title
                if (btn[4] & ~c_prev) begin
                    copy_i <= 0;  cv_d <= 1'b0;
                    st <= S_COPY;
                end else
                    st <= S_CAM;
            end
            G_EVOLVE: begin                      // 96 frames of flashing, then the new form
                evo_t <= evo_t - 1'b1;
                if (evo_t == 1) begin
                    form   <= form + 1'b1;
                    hp     <= f_hp(form + 1'b1);
                    gstate <= G_PLAY;
                    shake  <= 5'd18;
                end
                st <= S_END;
            end
            G_PLAY: begin
                if (inv      != 0) inv      <= inv - 1'b1;
                if (speed_t  != 0) speed_t  <= speed_t - 1'b1;
                if (roar_cd  != 0) roar_cd  <= roar_cd - 1'b1;
                if (shield_t != 0) begin
                    shield_t <= shield_t - 1'b1;
                    if (shield_t == 1) shield <= 1'b0;
                end
                // Feature 3.7: a shout (from the microphone) while the roar is ready
                if (!DEMO && roar_pend && roar_cd == 0) begin
                    roar_now <= 1'b1;  roar_cd <= 9'd300;  roar_t <= 5'd26;  shake <= 5'd16;
                    sfx <= SFX_ROAR;
                end

                if (dbg != 0 && form != dbg - 1'b1) begin          // debug switches force a form
                    form <= dbg - 1'b1;  hp <= f_hp(dbg - 1'b1);  z <= 0;  vz <= 0;  shake <= 5'd8;
                    clamp_form <= dbg - 1'b1;
                    st <= S_CLAMP;
                end else begin
                    // buttons {C, U, D, L, R}; both of a pair held = no move on that axis
                    movx   <= btn[1] ^ btn[0];   dir_xp <= btn[0];
                    movy   <= btn[3] ^ btn[2];   dir_yp <= btn[2];
                    if (btn[1] ^ btn[0]) face_r <= btn[0];
                    if ((btn[1] ^ btn[0]) || (btn[3] ^ btn[2])) begin
                        // speed in half pixels: 4 / 3 / 2 (+2 with the speed item)
                        {steps_left, acc} <= {2'b0, acc} + f_speed(form) + ((speed_t != 0) ? 3'd2 : 3'd0);
                        walk_t <= walk_t + 1'b1;
                        if (walk_t == 3'd7) walk_phase <= walk_phase + 1'b1;
                    end else begin
                        steps_left <= 0;  acc <= 1'b0;  walk_t <= 0;  walk_phase <= 0;
                    end
                    sub <= 1'b0;
                    st  <= S_STEP;
                end
            end
            default: st <= S_CAM;
            endcase
        end

        //---------------- walking: each 1-px step is x first, then y
        S_STEP: begin
            if (steps_left == 0)
                st <= S_JUMP;
            else if (!sub) begin
                sub <= 1'b1;
                if (movx) begin axis_y <= 1'b0; st <= S_AX; end
            end else begin
                sub <= 1'b0;
                steps_left <= steps_left - 1'b1;
                if (movy) begin axis_y <= 1'b1; st <= S_AX; end
            end
        end

        S_AX: begin
            if (!in_map)
                st <= S_STEP;                    // screen boundary: no step
            else begin
                nx <= nx_w;  ny <= ny_w;  ok <= 1'b1;  mode <= 1'b0;
                lx0 <= (nx_w - hbw) >> 4;          lx <= (nx_w - hbw) >> 4;
                lx1 <= (nx_w + hbw - 1'b1) >> 4;
                ly0 <= (ny_w - bh) >> 4;           ly <= (ny_w - bh) >> 4;
                ly1 <= (ny_w - 1'b1) >> 4;
                ox0 <= (px - hbw) >> 4;            ox1 <= (px + hbw - 1'b1) >> 4;
                oy0 <= (py - bh) >> 4;             oy1 <= (py - 1'b1) >> 4;
                st  <= S_T_RD;
            end
        end

        //---------------- touch every tile in the box: eat, smash or bump
        S_T_RD: begin
            if (out_map || corner)
                st <= S_T_NEXT;
            else begin
                ram_addr <= l_addr;
                st <= S_T_WAIT;
            end
        end

        S_T_WAIT: st <= S_T_USE;

        S_T_USE: begin
            st <= S_T_NEXT;
            if (t == T_TREE) begin                                    // eat a tree (every form)
                ram_din <= T_GRASS;  ram_we <= 1'b1;  sfx <= SFX_EAT;
                score <= add_pts(score, P_TREE);
                if (form == 0 && trees != 5'd31) trees <= trees + 1'b1;
            end else if (t == T_CAR && form != 0) begin               // eat a car (teen, full kaiju)
                ram_din <= T_ROAD_H;  ram_we <= 1'b1;  sfx <= SFX_EAT;
                score <= add_pts(score, P_CAR);
            end else if (t == T_HOUSE && form != 0) begin             // smash a house -> fire
                ram_din <= T_FIRE;  ram_we <= 1'b1;  sfx <= SFX_SMASH;
                score <= add_pts(score, P_HOUSE);
                destroyed <= destroyed + 12'd1;
                if (shake < 4) shake <= 5'd4;
            end else if (is_tower && form == 2) begin                 // smash a 2x2 tower (full kaiju)
                tox <= lx[6:0] - ((t == T_TWR_TR || t == T_TWR_BR) ? 7'd1 : 7'd0);
                toy <= ly[6:0] - ((t == T_TWR_BL || t == T_TWR_BR) ? 7'd1 : 7'd0);
                score <= add_pts(score, P_TOWER);  sfx <= SFX_SMASH;
                destroyed <= destroyed + 12'd4;
                if (shake < 10) shake <= 5'd10;
                st <= S_TW0;
            end else if (!mode && solid && !in_old)
                ok <= 1'b0;                                           // bump: the step is blocked
        end

        // tower -> rubble on one diagonal, fire on the other (one write per clock)
        S_TW0: begin ram_addr <= {toy,        tox};        ram_din <= T_RUBBLE; ram_we <= 1'b1; st <= S_TW1; end
        S_TW1: begin ram_addr <= {toy + 7'd1, tox + 7'd1}; ram_din <= T_RUBBLE; ram_we <= 1'b1; st <= S_TW2; end
        S_TW2: begin ram_addr <= {toy,        tox + 7'd1}; ram_din <= T_FIRE;   ram_we <= 1'b1; st <= S_TW3; end
        S_TW3: begin ram_addr <= {toy + 7'd1, tox};        ram_din <= T_FIRE;   ram_we <= 1'b1; st <= S_T_NEXT; end

        S_T_NEXT: begin
            if (lx != lx1) begin
                lx <= lx + 1'b1;  st <= S_T_RD;
            end else if (ly != ly1) begin
                lx <= lx0;  ly <= ly + 1'b1;  st <= S_T_RD;
            end else if (!mode) begin
                if (ok) begin px <= nx; py <= ny; end
                st <= S_STEP;
            end else
                st <= S_EVO;                     // stomp finished
        end

        //---------------- jump and gravity (BTNC)
        S_JUMP: begin
            st <= S_EVO;
            if (jump_go) sfx <= SFX_JUMP;
            if (in_air) begin
                if (z_n <= 0) begin              // landed
                    z <= 0;  vz <= 0;
                    st <= S_LAND;
                end else begin
                    z  <= z_n;
                    vz <= vz_n - 8'sd2;
                end
            end
        end

        S_LAND: begin
            if (form == 2 && stomp_cd == 0) begin                     // full kaiju stomp: radius ~2 tiles
                lx0 <= $signed({2'b0, st_cx}) - 9'sd2;  lx1 <= $signed({2'b0, st_cx}) + 9'sd2;
                ly0 <= $signed({2'b0, st_cy}) - 9'sd2;  ly1 <= $signed({2'b0, st_cy}) + 9'sd2;
                lx  <= $signed({2'b0, st_cx}) - 9'sd2;  ly  <= $signed({2'b0, st_cy}) - 9'sd2;
                mode <= 1'b1;  stomp_now <= 1'b1;        // enemies near the stomp blow up too
                shake <= 5'd24;  stomp_cd <= 6'd40;  roar_t <= 5'd26;  sfx <= SFX_STOMP;
                st <= S_T_RD;
            end else begin
                if (form == 1 && shake < 5) shake <= 5'd5;
                st <= S_EVO;
            end
        end

        //---------------- evolution
        S_EVO: begin
            if (dbg == 0 && ((form == 0 && trees >= EVO_TREES) || (form == 1 && score >= EVO_SCORE && !DEMO))) begin
                gstate <= G_EVOLVE;  evo_t <= 7'd96;  z <= 0;  vz <= 0;  sfx <= SFX_FANFARE;
                clamp_form <= form + 1'b1;       // the bigger sprite must fit on the map too
                st <= S_CLAMP;
            end else
                st <= DEMO ? S_END : S_ITEM;     // the demo has no units
        end

        S_CLAMP: begin
            px <= (px < f_x0(clamp_form)) ? f_x0(clamp_form) : (px > f_x1(clamp_form)) ? f_x1(clamp_form) : px;
            py <= (py < f_y0(clamp_form)) ? f_y0(clamp_form) : py;
            st <= (gstate == G_PLAY && !DEMO) ? S_ITEM : S_END;
        end

        //---------------- Feature 3.5: one power-up on the map at a time
        S_ITEM: begin
            ei <= 0;  e_try <= 1'b0;
            st <= S_E_START;
            if (it_on) begin
                it_hide <= (it_t < 10'd180) && frame_cnt[2];
                if (it_touch) begin                                   // picked up
                    it_on <= 1'b0;  it_spawn <= 10'd900;  sfx <= SFX_PICKUP;
                    case (it_type)
                        2'd0:    hp <= (hp < f_hp(form)) ? hp + 1'b1 : hp;      // heal
                        2'd1:    speed_t  <= 10'd600;                           // faster for 10 s
                        default: begin shield <= 1'b1; shield_t <= 10'd600; end // one free hit
                    endcase
                end else if (it_t <= 1) begin                         // nobody took it
                    it_on <= 1'b0;  it_spawn <= 10'd900;
                end else
                    it_t <= it_t - 1'b1;
            end else if (it_spawn != 0)
                it_spawn <= it_spawn - 1'b1;
            else if (it_in) begin                                     // try a tile near the kaiju
                it_tx <= itx_s[6:0];  it_ty <= ity_s[6:0];
                it_type <= (lfsr[9:8] == 2'd3) ? 2'd0 : lfsr[9:8];
                ram_addr <= {ity_s[6:0], itx_s[6:0]};
                st <= S_IT_WAIT;
            end
        end
        S_IT_WAIT: st <= S_IT_USE;
        S_IT_USE: begin
            if (i_pass(ram_dout)) begin
                it_on <= 1'b1;  it_t <= 10'd600;  it_hide <= 1'b0;
                it_x <= {it_tx, 4'd8};  it_y <= {it_ty, 4'd8};
            end
            st <= S_E_START;
        end

        //---------------- Feature 3.4: enemies, one slot after the other
        S_E_START: begin
            e_try <= 1'b0;
            if (!e_on[ei])
                st <= S_E_NEXT;
            else if (edist > 14'd520) begin                           // too far away: gone
                e_on[ei] <= 1'b0;  st <= S_E_NEXT;
            end else if (stomp_now && edist < 14'd80) begin           // stomped
                e_on[ei] <= 1'b0;  boom(ex, ey);
                score <= add_pts(score, (et >= E_HELI) ? P_BIG : P_UNIT);
                st <= S_E_NEXT;
            end else if (e_touch) begin                               // touches the kaiju
                e_on[ei] <= 1'b0;  boom(ex, ey);
                if (et == E_NUKE)
                    hurt(2'd2);                                       // the nuke truck blows up
                else if (form == 0)
                    hurt(2'd1);                                       // too small: it rams us
                else begin
                    score <= add_pts(score, P_UNIT);  sfx <= SFX_EAT; // big enough: eaten
                end
                st <= S_E_NEXT;
            end else begin
                if (roar_now && edist < 14'd128) e_stun[ei] <= 7'd120;   // the roar stuns it
                if (e_stun[ei] != 0) begin
                    e_stun[ei] <= e_stun[ei] - 1'b1;
                    st <= S_E_NEXT;
                end else
                    st <= S_E_MOVE;
            end
        end

        S_E_MOVE: begin
            if (e_wt[ei] != 0) e_wt[ei] <= e_wt[ei] - 1'b1;
            if (!e_move_en || e_hold)
                st <= S_E_FIRE;                                       // stay: too close, or slow
            else if (et == E_HELI) begin                              // flies over everything
                if (edx != 0) begin e_x[ei] <= edx[12] ? ex - 11'd1 : ex + 11'd1; e_face[ei] <= !edx[12]; end
                if (edy != 0) e_y[ei] <= edy[12] ? ey - 11'd1 : ey + 11'd1;
                st <= S_E_FIRE;
            end else if (!e_cin)
                st <= S_E_FIRE;
            else begin                                                // drives: check the tile ahead
                cx <= e_cx;  cy <= e_cy;
                ram_addr <= {e_cy[10:4], e_cx[10:4]};
                st <= S_E_WAIT;
            end
        end
        S_E_WAIT: st <= S_E_USE;
        S_E_USE: begin
            if (v_pass(ram_dout)) begin
                if (cx != ex) e_face[ei] <= (cx > ex);
                e_x[ei] <= cx;  e_y[ei] <= cy;
                st <= S_E_FIRE;
            end else if (!e_try && e_d2_ok) begin                     // try the other axis
                e_try <= 1'b1;
                st <= S_E_MOVE;
            end else begin                                            // stuck: drive a random way
                e_wdir[ei] <= lfsr[1:0];  e_wt[ei] <= 5'd20;
                st <= S_E_FIRE;
            end
        end

        S_E_FIRE: begin
            st <= S_E_NEXT;
            if (et != E_NUKE) begin
                if (e_cd[ei] != 0)
                    e_cd[ei] <= e_cd[ei] - 1'b1;
                else if (edist < 14'd200) begin
                    e_cd[ei] <= e_cdbase(et) + {2'b0, lfsr[5:0]};
                    shots <= (et == E_HELI) ? 2'd3 : 2'd1;   shot_k <= 0;   shot_dir <= aim_dir;
                    st <= S_E_SHOT;
                end
            end
        end

        S_E_SHOT: begin                                               // helicopter: 3 bullets in a fan
            if (shots == 0 || !has_free_b)
                st <= S_E_NEXT;
            else begin
                b_on[free_b]   <= 1'b1;
                b_x[free_b]    <= {ex, 1'b0};
                b_y[free_b]    <= {ey, 1'b0};
                b_dir[free_b]  <= (shot_k == 1) ? shot_dir + 3'd1 : (shot_k == 2) ? shot_dir - 3'd1 : shot_dir;
                b_kind[free_b] <= et;
                b_t[free_b]    <= 7'd110;
                shots  <= shots - 1'b1;
                shot_k <= shot_k + 1'b1;
            end
        end

        S_E_NEXT: begin
            ei <= ei + 1'b1;
            if (ei == 3'd7) begin bi <= 0; st <= S_B_START; end
            else st <= S_E_START;
        end

        //---------------- bullets: fly, hit the kaiju, stop at buildings
        S_B_START: begin
            if (!b_on[bi])
                st <= S_B_NEXT;
            else begin
                b_x[bi] <= nbx[11:0];  b_y[bi] <= nby[11:0];
                b_t[bi] <= b_t[bi] - 1'b1;
                if (b_out || b_t[bi] <= 1 || b_near_roar) begin
                    b_on[bi] <= 1'b0;  st <= S_B_NEXT;
                end else if (b_hit) begin
                    b_on[bi] <= 1'b0;  boom(bpx, bpy);
                    hurt((b_kind[bi] == E_TANK) ? 2'd2 : 2'd1);
                    st <= S_B_NEXT;
                end else begin
                    ram_addr <= {bpy[10:4], bpx[10:4]};
                    st <= S_B_WAIT;
                end
            end
        end
        S_B_WAIT: st <= S_B_USE;
        S_B_USE: begin
            if (b_block(ram_dout)) b_on[bi] <= 1'b0;
            st <= S_B_NEXT;
        end
        S_B_NEXT: begin
            bi <= bi + 1'b1;
            st <= (bi == 3'd7) ? S_SP_START : S_B_START;
        end

        //---------------- spawn a new enemy now and then (more and stronger for bigger forms)
        S_SP_START: begin
            st <= S_END;
            if (spawn_t != 0)
                spawn_t <= spawn_t - 1'b1;
            else if (has_free_e && e_count < f_cap(form) && sp_in) begin
                sp_x <= spx[10:0];  sp_y <= spy[10:0];  sp_type <= sp_t;
                if (sp_t == E_HELI) begin                             // no need to check the ground
                    e_on[free_e] <= 1'b1;  e_type[free_e] <= E_HELI;
                    e_x[free_e] <= spx[10:0];  e_y[free_e] <= spy[10:0];
                    e_face[free_e] <= (spx[10:0] < px);  e_cd[free_e] <= 8'd90;
                    e_stun[free_e] <= 0;  e_wt[free_e] <= 0;
                    spawn_t <= f_every(form);
                end else begin
                    ram_addr <= {spy[10:4], spx[10:4]};
                    st <= S_SP_WAIT;
                end
            end
        end
        S_SP_WAIT: st <= S_SP_USE;
        S_SP_USE: begin
            if (v_pass(ram_dout)) begin                               // on a road: place it
                e_on[free_e] <= 1'b1;  e_type[free_e] <= sp_type;
                e_x[free_e] <= sp_x;  e_y[free_e] <= sp_y;
                e_face[free_e] <= (sp_x < px);  e_cd[free_e] <= 8'd90;
                e_stun[free_e] <= 0;  e_wt[free_e] <= 0;
                spawn_t <= f_every(form);
            end                                                       // else: try again next frame
            st <= S_END;
        end

        //---------------- win / lose
        S_END: begin
            if (gstate == G_PLAY || gstate == G_EVOLVE) begin
                if (destroyed >= GOAL || score >= 14'd9999) begin gstate <= G_WIN;  sfx <= SFX_FANFARE; end   // city cleared or max score
                else if (hp == 0 || time_s == 0) begin gstate <= G_OVER; sfx <= SFX_OVER;    end
            end
            st <= S_CAM;
        end

        //---------------- numbers for the picture and the LEDs
        S_CAM: begin
            cam_x <= cam_x_n;
            cam_y <= cam_y_n;
            ov_on    <= (gstate != G_PLAY);
            ov_page  <= (gstate == G_TITLE) ? 3'd0 : (gstate == G_WIN) ? 3'd1 :
                        (gstate == G_OVER)  ? ((hp == 0) ? 3'd5 : 3'd2) :
                        (form == 0) ? 3'd3 : 3'd4;
            ov_blink <= frame_cnt[5];
            spr_form   <= dform;
            spr_mirror <= face_r;
            spr_flash  <= (gstate == G_EVOLVE) && (evo_t[2:0] < 3'd2);
            spr_frame  <= (gstate == G_EVOLVE)            ? 2'd0 :
                          (form == 2 && roar_t != 0)      ? 2'd3 :
                          (z > 0)                         ? 2'd1 :
                          (walk_phase == 1)               ? 2'd1 :
                          (walk_phase == 3)               ? 2'd2 : 2'd0;
            spr_x <= px - {5'b0, dsize[5:1]};
            spr_y <= py - {5'b0, dsize} + 11'd1 - {4'b0, zpx};
            spr_show   <= !(inv != 0 && frame_cnt[2]);
            spr_shield <= shield;
            shd_on <= (z > 0) && (gstate == G_PLAY);
            shd_x  <= px;
            shd_y  <= py - f_rh(form) + 11'd1;
            fire_phase <= frame_cnt[3];
            dark     <= (gstate == G_TITLE) || (gstate == G_WIN) || (gstate == G_OVER);
            dark_spr <= (gstate == G_WIN) || (gstate == G_OVER);
            if (gstate == G_TITLE) begin         // title: big kaiju roaring in the middle of the screen
                cam_x      <= title_x;
                cam_y      <= TITLE_CAM_Y;
                spr_form   <= 2'd2;
                spr_frame  <= frame_cnt[6] ? 2'd3 : 2'd0;
                spr_mirror <= 1'b0;
                spr_flash  <= 1'b0;
                spr_show   <= 1'b1;
                spr_shield <= 1'b0;
                spr_x      <= title_x + 11'd136;
                spr_y      <= TITLE_CAM_Y + 11'd113;
                shd_on     <= 1'b0;
            end
            led_bar <= bar;
            scan_i  <= 0;
            st <= S_SC_RD;
        end

        //---------------- fire scanner: every FIRE tile becomes RUBBLE with chance 1/256
        // per frame (about 4 s).  3 clocks per tile = 36,864 clocks, done long before
        // the next frame (420,000 clocks).
        S_SC_RD:   begin ram_addr <= scan_i; st <= S_SC_WAIT; end
        S_SC_WAIT: st <= S_SC_USE;
        S_SC_USE: begin
            if (ram_dout == T_FIRE && lfsr[7:0] == 8'd0) begin
                ram_din <= T_RUBBLE;  ram_we <= 1'b1;            // ram_addr is still scan_i
            end
            if (scan_i == MAP_TILES - 1)
                st <= S_IDLE;
            else begin
                scan_i <= scan_i + 1'b1;
                st <= S_SC_RD;
            end
        end

        default: st <= S_IDLE;
        endcase
    end
endmodule
