`timescale 1ns / 1ps
//=============================================================================
// Testbench for kaiju_core (25 MHz clock given directly, no MMCM).
// It plays a short game with the buttons, checks the results and saves
// screenshots (shot_*.ppm, 320 x 240) taken from the VGA pins.
//   Vivado: set tb_kaiju as top of sim_1, Run All (takes a few minutes).
//=============================================================================
module tb_kaiju;
    reg clk = 0;
    always #20 clk = ~clk;                 // 25 MHz

    reg        rst = 1;
    reg        U = 0, D = 0, L = 0, R = 0, C = 0;
    reg  [1:0] SW = 0;
    reg        SW15 = 1;                   // sound on
    wire       AUD_PWM, AUD_SD;
    wire       M_CLK, M_LRSEL;
    reg        M_DATA = 0;                 // quiet microphone: exactly half 1s
    always @(posedge M_CLK) M_DATA <= ~M_DATA;
    wire       LED17_R, LED17_G, LED17_B;
    wire [3:0] VGA_R, VGA_G, VGA_B;
    wire       VGA_HS, VGA_VS;
    wire [15:0] LED;
    wire       LED16_R, LED16_G, LED16_B, DP;
    wire [6:0] SEG;
    wire [7:0] AN;

    kaiju_core dut (
        .clk(clk), .rst(rst), .BTNU(U), .BTND(D), .BTNL(L), .BTNR(R), .BTNC(C), .SW(SW), .SW_MIC(2'b00), .SW14(1'b0), .SW15(SW15),
        .M_DATA(M_DATA), .M_CLK(M_CLK), .M_LRSEL(M_LRSEL),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .LED(LED), .LED16_R(LED16_R), .LED16_G(LED16_G), .LED16_B(LED16_B),
        .LED17_R(LED17_R), .LED17_G(LED17_G), .LED17_B(LED17_B),
        .SEG(SEG), .DP(DP), .AN(AN), .AUD_PWM(AUD_PWM), .AUD_SD(AUD_SD));

    localparam S_IDLE = 2;
    localparam G_PLAY = 0, G_EVOLVE = 1, G_WIN = 2, G_OVER = 3, G_TITLE = 4;

    // ---------------- sound: count started sounds and clocks where the speaker line is released (Z = high)
    integer sounds = 0, aud_high = 0;
    always @(posedge clk) begin
        if (dut.tick && dut.u_sound.new_prio != 0) sounds = sounds + 1;
        if (AUD_PWM === 1'bz) aud_high = aud_high + 1;
    end
    integer errors = 0;

    // ---------------- frames
    integer frames = 0;
    always @(posedge clk) if (dut.tick) frames = frames + 1;

    // wait n frame updates, and until the game (and the fire scanner) is idle again
    task wait_frames(input integer n);
        integer f0;
        begin
            f0 = frames;
            wait (frames >= f0 + n);
            @(posedge clk);
            wait (dut.u_game.st == S_IDLE);
            @(posedge clk);
        end
    endtask

    // ---------------- screenshots: the colour on the pins belongs to (x, y) of 3 clocks before
    reg [9:0] xd1 = 0, xd2 = 0, xd3 = 0, yd1 = 0, yd2 = 0, yd3 = 0;
    always @(posedge clk) begin
        xd1 <= dut.x;  xd2 <= xd1;  xd3 <= xd2;
        yd1 <= dut.y;  yd2 <= yd1;  yd3 <= yd2;
    end

    task shot(input [8*40-1:0] name);
        integer fd, n;
        begin
            fd = $fopen(name, "w");
            $fwrite(fd, "P3\n320 240\n15\n");
            wait (dut.x == 0 && dut.y == 0);
            n = 0;
            while (n < 76800) begin
                @(negedge clk);
                if (xd3 < 640 && yd3 < 480 && !xd3[0] && !yd3[0]) begin
                    $fwrite(fd, "%0d %0d %0d\n", VGA_R, VGA_G, VGA_B);
                    n = n + 1;
                end
            end
            $fclose(fd);
            $display("[%0t] saved %0s", $time, name);
        end
    endtask

    task show(input [8*24-1:0] what);
        $display("%0s: frame %0d  px=%0d py=%0d z=%0d form=%0d state=%0d score=%0d trees=%0d destroyed=%0d time=%0d led=%b",
                 what, frames, dut.u_game.px, dut.u_game.py, dut.u_game.z, dut.u_game.form, dut.u_game.gstate,
                 dut.u_game.score, dut.u_game.trees, dut.u_game.destroyed, dut.u_game.time_s, LED);
    endtask

    task check(input cond, input [8*48-1:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("  FAIL: %0s", msg);
        end else
            $display("  ok  : %0s", msg);
    endtask

    integer s0, d0, py0;
    reg [3:0] orig;

    initial begin
        repeat (20) @(posedge clk);
        rst = 0;
        wait (dut.u_game.st == S_IDLE);              // map ROM copied into the tile RAM
        wait_frames(40);
        show("title");
        check(dut.u_game.gstate == G_TITLE, "after reset: title page");
        shot("shot_0_title.ppm");
        C = 1;  wait_frames(2);  C = 0;  wait_frames(1);
        show("start");
        check(dut.u_game.gstate == G_PLAY, "BTNC starts the game");
        check(dut.u_game.px == 1080 && dut.u_game.py == 1388 && dut.u_game.form == 0, "start position, form 1");
        shot("shot_1_start.ppm");

        // ---- Feature 1: walk up the road, 2 px per frame
        U = 1;  wait_frames(30);  U = 0;  wait_frames(1);
        show("walk up 30 frames");
        check(dut.u_game.py == 1388 - 60, "hatchling walks 2 px per frame");
        check(dut.u_game.cam_y == dut.u_game.py - 8 - 120, "camera follows the player");

        // ---- Feature 1: a hatchling cannot walk through a house (row 82, col 66 is a house)
        L = 1;  wait_frames(20);  L = 0;  wait_frames(1);
        show("walk left into houses");

        // ---- eat trees on the right (row 86 has trees at col 68, 70, 71)
        D = 1;  wait_frames(30);  D = 0;  wait_frames(1);
        R = 1;  wait_frames(30);  R = 0;  wait_frames(1);
        show("walk right through trees");
        check(dut.u_game.trees > 0 && dut.u_game.score == 5 * dut.u_game.trees, "trees eaten, 5 points each");
        check(LED != 16'h0000, "LED bar shows progress");

        // ---- jump with gravity
        C = 1;  wait_frames(1);  C = 0;
        wait_frames(9);
        show("in the air");
        check(dut.u_game.z > 0, "jump: z > 0");
        check(sounds >= 2 && aud_high > 0 && AUD_SD == 1, "sound plays with SW15 on (start, eat, jump)");
        shot("shot_2_jump.ppm");
        wait_frames(25);
        show("landed");
        check(dut.u_game.z == 0, "gravity brings the player down");

        // ---- Feature 2: debug switches -> KAIJU, stomp and smash
        SW = 2'b11;  wait_frames(2);
        show("SW = 11");
        check(dut.u_game.form == 2, "debug switch forces form 3");
        s0 = dut.u_game.score;  d0 = dut.u_game.destroyed;
        C = 1;  wait_frames(1);  C = 0;
        wait_frames(24);
        show("after stomp");
        shot("shot_3_stomp.ppm");
        U = 1;  wait_frames(90);  U = 0;  wait_frames(1);
        show("kaiju walks up");
        check(dut.u_game.destroyed > d0 && dut.u_game.score > s0, "KAIJU smashes buildings");
        shot("shot_4_smash.ppm");

        // ---- Feature 3: CPU RESET rebuilds the city
        orig = dut.u_map_rom.mem[{7'd80, 7'd68}];
        $display("tile (row 80, col 68): now %0d, map ROM %0d", dut.u_tiles.mem[{7'd80, 7'd68}], orig);
        SW = 2'b00;
        rst = 1;  repeat (5) @(posedge clk);  rst = 0;
        wait (dut.u_game.st == S_IDLE);
        wait_frames(1);
        check(dut.u_tiles.mem[{7'd80, 7'd68}] == orig, "reset copies the map ROM back");
        C = 1;  wait_frames(2);  C = 0;  wait_frames(1);
        check(dut.u_game.score == 0 && dut.u_game.form == 0, "reset: score 0, form 1");

        // ---- Feature 2: 20 trees -> BEAST (96 frames of flashing)
        dut.u_game.trees = 5'd20;
        wait_frames(1);
        show("20 trees");
        check(dut.u_game.gstate == G_EVOLVE, "evolving");
        wait_frames(40);
        shot("shot_5_evolve.ppm");
        wait_frames(60);
        show("after evolve");
        check(dut.u_game.form == 1 && dut.u_game.gstate == G_PLAY, "form 2 after 96 frames");
        shot("shot_6_beast.ppm");

        // ---- time up
        dut.u_game.time_s = 8'd1;
        wait_frames(62);
        show("time up");
        check(dut.u_game.gstate == G_OVER, "time 0 -> game over");
        wait_frames(20);
        shot("shot_7_timeup.ppm");

        // ---- BTNC after the end: rebuild the city, back to the title; SW15 off = silent
        SW15 = 0;  aud_high = 0;
        C = 1;  wait_frames(2);  C = 0;
        wait (dut.u_game.st == S_IDLE);  wait_frames(1);
        show("back to title");
        check(dut.u_game.gstate == G_TITLE, "BTNC after the end -> title");
        check(aud_high == 0 && AUD_SD == 0, "SW15 off: no sound");

        $display("==== %0d error(s) ====", errors);
        $finish;
    end
endmodule
