// One native Neo Geo pad: combo, coin, select, Start, D/C/B/A, directions.
module neogeo_snac_autofire #(
    parameter integer HALF_PERIOD_FRAMES = 2
) (
    input clk, reset, active, vblank,
    input  [11:0] pad_in,
    output [11:0] pad_out
);
    wire [3:0] actions = pad_in[7:4];
    wire start = pad_in[8];
    wire single_action = actions == 4'b0001 || actions == 4'b0010 ||
                         actions == 4'b0100 || actions == 4'b1000;
    reg last_vblank, last_start;
    reg [3:0] last_actions;
    wire frame_tick = vblank && !last_vblank;

    reg swallow_start, valid_press;
    // Decide how to route Start on its leading edge. Changing the other
    // buttons while holding Start must never leak the end of a gesture to
    // the game, or swallow an ordinary Start or a multi-button BIOS chord.
    wire action_held = single_action && actions == last_actions;
    wire hide_start = last_start ? swallow_start : action_held;
    wire game_start = start && !hide_start;
    wire gesture_down = start && action_held && (!last_start || valid_press);
    reg sampled_down, stable_down;
    reg [1:0] taps;
    reg [3:0] turbo;
    always @(posedge clk) begin
        last_vblank <= vblank;
        if (reset || !active) begin
            last_actions <= 0;
            last_start <= 0;
            swallow_start <= 0;
            valid_press <= 0;
            taps <= 0;
            sampled_down <= 0;
            stable_down <= 0;
            // The OSD temporarily stops polling. Preserve the settings
            // until a reset or a change of USER I/O mode.
            if (reset) turbo <= 0;
        end else begin
            last_actions <= actions;
            last_start <= start;
            if (start && !last_start) begin
                swallow_start <= action_held;
                valid_press <= action_held;
            end else if (!start || actions != last_actions) begin
                valid_press <= 0;
            end

            if (!single_action || actions != last_actions) begin
                taps <= 0;
                sampled_down <= 0;
                stable_down <= 0;
            end else if (frame_tick) begin
                // Two equal frame samples debounce both halves of each tap.
                // Toggle on the third release while the same action is held.
                sampled_down <= gesture_down;
                if (gesture_down && sampled_down) stable_down <= 1;
                if (!start && !sampled_down && stable_down) begin
                    stable_down <= 0;
                    if (taps == 2) begin
                        taps <= 0;
                        turbo <= turbo ^ actions;
                    end else taps <= taps + 1'b1;
                end
            end
        end
    end

    localparam PERIOD_FRAMES = 2 * HALF_PERIOD_FRAMES;
    localparam PHASE_BITS = $clog2(PERIOD_FRAMES);
    wire [3:0] fire;
    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : button
        reg [PHASE_BITS-1:0] phase;
        always @(posedge clk) begin
            if (reset || !active || !actions[i] || !turbo[i]) phase <= 0;
            else if (frame_tick) begin
                if (phase == PERIOD_FRAMES-1) phase <= 0;
                else phase <= phase + 1'b1;
            end
        end
        assign fire[i] = actions[i] && (!turbo[i] || phase < HALF_PERIOD_FRAMES);
    end endgenerate

    // A Start chord forwarded to the game needs every held button, even if
    // that button's autofire happens to be in its off phase.
    assign pad_out = (active && !reset) ?
        {pad_in[11:9], game_start, game_start ? actions : fire, pad_in[3:0]} : 12'd0;
endmodule
