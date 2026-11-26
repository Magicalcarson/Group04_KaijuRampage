`timescale 1ns / 1ps
//=============================================================================
// Kaiju Rampage : picture
//
// The game picture is 320 x 240, every game pixel is 2 x 2 screen pixels.
// Screen pixel (x, y) shows map point (cam_x + x/2, cam_y + y/2).
//
// The map is NOT stored as a picture.  It is 128 x 96 tile numbers (tile RAM)
// and 16 small 16 x 16 pictures (tile ROM).  Colour numbers are 4 bits, and one
// 16-colour palette turns them into 12-bit VGA colours.
//
// Layers, top first:  text page > explosions > bullets > helicopters > player
//                     > other enemies > power-up item > shadow > city tiles
// Each kind of sprite has its own ROM.  For enemies / explosions the first slot
// that covers the pixel is used (one ROM read per kind and pixel).
//
// The colour is ready 4 clocks after (x, y):
//   clock 1 : map point (wx, wy)
//   clock 2 : tile RAM gives the tile number, sprite ROMs give colour numbers,
//             bullets / shadow are worked out
//   clock 3 : tile ROM gives the tile colour number; choose each sprite kind
//   clock 4 : choose the top layer -> palette -> darker? -> VGA pins
// hsync, vsync and video_on are delayed by the same 4 clocks.
//=============================================================================
module kaiju_render (
    input  wire        clk,
    input  wire [9:0]  x, y,
    input  wire        hsync, vsync, video_on,

    input  wire [10:0] cam_x, cam_y,
    input  wire [10:0] spr_x, spr_y,
    input  wire [1:0]  spr_form, spr_frame,
    input  wire        spr_mirror, spr_flash, spr_show, spr_shield,
    input  wire        shd_on,
    input  wire [10:0] shd_x, shd_y,
    input  wire        fire_phase,
    input  wire        dark,            // darker city (title / end)
    input  wire        dark_spr,        // darker sprites (end)
    input  wire        ov_on,           // text page on top
    input  wire [2:0]  ov_page,
    input  wire        ov_blink,
    input  wire [7:0]  anim,

    input  wire [7:0]  e_on_v,
    input  wire [15:0] e_type_v,
    input  wire [87:0] e_x_v, e_y_v,
    input  wire [7:0]  e_face_v, e_flash_v,
    input  wire [7:0]  b_on_v,
    input  wire [87:0] b_x_v, b_y_v,
    input  wire [15:0] b_kind_v,
    input  wire [3:0]  bm_on_v,
    input  wire [43:0] bm_x_v, bm_y_v,
    input  wire [3:0]  bm_fr_v,
    input  wire        it_on, it_hide,
    input  wire [1:0]  it_type,
    input  wire [10:0] it_x, it_y,

    output wire [13:0] tile_addr,       // tile RAM port B
    input  wire [3:0]  tile_id,

    output reg  [3:0]  VGA_R = 0, VGA_G = 0, VGA_B = 0,
    output reg         VGA_HS = 1, VGA_VS = 1
);
    //---------------- clock 1 : where is this pixel on the map?
    reg [10:0] wx = 0, wy = 0;
    reg [7:0]  ox = 0;                  // text page pixel (4 x 4 screen pixels each)
    reg [6:0]  oy = 0;
    reg        vid_0 = 0, hs_0 = 1, vs_0 = 1;
    always @(posedge clk) begin
        wx <= cam_x + {2'b0, x[9:1]};
        wy <= cam_y + {2'b0, y[9:1]};
        ox <= x[9:2];
        oy <= y[9:2];
        vid_0 <= video_on;  hs_0 <= hsync;  vs_0 <= vsync;
    end
    assign tile_addr = {wy[10:4], wx[10:4]};

    //---------------- clock 2 : sprites
    // player: size x size, top-left at (spr_x, spr_y)
    wire [5:0]  size = (spr_form == 0) ? 6'd16 : (spr_form == 1) ? 6'd32 : 6'd48;
    wire signed [11:0] sx = $signed({1'b0, wx}) - $signed({1'b0, spr_x});
    wire signed [11:0] sy = $signed({1'b0, wy}) - $signed({1'b0, spr_y});
    wire        on_spr = spr_show && (sx >= 0) && (sx < $signed({6'b0, size})) &&
                         (sy >= 0) && (sy < $signed({6'b0, size}));
    wire [5:0]  col = spr_mirror ? (size - 6'd1 - sx[5:0]) : sx[5:0];
    wire [5:0]  row = sy[5:0];
    wire [9:0]  a_f1 = {spr_frame, row[3:0], col[3:0]};                          // 16 x 16
    wire [11:0] a_f2 = {spr_frame, row[4:0], col[4:0]};                          // 32 x 32
    wire [13:0] a_f3 = spr_frame * 14'd2304 + {row, 5'b0} + {row, 4'b0} + col;   // 48 x 48
    wire [3:0] q_f1, q_f2, q_f3;
    rom_1p #(.DW(4), .AW(10), .DEPTH(768),  .FILE("spr_f1.mem")) u_f1 (.clk(clk), .addr(a_f1), .q(q_f1));
    rom_1p #(.DW(4), .AW(12), .DEPTH(3072), .FILE("spr_f2.mem")) u_f2 (.clk(clk), .addr(a_f2), .q(q_f2));
    rom_1p #(.DW(4), .AW(14), .DEPTH(9216), .FILE("spr_f3.mem")) u_f3 (.clk(clk), .addr(a_f3), .q(q_f3));

    // enemies: police car / tank 16x16, helicopter 32x32, nuke truck 32x16; centre at (e_x, e_y)
    reg        e_hit;
    reg [1:0]  e_typ;
    reg [4:0]  e_col, e_row;
    reg        e_fl;
    integer i, i2, i3;
    always @(*) begin : pick_enemy
        reg [5:0] w, h;
        reg signed [12:0] ex0, ey0;
        e_hit = 0;  e_typ = 0;  e_col = 0;  e_row = 0;  e_fl = 0;
        for (i = 7; i >= 0; i = i - 1) begin
            w = (e_type_v[2*i +: 2] >= 2) ? 6'd32 : 6'd16;
            h = (e_type_v[2*i +: 2] == 2) ? 6'd32 : 6'd16;
            ex0 = $signed({2'b0, wx}) - $signed({2'b0, e_x_v[11*i +: 11]}) + $signed({7'b0, w[5:1]});
            ey0 = $signed({2'b0, wy}) - $signed({2'b0, e_y_v[11*i +: 11]}) + $signed({7'b0, h[5:1]});
            if (e_on_v[i] && ex0 >= 0 && ex0 < $signed({7'b0, w}) && ey0 >= 0 && ey0 < $signed({7'b0, h})) begin
                e_hit = 1;
                e_typ = e_type_v[2*i +: 2];
                e_col = e_face_v[i] ? (w[4:0] - 5'd1 - ex0[4:0]) : ex0[4:0];   // sprites face left
                e_row = ey0[4:0];
                e_fl  = e_flash_v[i];
            end
        end
    end
    // animation: police lights, tank tracks, rotor, beacon
    wire        e_frame = (e_typ == 0) ? anim[3] : (e_typ == 1) ? anim[2] : (e_typ == 2) ? anim[1] : anim[3];
    wire [12:0] a_en = {e_typ, e_frame, e_row, e_col};
    wire [3:0]  q_en;
    rom_1p #(.DW(4), .AW(13), .DEPTH(8192), .FILE("spr_enemy.mem")) u_en (.clk(clk), .addr(a_en), .q(q_en));

    // explosions 16x16, centre at (bm_x, bm_y)
    reg        m_hit;
    reg [3:0]  m_col, m_row;
    reg        m_fr;
    always @(*) begin : pick_boom
        reg signed [12:0] mx0, my0;
        m_hit = 0;  m_col = 0;  m_row = 0;  m_fr = 0;
        for (i2 = 3; i2 >= 0; i2 = i2 - 1) begin
            mx0 = $signed({2'b0, wx}) - $signed({2'b0, bm_x_v[11*i2 +: 11]}) + 13'sd8;
            my0 = $signed({2'b0, wy}) - $signed({2'b0, bm_y_v[11*i2 +: 11]}) + 13'sd8;
            if (bm_on_v[i2] && mx0 >= 0 && mx0 < 13'sd16 && my0 >= 0 && my0 < 13'sd16) begin
                m_hit = 1;  m_col = mx0[3:0];  m_row = my0[3:0];  m_fr = bm_fr_v[i2];
            end
        end
    end
    wire [3:0] q_bm;
    rom_1p #(.DW(4), .AW(9), .DEPTH(512), .FILE("spr_boom.mem")) u_bm (.clk(clk), .addr({m_fr, m_row, m_col}), .q(q_bm));

    // power-up item 16x16, centre at (it_x, it_y)
    wire signed [12:0] ix0 = $signed({2'b0, wx}) - $signed({2'b0, it_x}) + 13'sd8;
    wire signed [12:0] iy0 = $signed({2'b0, wy}) - $signed({2'b0, it_y}) + 13'sd8;
    wire        i_hit = it_on && !it_hide && ix0 >= 0 && ix0 < 13'sd16 && iy0 >= 0 && iy0 < 13'sd16;
    wire [3:0]  q_it;
    rom_1p #(.DW(4), .AW(10), .DEPTH(768), .FILE("spr_items.mem")) u_it (.clk(clk), .addr({it_type, iy0[3:0], ix0[3:0]}), .q(q_it));

    // bullets: 5x5 balls without corners, drawn from numbers (no ROM)
    //   police: white core, red ring · tank: yellow / orange · helicopter: white / sky
    reg        bl_hit;
    reg [3:0]  bl_idx;
    always @(*) begin : pick_bullet
        reg signed [12:0] dx, dy;
        reg [12:0] ax, ay;
        reg [1:0]  kd;
        bl_hit = 0;  bl_idx = 0;
        for (i3 = 7; i3 >= 0; i3 = i3 - 1) begin
            dx = $signed({2'b0, wx}) - $signed({2'b0, b_x_v[11*i3 +: 11]});
            dy = $signed({2'b0, wy}) - $signed({2'b0, b_y_v[11*i3 +: 11]});
            ax = dx[12] ? -dx : dx;
            ay = dy[12] ? -dy : dy;
            kd = b_kind_v[2*i3 +: 2];
            if (b_on_v[i3] && ax <= 2 && ay <= 2 && !(ax == 2 && ay == 2)) begin
                bl_hit = 1;
                if (ax <= 1 && ay <= 1) bl_idx = (kd == 1) ? 4'd12 : 4'd6;
                else                    bl_idx = (kd == 0) ? 4'd14 : (kd == 1) ? 4'd13 : 4'd11;
            end
        end
    end

    // shadow while jumping: ellipse  dx^2 * rh^2 + dy^2 * rw^2 <= rw^2 * rh^2
    //   rw x rh = 4 x 2, 9 x 2, 13 x 3 for the 3 forms
    wire signed [11:0] hdx = $signed({1'b0, wx}) - $signed({1'b0, shd_x});
    wire signed [11:0] hdy = $signed({1'b0, wy}) - $signed({1'b0, shd_y});
    wire [11:0] adx = hdx[11] ? -hdx : hdx;
    wire [11:0] ady = hdy[11] ? -hdy : hdy;
    wire [3:0]  rh2 = (spr_form == 2) ? 4'd9   : 4'd4;
    wire [7:0]  rw2 = (spr_form == 0) ? 8'd16  : (spr_form == 1) ? 8'd81  : 8'd169;
    wire [10:0] k   = (spr_form == 0) ? 11'd64 : (spr_form == 1) ? 11'd324 : 11'd1521;
    wire [11:0] e   = adx[3:0] * adx[3:0] * rh2 + ady[1:0] * ady[1:0] * rw2;
    wire        in_shd = shd_on && (adx <= 12'd13) && (ady <= 12'd3) && (e <= {1'b0, k});

    // text pages: 160 x 120, 3 bits;  addr = page * 19200 + oy * 160 + ox   (160 = 128 + 32)
    wire [16:0] a_ov = ov_page * 17'd19200 + {oy, 7'b0} + {oy, 5'b0} + ox;
    wire [2:0]  q_ov;
    rom_1p #(.DW(3), .AW(17), .DEPTH(115200), .FILE("overlay.mem")) u_ov (.clk(clk), .addr(a_ov), .q(q_ov));

    // pipeline registers into clock 3
    reg  [3:0] tx_1 = 0, ty_1 = 0;
    reg        on_1 = 0, en_1 = 0, en_fl_1 = 0, en_air_1 = 0, bm_1 = 0, it_1 = 0, shd_1 = 0, bl_1 = 0;
    reg  [3:0] bl_idx_1 = 0;
    reg        vid_1 = 0, hs_1 = 1, vs_1 = 1;
    always @(posedge clk) begin
        tx_1 <= wx[3:0];  ty_1 <= wy[3:0];
        on_1 <= on_spr;   en_1 <= e_hit;   en_fl_1 <= e_fl;   en_air_1 <= (e_typ == 2);
        bm_1 <= m_hit;    it_1 <= i_hit;   shd_1 <= in_shd;
        bl_1 <= bl_hit;   bl_idx_1 <= bl_idx;
        vid_1 <= vid_0;   hs_1 <= hs_0;    vs_1 <= vs_0;
    end

    //---------------- clock 3 : tile picture, choose each sprite kind
    // fire tiles flicker: show them mirrored every 8 frames
    wire [3:0]  tcol   = (tile_id == 4'd15 && fire_phase) ? ~tx_1 : tx_1;
    wire [3:0]  q_tile;
    rom_1p #(.DW(4), .AW(12), .DEPTH(4096), .FILE("tiles.mem")) u_tiles (.clk(clk), .addr({tile_id, ty_1, tcol}), .q(q_tile));

    wire [3:0]  q_spr = (spr_form == 0) ? q_f1 : (spr_form == 1) ? q_f2 : q_f3;

    reg  [3:0] p_idx = 0, e_idx = 0, m_idx = 0, i_idx = 0, bl_idx_2 = 0;
    reg        p_see = 0, e_see = 0, e_air = 0, m_see = 0, i_see = 0, bl_see = 0, shd_2 = 0;
    reg  [2:0] ov_2 = 0;
    reg        vid_2 = 0, hs_2 = 1, vs_2 = 1;
    always @(posedge clk) begin
        // colour 0 of every sprite is see-through
        p_see <= on_1 && (q_spr != 0);
        p_idx <= spr_flash ? 4'd6 : (spr_shield && q_spr == 4'd1) ? 4'd11 : q_spr;   // shield: blue outline
        e_see <= en_1 && (q_en != 0);
        e_idx <= en_fl_1 ? 4'd6 : q_en;                                                // stunned: white
        e_air <= en_air_1;
        m_see <= bm_1 && (q_bm != 0);   m_idx <= q_bm;
        i_see <= it_1 && (q_it != 0);   i_idx <= q_it;
        bl_see <= bl_1;  bl_idx_2 <= bl_idx_1;
        shd_2 <= shd_1;
        ov_2  <= q_ov;
        vid_2 <= vid_1;  hs_2 <= hs_1;  vs_2 <= vs_1;
    end

    //---------------- clock 4 : top layer -> palette -> VGA pins
    reg  [11:0] pal [0:15];
    initial $readmemh("palette.mem", pal);

    // text colour code -> palette: 1 ink, 2 orange, 3 yellow, 4 red, 5 white (blinks), 6 ink (blinks)
    wire        ov_see = ov_on && (ov_2 != 0) && (ov_2 < 5 || ov_blink);
    wire [3:0]  ov_idx = (ov_2 == 2) ? 4'd13 : (ov_2 == 3) ? 4'd12 : (ov_2 == 4) ? 4'd14 :
                         (ov_2 == 5) ? 4'd6  : 4'd1;
    wire        tile_layer = !(ov_see || m_see || bl_see || e_see || p_see || i_see);
    wire [3:0]  idx = ov_see           ? ov_idx :
                      m_see            ? m_idx  :
                      bl_see           ? bl_idx_2 :
                      (e_see && e_air) ? e_idx  :
                      p_see            ? p_idx  :
                      e_see            ? e_idx  :
                      i_see            ? i_idx  : q_tile;
    wire [11:0] c0   = pal[idx];
    wire [11:0] half = {1'b0, c0[11:9], 1'b0, c0[7:5], 1'b0, c0[3:1]};
    wire        dim  = ov_see ? 1'b0 : tile_layer ? (dark || shd_2) : dark_spr;   // shadow = half the colour

    always @(posedge clk) begin
        {VGA_R, VGA_G, VGA_B} <= vid_2 ? (dim ? half : c0) : 12'h000;   // black outside the picture
        VGA_HS <= hs_2;
        VGA_VS <= vs_2;
    end
endmodule
