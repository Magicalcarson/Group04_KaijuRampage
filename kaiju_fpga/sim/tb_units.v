`timescale 1ns / 1ps
//=============================================================================
// Short testbench for the units (Feature 3.3, 3.4, 3.5, 3.7): about 70 frames.
// It starts a game as the full kaiju, puts 4 enemies and a shield item next to
// the player, then checks bullets / damage, pick-up, roar (stun) and stomp.
// Screenshots: shot_u*.ppm (320 x 240, convert with ppm_to_png.py).
//=============================================================================
module tb_units;
    reg clk = 0;
    always #20 clk = ~clk;                 // 25 MHz

    reg        rst = 1;
    reg        U = 0, D = 0, L = 0, R = 0, C = 0;
    reg  [1:0] SW = 0;
    wire       AUD_PWM, AUD_SD, M_CLK, M_LRSEL;
    reg        M_DATA = 0;
    always @(posedge M_CLK) M_DATA <= ~M_DATA;      // quiet microphone
    wire [3:0] VGA_R, VGA_G, VGA_B;
    wire       VGA_HS, VGA_VS, DP;
    wire [15:0] LED;
    wire       LED16_R, LED16_G, LED16_B, LED17_R, LED17_G, LED17_B;
    wire [6:0] SEG;
    wire [7:0] AN;

    kaiju_core dut (
        .clk(clk), .rst(rst), .BTNU(U), .BTND(D), .BTNL(L), .BTNR(R), .BTNC(C),
        .SW(SW), .SW_MIC(2'b00), .SW14(1'b0), .SW15(1'b1),
        .M_DATA(M_DATA), .M_CLK(M_CLK), .M_LRSEL(M_LRSEL),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .LED(LED), .LED16_R(LED16_R), .LED16_G(LED16_G), .LED16_B(LED16_B),
        .LED17_R(LED17_R), .LED17_G(LED17_G), .LED17_B(LED17_B),
        .SEG(SEG), .DP(DP), .AN(AN), .AUD_PWM(AUD_PWM), .AUD_SD(AUD_SD));

    localparam S_IDLE = 2;
    integer errors = 0, frames = 0;
    always @(posedge clk) if (dut.tick) frames = frames + 1;

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

    // the colour on the pins belongs to (x, y) of 4 clocks before
    reg [9:0] xd [1:4], yd [1:4];
    integer q;
    always @(posedge clk) begin
        xd[1] <= dut.x;  yd[1] <= dut.y;
        for (q = 2; q <= 4; q = q + 1) begin xd[q] <= xd[q-1]; yd[q] <= yd[q-1]; end
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
                if (xd[4] < 640 && yd[4] < 480 && !xd[4][0] && !yd[4][0]) begin
                    $fwrite(fd, "%0d %0d %0d\n", VGA_R, VGA_G, VGA_B);
                    n = n + 1;
                end
            end
            $fclose(fd);
            $display("[frame %0d] saved %0s", frames, name);
        end
    endtask

    task show(input [8*24-1:0] what);
        $display("%0s: frame %0d px=%0d py=%0d form=%0d state=%0d hp=%0d score=%0d e_on=%b b_on=%b it_on=%0d shield=%0d stun0=%0d",
                 what, frames, dut.u_game.px, dut.u_game.py, dut.u_game.form, dut.u_game.gstate, dut.u_game.hp,
                 dut.u_game.score, dut.u_game.e_on, dut.u_game.b_on, dut.u_game.it_on, dut.u_game.shield,
                 dut.u_game.e_stun[0]);
    endtask

    task check(input cond, input [8*48-1:0] msg);
        if (!cond) begin errors = errors + 1; $display("  FAIL: %0s", msg); end
        else $display("  ok  : %0s", msg);
    endtask

    integer px0, py0, hp0, s0;

    initial begin
        repeat (20) @(posedge clk);
        rst = 0;
        wait (dut.u_game.st == S_IDLE);
        wait_frames(2);
        C = 1;  wait_frames(2);  C = 0;
        SW = 2'b11;  wait_frames(2);  SW = 2'b00;  // full kaiju (SW back to 0 keeps the form)
        wait_frames(1);
        show("start");
        check(dut.u_game.form == 2 && dut.u_game.gstate == 0, "playing as the full kaiju");
        check(dut.u_game.hp == 9, "full kaiju has 9 HP");

        // put 4 enemies around the player, ready to shoot, and a shield item
        px0 = dut.u_game.px;  py0 = dut.u_game.py - 24;
        dut.u_game.spawn_t = 8'd250;
        dut.u_game.e_type[0] = 0; dut.u_game.e_x[0] = px0 - 70; dut.u_game.e_y[0] = py0;      dut.u_game.e_cd[0] = 2;
        dut.u_game.e_type[1] = 1; dut.u_game.e_x[1] = px0 + 75; dut.u_game.e_y[1] = py0 + 10; dut.u_game.e_cd[1] = 4;
        dut.u_game.e_type[2] = 2; dut.u_game.e_x[2] = px0 + 10; dut.u_game.e_y[2] = py0 - 85; dut.u_game.e_cd[2] = 6;
        dut.u_game.e_type[3] = 3; dut.u_game.e_x[3] = px0 - 90; dut.u_game.e_y[3] = py0 + 70; dut.u_game.e_cd[3] = 0;
        for (q = 0; q < 4; q = q + 1) begin dut.u_game.e_stun[q] = 0; dut.u_game.e_wt[q] = 0; end
        dut.u_game.e_on = 8'b0000_1111;
        dut.u_game.it_on = 1;  dut.u_game.it_type = 2;  dut.u_game.it_t = 10'd600;
        dut.u_game.it_x = px0 + 40;  dut.u_game.it_y = py0 + 40;
        hp0 = dut.u_game.hp;

        wait_frames(10);
        show("enemies placed");
        check(dut.u_game.b_on != 0, "enemies fire bullets");
        shot("shot_u1_enemies.ppm");

        wait_frames(25);
        show("after bullets");
        check(dut.u_game.hp < hp0, "bullets hurt the kaiju (HP went down)");

        // walk to the item: right and down
        R = 1; D = 1;  wait_frames(30);  R = 0; D = 0;  wait_frames(1);
        show("walked to the item");
        check(dut.u_game.it_on == 0 && dut.u_game.shield == 1, "shield item picked up");
        shot("shot_u2_shield.ppm");

        // roar: as if the microphone heard a shout
        force dut.u_game.roar_req = 1'b1;  repeat (3) @(posedge clk);  release dut.u_game.roar_req;
        wait_frames(2);
        show("roar");
        check(dut.u_game.roar_cd != 0, "roar started (cooldown running)");

        // jump -> stomp blows up enemies close by
        s0 = dut.u_game.score;
        C = 1;  wait_frames(1);  C = 0;  wait_frames(24);
        show("stomp");
        shot("shot_u3_stomp.ppm");

        $display("==== %0d error(s) ====", errors);
        $finish;
    end
endmodule
