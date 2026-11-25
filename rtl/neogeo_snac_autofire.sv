// One native Neo Geo pad: combo, coin, select, Start, D/C/B/A, directions.
module neogeo_snac_autofire (
    input clk, reset, active, vblank,
    input  [11:0] pad_in,
    output [11:0] pad_out,
    output reg [3:0] gesture = 0
);
    wire [3:0] actions = pad_in[7:4];
    wire start = pad_in[8];
    wire single_action = (actions == 1 || actions == 2 || actions == 4 || actions == 8);
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
    always @(posedge clk) begin
        last_vblank <= vblank;
        gesture <= 0;
        if (reset || !active) begin
            last_actions <= 0;
            last_start <= 0;
            swallow_start <= 0;
            valid_press <= 0;
            taps <= 0;
            sampled_down <= 0;
            stable_down <= 0;
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
                        gesture <= actions;
                    end else taps <= taps + 1'b1;
                end
            end
        end
    end

    assign pad_out = (active && !reset) ?
        {pad_in[11:9], game_start, actions, pad_in[3:0]} : 12'd0;
endmodule

// Repeat one action on the logical player port. Cabinet controls and
// the other three actions pass through.
module neogeo_menu_autofire (
    input clk, reset, osd, vblank, report_ready,
    input [1:0] mode, speed, button,
    input [11:0] pad_in,
    output [11:0] pad_out
);
    localparam [1:0] HOLD = 1, TOGGLE = 2;
    wire [3:0] actions = pad_in[7:4];
    wire action = actions[button];
    reg last_vblank = 0, last_action = 0, ready = 0;
    reg toggled = 0;
    reg [1:0] last_mode = 0, last_speed = 0, last_button = 0;
    reg [2:0] phase = 0;
    wire changed = mode != last_mode || speed != last_speed || button != last_button;
    wire [2:0] half_period = speed == 1 ? 3'd4 : speed == 2 ? 3'd1 : 3'd2;
    wire [2:0] last_phase = speed == 1 ? 3'd7 : speed == 2 ? 3'd1 : 3'd3;
    wire repeating = mode == HOLD ? action : mode == TOGGLE && toggled;

    always @(posedge clk) begin
        last_vblank <= vblank;
        last_action <= action;
        last_mode <= mode;
        last_speed <= speed;
        last_button <= button;
        if (reset || osd || changed || !report_ready) ready <= 0;
        else if (!action) ready <= 1;

        if (reset || mode != last_mode || button != last_button || mode != TOGGLE) toggled <= 0;
        else if (!osd && report_ready && ready && action && !last_action) toggled <= !toggled;

        if (reset || osd || changed || !repeating) phase <= 0;
        else if (vblank && !last_vblank)
            phase <= phase == last_phase ? 3'd0 : phase + 3'd1;
    end

    wire menu_enabled = mode == HOLD || mode == TOGGLE;
    wire fire = (menu_enabled && !osd && !reset) ? repeating && phase < half_period : action;
    wire [3:0] selected = 4'b0001 << button;
    wire [3:0] filtered = (actions & ~selected) | (fire ? selected : 4'b0);
    assign pad_out = {pad_in[11:8], filtered, pad_in[3:0]};
endmodule

// Merge gesture updates into the HPS menu status without changing speed
// or unrelated options. Apply a gesture locally while the host reflects it.
module neogeo_autofire_settings (
    input clk, reset,
    input [127:0] status,
    input [3:0] gesture1, gesture2,
    output [1:0] mode1, mode2, button1, button2,
    output reg [127:0] status_in,
    output status_set
);
    wire [3:0] host [0:1];
    // MiSTer echoes status in 16-bit writes. Keep both players in word 4
    // so a new mode can never appear alongside the previous button.
    assign host[0] = status[67:64];
    assign host[1] = status[73:70];
    wire [3:0] gesture [0:1];
    assign gesture[0] = gesture1;
    assign gesture[1] = gesture2;
    wire [3:0] effective [0:1];
    wire [3:0] updated [0:1];
    wire [1:0] waiting_for_echo;
    reg last_status_set = 0;
    always @(posedge clk) last_status_set <= status_set;


    genvar p;
    generate
    for (p = 0; p < 2; p = p + 1) begin : player
        reg local_selection = 0, awaiting = 0;
        reg [3:0] requested = 0, submitted = 0;
        assign waiting_for_echo[p] = awaiting && host[p] != submitted;
        wire [1:0] target = gesture[p][3] ? 2'd3 : gesture[p][2] ? 2'd2 :
                            gesture[p][1] ? 2'd1 : 2'd0;
        assign effective[p] = local_selection ? requested : host[p];
        wire same_active = effective[p][1:0] == target &&
                           (effective[p][3:2] == 1 || effective[p][3:2] == 2);
        assign updated[p] = |gesture[p] ? {same_active ? 2'd0 : 2'd1, target} : effective[p];

        always @(posedge clk) begin
            if (reset) begin
                local_selection <= 0;
                awaiting <= 0;
            end else begin
                if (|gesture[p]) begin
                    requested <= updated[p];
                    local_selection <= 1;
                end else if (!waiting_for_echo[p] && host[p] == requested) begin
                    local_selection <= 0;
                end

                if (status_set) begin
                    submitted <= updated[p];
                    awaiting <= updated[p] != host[p];
                end else if (!waiting_for_echo[p]) begin
                    awaiting <= 0;
                end
            end
        end
    end

    endgenerate

    assign {mode1, button1} = effective[0];
    assign {mode2, button2} = effective[1];
    // Main owns a single request slot. If a new gesture arrives while its
    // previous echo is in flight, apply it locally and send the latest
    // selection once the slot is free. hps_io detects a rising strobe.
    assign status_set = !reset && !last_status_set && !(|waiting_for_echo) &&
                        (updated[0] != host[0] || updated[1] != host[1]);
    always @* begin
        status_in = status;
        status_in[67:64] = updated[0];
        status_in[73:70] = updated[1];
    end
endmodule
