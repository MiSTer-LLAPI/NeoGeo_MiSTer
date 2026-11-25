`timescale 1ns/1ps
module snac_autofire_tb;
    localparam [11:0] A = 12'h010, B = 12'h020, C = 12'h040, D = 12'h080;
    localparam [11:0] START = 12'h100, OTHER = 12'he0f;
    reg clk = 0, reset = 1, active = 0, vblank = 0;
    always #5 clk = !clk;
    reg [11:0] raw [0:1];
    wire [11:0] pad [0:1];
    wire [11:0] routed [0:1];
    wire [3:0] event_button [0:1];
    wire [1:0] mode [0:1], selected_button [0:1];
    localparam [127:0] INITIAL = (128'd1 << 127) | (128'd2 << 68) | (128'd1 << 74) | 128'h0001_a800_0000_0040;
    localparam [127:0] SELECTORS = (128'd15 << 64) | (128'd15 << 70);
    reg [127:0] host_status = INITIAL;
    wire [127:0] update_status;
    wire status_set;
    integer writes = 0;
    always @(posedge clk) if (status_set) begin
        writes <= writes + 1;
        host_status <= update_status;
    end
    neogeo_autofire_settings settings(
        .clk(clk), .reset(reset), .status(host_status),
        .gesture1(event_button[0]), .gesture2(event_button[1]),
        .mode1(mode[0]), .mode2(mode[1]), .button1(selected_button[0]), .button2(selected_button[1]),
        .status_in(update_status), .status_set(status_set)
    );
    wire [1:0] speed [0:1];
    assign speed[0] = host_status[69:68];
    assign speed[1] = host_status[75:74];
    for (genvar p=0; p<2; p=p+1) begin : player
        neogeo_snac_autofire dut(
            .clk(clk), .reset(reset), .active(active), .vblank(vblank),
            .pad_in(raw[p]), .pad_out(routed[p]), .gesture(event_button[p]));
        neogeo_menu_autofire menu(
            .clk(clk), .reset(reset), .osd(1'b0), .vblank(vblank), .report_ready(1'b1),
            .mode(mode[p]), .speed(speed[p]), .button(selected_button[p]),
            .pad_in(routed[p]), .pad_out(pad[p]));
    end

    // A multi-clock VBlank must only advance the repeat rate once.
    task frame;
        begin
            @(negedge clk); vblank = 1;
            repeat (4) @(negedge clk);
            vblank = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    task check_pad(input integer player_id, input [11:0] mask, value, input string scenario);
        begin
            #1;
            if ((pad[player_id] & mask) !== (value & mask))
                $fatal(1,"%s: P%0d expected %h under mask %h, got %h",
                       scenario, player_id+1, value, mask, pad[player_id]);
        end
    endtask

    task steady(input integer player_id, input [11:0] mask, value, input string scenario);
        repeat (8) begin frame; check_pad(player_id, mask, value, scenario); end
    endtask

    // Check both duty cycle and time between edges without assuming starting phase.
    task pulsing(input integer player_id, input [11:0] button_mask, input integer half_period);
        integer i, on_frames, transitions, previous_edge;
        reg [11:0] sample, previous;
        begin
            on_frames=0; transitions=0; previous_edge=0;
            for (i=0; i<24; i=i+1) begin
                frame;
                sample=pad[player_id] & button_mask;
                if (sample !== 0 && sample !== button_mask)
                    $fatal(1,"Undefined autofire output");
                if (sample == button_mask) on_frames=on_frames+1;
                if (i && sample != previous) begin
                    if (transitions && i-previous_edge != half_period)
                        $fatal(1,"Wrong P%0d pulse width at frame %0d", player_id+1, i);
                    transitions=transitions+1; previous_edge=i;
                end
                previous=sample;
            end
            if (on_frames != 12 || transitions < (24 / half_period) - 1)
                $fatal(1,"P%0d button %h expected 50%% duty cycle; %0d on, %0d edges",
                       player_id+1, button_mask, on_frames, transitions);
        end
    endtask

    task tap(input integer player_id);
        begin
            raw[player_id] = raw[player_id] | START;
            check_pad(player_id, START, 0, "Start leaked at chord press");
            repeat (4) begin frame; check_pad(player_id, START, 0, "Start leaked while held"); end
            raw[player_id] = raw[player_id] & ~START;
            repeat (4) frame;
        end
    endtask

    task release_pad(input integer player_id);
        begin
            raw[player_id] = 0;
            check_pad(player_id, 12'hfff, 0, "Released input stuck");
            repeat (4) frame;
        end
    endtask

    initial begin
        raw[0]=0; raw[1]=0;
        repeat (4) frame;
        reset=0; active=1;
        repeat (4) frame;

        raw[0]=OTHER | START;
        check_pad(0, 12'hfff, raw[0], "Plain Start and other controls");
        steady(0, 12'hfff, raw[0], "Held plain Start");
        raw[0]=START | D;
        steady(0,12'hfff,START | D,"Start already held before the action");
        release_pad(0);
        raw[0]=A | B | C | START;
        steady(0, 12'hfff, raw[0], "UniBIOS multi-button chord");
        release_pad(0);

        // Unlike pressing Start AFTER holding the action, a simultaneous
        // Start+action report is an ordinary game chord, even if repeated.
        repeat (3) begin
            raw[0]=START | D;
            check_pad(0,12'hfff,START | D,"Simultaneous Start and action");
            repeat (4) frame;
            raw[0]=D;
            repeat (4) frame;
            release_pad(0);
        end
        raw[0]=D;
        steady(0,12'hfff,D,"Simultaneous chords inadvertently programmed turbo");
        release_pad(0);

        if (writes != 0) $fatal(1, "Ordinary chords must not update the OSD");
        raw[0]=A | OTHER; repeat (4) frame;
        raw[0]=A | OTHER | START; frame;
        raw[0]=A | OTHER; repeat (4) frame;
        tap(0); tap(0);
        if (writes != 0) $fatal(1, "Two taps and a glitch must not update the OSD");
        tap(0);
        if (host_status[67:66] != 1 || host_status[65:64] != 0)
            $fatal(1, "P1 A must select Hold in the OSD");
        pulsing(0,A,1);
        release_pad(0);

        raw[0]=B; repeat (4) frame; repeat (3) tap(0);
        if (host_status[67:66] != 1 || host_status[65:64] != 1)
            $fatal(1, "P1 B must replace A");
        pulsing(0,B,1);
        raw[0]=A|B; steady(0,A,A,"Previous button must pass through");
        raw[0]=B; repeat (4) frame;

        raw[1]=D; repeat (4) frame; tap(1); tap(1);
        active=0; repeat (4) frame; active=1; repeat (4) frame;
        tap(1);
        if (host_status[73:72] != 0) $fatal(1, "Partial P2 gesture survived interruption");
        tap(1); tap(1);
        if (host_status[73:72] != 1 || host_status[71:70] != 3)
            $fatal(1, "P2 D must independently select Hold");
        pulsing(1,D,4);
        repeat (3) tap(0);
        if (host_status[67:66] != 0 || host_status[73:72] != 1 || host_status[65:64] != 1)
            $fatal(1, "Repeating the same gesture must turn off only that player");
        steady(0,B,B,"P1 Off");
        pulsing(1,D,4);
        // Change P1 in the OSD and complete both SNAC gestures on the same
        // frame. Replace P1 Toggle/C with Hold/B and turn off P2 Hold/D.
        host_status[67:64] = 4'b1010;
        repeat (4) frame;
        repeat (3) begin
            raw[0] = B | START; raw[1] = D | START; repeat (4) frame;
            raw[0] = B; raw[1] = D; repeat (4) frame;
        end
        if (host_status[67:64] !== 4'b0101 || host_status[73:70] !== 4'b0011)
            $fatal(1,"Simultaneous gestures lost a player or ignored the menu change");
        if ((host_status & ~SELECTORS) !== (INITIAL & ~SELECTORS))
            $fatal(1, "Gesture changed speed or another menu option");
        $display("PASS SNAC gesture updates shared OSD, replaces button, toggles off and preserves speed and P1/P2");
        $finish;
    end
endmodule
