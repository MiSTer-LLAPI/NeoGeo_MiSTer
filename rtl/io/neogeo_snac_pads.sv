// Digital pad scan sequences adapted from jtframe_snac_arcade in the
// MiSTer-LLAPI arcade cores. Use with the MiSTer-devel SNAC adapter pinout.
// USER_OUT=1 releases an open-drain pin. Only the selected reader owns pins.
module neogeo_snac_pads #(
    parameter integer TICK_CYCLES = 480,  // 10 us at 48 MHz
    parameter integer SCAN_TICKS = 250    // 2.5 ms, includes MD6 timeout
)(
    input clk, reset,
    input [1:0] mode,                     // 0 off, 1 MD, 2 SNES, 3 Saturn
    input [6:0] user_in,
    output [6:0] user_out,
    output reg report_ready = 0,
    output [11:0] pad1, pad2              // ABC combo, coin, select, start, DCBA, UDLR
);
    localparam MD = 2'd1, SNES = 2'd2, SATURN = 2'd3;
    localparam TICK_BITS = TICK_CYCLES > 1 ? $clog2(TICK_CYCLES) : 1;
    localparam PHASE_BITS = $clog2(SCAN_TICKS);
    reg [TICK_BITS-1:0] ticks = 0;
    reg [PHASE_BITS-1:0] phase = 0;
    reg [1:0] last_mode = 0;
    reg [6:0] drive = 7'h7f;
    reg [11:0] first = 0, second = 0;
    wire scanning = !reset && mode != 0 && mode == last_mode;
    assign user_out = scanning ? drive : 7'h7f;
    assign pad1 = scanning ? first : 12'd0;
    assign pad2 = scanning ? second : 12'd0;

    (* async_reg="true" *) reg [6:0] input_meta = 7'h7f, pins = 7'h7f;
    always @(posedge clk) begin
        input_meta <= user_in;
        pins <= input_meta;
    end

    reg [15:0] snes1 = '1, snes2 = '1;
    function automatic [11:0] snes_pad(input [15:0] serial);
        // Physical B,A,Y,X -> Neo Geo A,B,C,D, and R -> ABC. Same face
        // layout and Select/Coin duplication as the Neo Geo LLAPI 1.0 driver.
        snes_pad = serial[15:12] == 4'hf
            ? ~{serial[11],serial[2],serial[2],serial[3],serial[9],serial[1],
                serial[8],serial[0],serial[4],serial[5],serial[6],serial[7]}
            : 12'd0;
    endfunction

    wire [5:0] md_in = {pins[6],pins[2],pins[3],pins[5],pins[0],pins[1]}; // C B R L D U
    reg [5:0] md_high = '1;
    reg [1:0] md_start_a = '1;
    reg [3:0] md_ext = '1; // Mode X Y Z
    reg md_valid = 0, md_six = 0;
    wire md_select = md_six ? !md_ext[3] : (!md_high[1] && !md_start_a[1]);
    wire md_start = !md_start_a[1] && (md_six || !md_select);
    wire [3:0] sat_in = {pins[3],pins[5],pins[0],pins[1]};
    reg [3:0] sat_extra = '1, sat_main = '1, sat_dir = '1;

    always @(posedge clk) begin
        last_mode <= mode;
        if (!scanning) begin
            report_ready <= 0;
            ticks <= 0;
            phase <= 0;
            drive <= 7'h7f;
            first <= 0;
            second <= 0;
        end else if (ticks == TICK_CYCLES-1) begin
            ticks <= 0;
            phase <= phase == SCAN_TICKS-1 ? 0 : phase + 1'b1;
            case (mode)
                MD: case (phase) // TH on USER4; all other lines remain inputs.
                    0: begin drive <= 7'h6f; md_six <= 0; end
                    1: drive[4] <= 1;
                    2: begin md_high <= md_in; drive[4] <= 0; end
                    3: begin
                        md_start_a <= md_in[5:4];
                        md_valid <= md_in[3:2] == 0;
                        drive[4] <= 1;
                    end
                    4: drive[4] <= 0;
                    5: begin md_six <= md_in[3:0] == 0; drive[4] <= 1; end
                    6: begin md_ext <= md_in[3:0]; drive[4] <= 0; end
                    7: begin
                        report_ready <= 1;
                        drive[4] <= 1;
                        first <= md_valid ? {1'b0, md_select, md_select, md_start,
                            md_six && !md_ext[2], !md_high[5], !md_high[4], !md_start_a[0],
                            !md_high[0], !md_high[1], !md_high[2], !md_high[3]} : 12'd0;
                    end
                endcase
                SNES: begin // Shared latch USER0, P1 clock/data USER1/5, P2 USER3/6.
                    if (phase <= 1) drive <= 7'h7f;
                    if (phase == 2) drive[0] <= 0;
                    if (phase >= 3 && phase <= 33 && phase[0]) begin
                        snes1[(phase-3)>>1] <= pins[5];
                        snes2[(phase-3)>>1] <= pins[6];
                        drive[1] <= 0;
                        drive[3] <= 0;
                    end
                    if (phase >= 4 && phase <= 34 && !phase[0]) begin
                        drive[1] <= 1;
                        drive[3] <= 1;
                    end
                    if (phase == 35) begin
                        report_ready <= 1;
                        first <= snes_pad(snes1);
                        second <= snes_pad(snes2);
                    end
                end
                SATURN: case (phase) // TH=USER4, TR=USER6, TL=USER2 input.
                    0: drive <= 7'h2f;
                    1: begin sat_extra <= sat_in; drive[4] <= 1; end // R X Y Z
                    2: begin sat_main <= sat_in; drive[4] <= 0; drive[6] <= 1; end // Start A C B
                    3: begin sat_dir <= sat_in; drive[4] <= 1; end // R L D U
                    4: begin
                        report_ready <= 1;
                        // Digital pad ID {L,1,0,0}. A disconnected or analog
                        // pad releases all game inputs on the next scan.
                        first <= sat_in[2:0] == 3'b100
                            ? ~{sat_extra[3],sat_in[3],sat_in[3],sat_main[3],
                                sat_extra[2],sat_main[1],sat_main[0],sat_main[2],
                                sat_dir[0],sat_dir[1],sat_dir[2],sat_dir[3]}
                            : 12'd0;
                    end
                endcase
            endcase
        end else ticks <= ticks + 1'b1;
    end
endmodule
