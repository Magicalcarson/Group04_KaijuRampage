`timescale 1ns / 1ps
//=============================================================================
// Kaiju Rampage : sound effects + background music on the mono audio jack (AUD_PWM)
//                                                                      SW15 = on
//
// Effect voice: a square wave (or LFSR noise for crashes) whose half-period
// changes by a fixed step every frame, so the pitch slides:
//   eat     660 -> 990 Hz      5 frames   square
//   jump    260 -> 620 Hz      8 frames   square
//   smash   180 ->  40 Hz     13 frames   noise
//   pickup  660, 880, 1320 Hz  4 frames each
//   fanfare 330, 416, 524, 660 Hz, 7 frames each   (start, evolve, win)
//   over    220 ->  80 Hz     40 frames   square
//   hit     140 ->  60 Hz     18 frames   square
//   stomp    90 ->  30 Hz     27 frames   noise
//   roar     70 ->  40 Hz     30 frames   noise
// Effects asked for during a frame are collected; at the next frame the most
// important one starts, unless a more important one is still playing.
//
// Music voice: a 27-note riff from a small ROM, looped while the game is played.
// The effect voice plays over the music (the music is quieter).
//
// AUD_PWM goes through a low-pass filter on the board.  It must be driven LOW or
// left floating (Z) for "high".  Volume = duty of a fast PWM (1.56 MHz) during
// the high half of the wave: 4/16 for effects, 2/16 for the music.
//=============================================================================
module kaiju_sound (
    input  wire       clk,              // 25 MHz
    input  wire       rst,
    input  wire       tick,             // one pulse per frame
    input  wire       en,               // SW15
    input  wire       music_on,         // the game is being played
    input  wire [8:0] sfx,              // pulses {roar, pickup, hit, over, fanfare, stomp, smash, jump, eat}
    output wire       AUD_PWM,
    output wire       AUD_SD            // 1 = amplifier on
);
    reg  [3:0]  pw = 0;
    reg  [15:0] lfsr = 16'h1D2B;
    always @(posedge clk) begin
        pw   <= pw + 1'b1;
        lfsr <= lfsr[0] ? ((lfsr >> 1) ^ 16'hB400) : (lfsr >> 1);
    end

    //=========================================================================
    // effect voice
    //=========================================================================
    reg  [8:0]  want = 0;               // effects asked for during this frame
    reg  [3:0]  prio = 0;               // priority of the effect playing (0 = silent)
    reg  [18:0] per  = 0;               // half-period in clocks
    reg  signed [19:0] dper = 0;        // change of per every frame
    reg  [5:0]  left = 0;               // frames left
    reg         noise = 0;
    reg         arp = 0, arp_b = 0;     // notes from a table: fanfare (a) or pickup (b)
    reg  [2:0]  note_t = 0;
    reg  [1:0]  note = 0;
    reg  [18:0] cnt = 0;
    reg         sq = 0;

    // highest effect asked for, and its priority
    wire [3:0] new_prio = want[8] ? 4'd9 : want[3] ? 4'd8 : want[6] ? 4'd7 : want[5] ? 4'd6 :
                          want[4] ? 4'd5 : want[7] ? 4'd4 : want[2] ? 4'd3 : want[1] ? 4'd2 :
                          want[0] ? 4'd1 : 4'd0;

    function [18:0] note_per;            // 25 MHz / (2 f)
        input b; input [1:0] n;
        note_per = b ? ((n == 0) ? 19'd18939 : (n == 1) ? 19'd14205 : 19'd9470) :        // 660 880 1320
                       ((n == 0) ? 19'd37879 : (n == 1) ? 19'd30063 : (n == 2) ? 19'd23861 : 19'd18939);
    endfunction

    always @(posedge clk) begin
        if (left != 0) begin
            if (cnt >= (noise ? {2'b0, per[18:2]} : per)) begin      // noise changes 4x faster
                cnt <= 0;
                sq  <= noise ? lfsr[0] : ~sq;
            end else
                cnt <= cnt + 1'b1;
        end

        if (rst) begin
            want <= 0;  left <= 0;  prio <= 0;
        end else if (tick) begin
            want <= sfx;                                             // a pulse in this very clock counts too
            if (new_prio != 0 && (left == 0 || new_prio >= prio)) begin
                prio <= new_prio;  cnt <= 0;  arp <= 1'b0;  noise <= 1'b0;  note <= 0;  note_t <= 0;
                case (new_prio)
                    4'd9: begin per <= 19'd178571; dper <=  20'sd4464;  left <= 6'd30; noise <= 1'b1; end  // roar
                    4'd8: begin per <= 19'd138889; dper <=  20'sd10288; left <= 6'd27; noise <= 1'b1; end  // stomp
                    4'd7: begin per <= 19'd89286;  dper <=  20'sd6720;  left <= 6'd18; end                 // hit
                    4'd6: begin per <= 19'd56818;  dper <=  20'sd2486;  left <= 6'd40; end                 // over
                    4'd5: begin per <= note_per(1'b0, 2'd0); dper <= 0; left <= 6'd28; arp <= 1'b1; arp_b <= 1'b0; end
                    4'd4: begin per <= note_per(1'b1, 2'd0); dper <= 0; left <= 6'd12; arp <= 1'b1; arp_b <= 1'b1; end
                    4'd3: begin per <= 19'd69444;  dper <=  20'sd18675; left <= 6'd13; noise <= 1'b1; end  // smash
                    4'd2: begin per <= 19'd48077;  dper <= -20'sd3490;  left <= 6'd8;  end                 // jump
                    default: begin per <= 19'd18939; dper <= -20'sd1578; left <= 6'd5; end                 // eat
                endcase
            end else if (left != 0) begin
                left <= left - 1'b1;
                if (left == 1) prio <= 0;
                if (arp) begin
                    if (note_t == (arp_b ? 3'd3 : 3'd6)) begin       // 4 or 7 frames per note
                        note_t <= 0;
                        note   <= note + 1'b1;
                        per    <= note_per(arp_b, note + 1'b1);
                    end else
                        note_t <= note_t + 1'b1;
                end else
                    per <= $unsigned($signed({1'b0, per}) + dper);
            end
        end else
            want <= want | sfx;
    end

    //=========================================================================
    // music voice: riff in A minor, one eighth note = 10 frames
    //=========================================================================
    // pitch 0 = rest; half-periods for 25 MHz
    function [16:0] pitch_per;
        input [3:0] p;
        case (p)
            4'd1:  pitch_per = 17'd56818;   // A3
            4'd2:  pitch_per = 17'd47778;   // C4
            4'd3:  pitch_per = 17'd42566;   // D4
            4'd4:  pitch_per = 17'd37921;   // E4
            4'd5:  pitch_per = 17'd35793;   // F4
            4'd6:  pitch_per = 17'd31888;   // G4
            4'd7:  pitch_per = 17'd28409;   // A4
            default: pitch_per = 17'd0;
        endcase
    endfunction

    // the riff: {pitch, length in eighth notes}
    function [5:0] riff;
        input [4:0] i;
        case (i)
            5'd0:  riff = {4'd1, 2'd1};  5'd1:  riff = {4'd1, 2'd1};  5'd2:  riff = {4'd2, 2'd1};
            5'd3:  riff = {4'd1, 2'd1};  5'd4:  riff = {4'd3, 2'd1};  5'd5:  riff = {4'd1, 2'd1};
            5'd6:  riff = {4'd4, 2'd2};
            5'd7:  riff = {4'd1, 2'd1};  5'd8:  riff = {4'd1, 2'd1};  5'd9:  riff = {4'd2, 2'd1};
            5'd10: riff = {4'd1, 2'd1};  5'd11: riff = {4'd6, 2'd1};  5'd12: riff = {4'd5, 2'd1};
            5'd13: riff = {4'd4, 2'd2};
            5'd14: riff = {4'd3, 2'd1};  5'd15: riff = {4'd3, 2'd1};  5'd16: riff = {4'd5, 2'd1};
            5'd17: riff = {4'd3, 2'd1};  5'd18: riff = {4'd6, 2'd1};  5'd19: riff = {4'd5, 2'd1};
            5'd20: riff = {4'd4, 2'd2};
            5'd21: riff = {4'd2, 2'd1};  5'd22: riff = {4'd3, 2'd1};  5'd23: riff = {4'd4, 2'd1};
            5'd24: riff = {4'd6, 2'd1};  5'd25: riff = {4'd7, 2'd2};  5'd26: riff = {4'd0, 2'd2};
            default: riff = {4'd0, 2'd1};
        endcase
    endfunction
    localparam [4:0] RIFF_LAST = 5'd26;

    reg  [4:0]  m_i = 0;                // note number
    reg  [5:0]  m_t = 0;                // frames into the note
    reg  [16:0] m_cnt = 0;
    reg         m_sq = 0;
    wire [5:0]  m_note = riff(m_i);
    wire [16:0] m_per  = pitch_per(m_note[5:2]);
    wire [5:0]  m_len  = (m_note[1:0] == 2'd2) ? 6'd20 : 6'd10;
    wire        m_gate = music_on && (m_note[5:2] != 0) && (m_t < m_len - 6'd2);   // short gap between notes

    always @(posedge clk) begin
        if (m_cnt >= m_per) begin m_cnt <= 0; m_sq <= ~m_sq; end
        else m_cnt <= m_cnt + 1'b1;
        if (rst || !music_on) begin
            m_i <= 0;  m_t <= 0;
        end else if (tick) begin
            if (m_t == m_len - 1'b1) begin
                m_t <= 0;
                m_i <= (m_i == RIFF_LAST) ? 5'd0 : m_i + 1'b1;
            end else
                m_t <= m_t + 1'b1;
        end
    end

    //=========================================================================
    // mix: the effect if one is playing, else the music
    //=========================================================================
    wire [3:0] level = (left >= 6'd4) ? 4'd4 : left[3:0];          // effects fade in the last 4 frames
    wire       fx    = (left != 0);
    wire       high  = en && (fx ? (sq && (pw < level)) : (m_gate && m_sq && (pw < 4'd2)));

    assign AUD_PWM = high ? 1'bz : 1'b0;
    assign AUD_SD  = en;
endmodule
