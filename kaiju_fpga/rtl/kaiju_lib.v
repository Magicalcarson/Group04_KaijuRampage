`timescale 1ns / 1ps
//=============================================================================
// Kaiju Rampage : small building blocks
//   vga_sync ..... VGA 640 x 480 @ 60 Hz timing (same as LAB08 Part A)
//   rom_1p ....... ROM in Block RAM, loaded from a .mem file, 1 clock read
//   tile_ram ..... the city map that can change: 2 ports, 1 clock read
//   bin2bcd ...... binary -> BCD digits for the 7-segment display
//   seg7_mux ..... drives the 8 digits of the 7-segment display
//=============================================================================


//-----------------------------------------------------------------------------
// VGA 640 x 480 @ 60 Hz.  clk = 25 MHz, one clock = one pixel.
// x counts 0 .. 799, y counts 0 .. 524.  hsync / vsync are active LOW.
//-----------------------------------------------------------------------------
module vga_sync (
    input  wire       clk,
    input  wire       rst,
    output reg  [9:0] x = 10'd0,
    output reg  [9:0] y = 10'd0,
    output wire       hsync,
    output wire       vsync,
    output wire       video_on
);
    localparam H_VISIBLE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48;
    localparam V_VISIBLE = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33;
    localparam H_TOTAL = H_VISIBLE + H_FP + H_SYNC + H_BP;   // 800
    localparam V_TOTAL = V_VISIBLE + V_FP + V_SYNC + V_BP;   // 525

    wire x_end = (x == H_TOTAL - 1);
    wire y_end = (y == V_TOTAL - 1);

    assign hsync    = ~((x >= H_VISIBLE + H_FP) && (x < H_VISIBLE + H_FP + H_SYNC));
    assign vsync    = ~((y >= V_VISIBLE + V_FP) && (y < V_VISIBLE + V_FP + V_SYNC));
    assign video_on = (x < H_VISIBLE) && (y < V_VISIBLE);

    always @(posedge clk) begin
        if (rst) begin
            x <= 10'd0;
            y <= 10'd0;
        end else begin
            x <= x_end ? 10'd0 : x + 10'd1;
            if (x_end) y <= y_end ? 10'd0 : y + 10'd1;
        end
    end
endmodule


//-----------------------------------------------------------------------------
// ROM, 1 clock read latency, Block RAM.  DEPTH may be less than 2^AW.
//-----------------------------------------------------------------------------
module rom_1p #(
    parameter DW = 4, AW = 12, DEPTH = 1 << AW,
    parameter FILE = ""
) (
    input  wire          clk,
    input  wire [AW-1:0] addr,
    output reg  [DW-1:0] q = 0
);
    (* rom_style = "block" *) reg [DW-1:0] mem [0:DEPTH-1];
    initial $readmemh(FILE, mem);
    always @(posedge clk) q <= mem[addr];
endmodule


//-----------------------------------------------------------------------------
// Tile map RAM: 128 x 96 tiles, 4 bits each.  addr = {row[6:0], col[6:0]}.
//   port A : game logic, read and write
//   port B : picture, read only
// The power-up content comes from map.mem (the bitstream).  On CPU RESET the
// game copies the map ROM into this RAM again, so the city is rebuilt.
//-----------------------------------------------------------------------------
module tile_ram #(
    parameter FILE = "map.mem"
) (
    input  wire        clk,
    input  wire [13:0] a_addr,
    input  wire        a_we,
    input  wire [3:0]  a_din,
    output reg  [3:0]  a_dout = 0,
    input  wire [13:0] b_addr,
    output reg  [3:0]  b_dout = 0
);
    (* ram_style = "block" *) reg [3:0] mem [0:16383];
    initial $readmemh(FILE, mem);

    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        a_dout <= mem[a_addr];
    end
    always @(posedge clk) b_dout <= mem[b_addr];
endmodule


//-----------------------------------------------------------------------------
// Binary -> BCD, "double dabble", one bit per clock.  It runs again and again,
// so bcd follows bin about W + 1 clocks later.
//-----------------------------------------------------------------------------
module bin2bcd #(
    parameter W = 14,      // binary bits
    parameter D = 4        // decimal digits
) (
    input  wire           clk,
    input  wire [W-1:0]   bin,
    output reg  [4*D-1:0] bcd = 0
);
    reg [W-1:0]   sh  = 0;
    reg [4*D-1:0] acc = 0;
    reg [5:0]     n   = 0;

    // add 3 to every digit that is 5 or more, before the shift
    reg [4*D-1:0] adj;
    integer i;
    always @(*) begin
        adj = acc;
        for (i = 0; i < D; i = i + 1)
            if (adj[4*i +: 4] >= 4'd5) adj[4*i +: 4] = adj[4*i +: 4] + 4'd3;
    end

    always @(posedge clk) begin
        if (n == 0) begin
            sh  <= bin;
            acc <= 0;
            n   <= W;
        end else begin
            acc <= {adj[4*D-2:0], sh[W-1]};
            sh  <= sh << 1;
            n   <= n - 1'b1;
            if (n == 1) bcd <= {adj[4*D-2:0], sh[W-1]};
        end
    end
endmodule


//-----------------------------------------------------------------------------
// 8-digit 7-segment display, one digit at a time (about 95 Hz for all 8).
//   digits = 8 x 4 bits, digits[31:28] is the left digit (AN7).
//   value 0-9 = number, 4'hF = blank, 4'hE = "-"
//   dp[i] = 1 lights the decimal point of digit i (AN i)
//   seg = {CG, CF, CE, CD, CC, CB, CA}, active LOW.  an and dp_n are active LOW.
//-----------------------------------------------------------------------------
module seg7_mux (
    input  wire        clk,
    input  wire [31:0] digits,
    input  wire [7:0]  dp,
    output reg  [6:0]  seg  = 7'h7F,
    output reg  [7:0]  an   = 8'hFF,
    output reg         dp_n = 1'b1
);
    reg [17:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1'b1;

    wire [2:0] sel = cnt[17:15];                  // 25 MHz / 2^15 = 763 Hz per digit
    wire [3:0] d   = digits[4*sel +: 4];

    always @(posedge clk) begin
        an <= ~(8'b1 << sel);
        dp_n <= ~dp[sel];
        case (d)                                  //  gfedcba
            4'd0: seg <= 7'b1000000;
            4'd1: seg <= 7'b1111001;
            4'd2: seg <= 7'b0100100;
            4'd3: seg <= 7'b0110000;
            4'd4: seg <= 7'b0011001;
            4'd5: seg <= 7'b0010010;
            4'd6: seg <= 7'b0000010;
            4'd7: seg <= 7'b1111000;
            4'd8: seg <= 7'b0000000;
            4'd9: seg <= 7'b0010000;
            4'hE: seg <= 7'b0111111;              // "-"
            default: seg <= 7'b1111111;           // blank
        endcase
    end
endmodule
