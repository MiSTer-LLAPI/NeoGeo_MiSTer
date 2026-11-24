`timescale 1ns/1ps
module snac_autofire_tb;
    localparam [11:0] A = 12'h010, B = 12'h020, C = 12'h040, D = 12'h080;
    localparam [11:0] START = 12'h100, OTHER = 12'he0f;
    reg clk = 0, reset = 1, active = 0, vblank = 0;
    always #5 clk = !clk;
    reg [11:0] raw [0:1];
    wire [11:0] pad [0:1];
    genvar p;
    for (p=0; p<2; p=p+1) begin : player
        neogeo_snac_autofire #(.HALF_PERIOD_FRAMES(2)) dut(
            .clk(clk), .reset(reset), .active(active), .vblank(vblank),
            .pad_in(raw[p]), .pad_out(pad[p]));
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
    task pulsing(input integer player_id, input [11:0] button_mask);
        integer i, on_frames, transitions, previous_edge;
        reg [11:0] sample, previous;
        begin
            on_frames=0; transitions=0; previous_edge=0;
            for (i=0; i<12; i=i+1) begin
                frame;
                sample=pad[player_id] & button_mask;
                if (sample !== 0 && sample !== button_mask)
                    $fatal(1,"Undefined autofire output");
                if (sample == button_mask) on_frames=on_frames+1;
                if (i && sample != previous) begin
                    if (transitions && i-previous_edge != 2)
                        $fatal(1,"Wrong P%0d pulse width at frame %0d", player_id+1, i);
                    transitions=transitions+1; previous_edge=i;
                end
                previous=sample;
            end
            if (on_frames != 6 || transitions < 5)
                $fatal(1,"P%0d button %h expected 2 frames on / 2 off; %0d on, %0d edges",
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

        raw[0]=A | OTHER; raw[1]=A;
        check_pad(0, 12'hfff, A | OTHER, "Immediate manual press");
        repeat (4) frame;
        // A single-frame glitch must not count as an extra tap.
        raw[0]=A | OTHER | START; frame;
        raw[0]=A | OTHER; repeat (4) frame;
        tap(0); tap(0);
        steady(0, 12'hfff, A | OTHER, "Two complete taps");
        raw[0]=A | OTHER | START;
        repeat (4) frame;
        raw[0]=A | OTHER; frame;
        raw[0]=A | OTHER | START;
        repeat (16) begin frame; check_pad(0, 12'hfff, A | OTHER, "Third tap held"); end
        raw[0]=A | OTHER; repeat (4) frame;
        pulsing(0,A);
        check_pad(0,OTHER,OTHER,"Autofire changed other buttons");
        steady(1,A,A,"P1 programming affected P2");
        release_pad(0);
        raw[0]=A;
        check_pad(0,A,A,"New turbo press should fire immediately");
        pulsing(0,A);

        // Configure a second action independently, then turn only A off.
        release_pad(0);
        raw[0]=B; repeat (4) frame;
        repeat (3) tap(0);
        pulsing(0,B);
        raw[0]=A | B | C;
        repeat (6) frame;
        raw[0]=A | B | C | START;
        steady(0,12'hfff,raw[0],"Turbo masks damaged UniBIOS combo");
        release_pad(0);
        raw[0]=A; repeat (4) frame;
        repeat (3) tap(0);
        raw[0]=A | B;
        steady(0,A,A,"Disabling autofire on A");
        pulsing(0,B);
        release_pad(0);

        // Two taps on C cannot carry over to D. Releasing the action before
        // releasing Start must neither count the tap nor leak a Start press.
        raw[0]=C; repeat (4) frame;
        tap(0); tap(0);
        raw[0]=D; repeat (4) frame;
        tap(0);
        steady(0,12'hfff,D,"Changed target between taps");
        raw[0]=D | START; repeat (4) frame;
        raw[0]=START;
        steady(0,12'hfff,0,"Cancelled chord leaked held Start");
        release_pad(0);
        raw[0]=D; repeat (4) frame;
        repeat (3) tap(0);
        pulsing(0,D);
        release_pad(0);

        // Interrupt a partial P2 gesture while keeping a programmed P1 button.
        raw[1]=C; repeat (4) frame;
        tap(1); tap(1);
        active=0; raw[0]=B;
        steady(0,12'hfff,0,"Inactive input leaked");
        active=1; repeat (4) frame;
        tap(1);
        steady(1,12'hfff,C,"Partial sequence survived inactive interval");
        pulsing(0,B);
        tap(1); tap(1);
        pulsing(1,C);

        // A reset (also used for a USER I/O mode change) clears both players.
        raw[0]=0; raw[1]=0; active=0; reset=1;
        repeat (4) frame;
        reset=0; active=1; raw[0]=B; raw[1]=C;
        steady(0,12'hfff,B,"P1 turbo survived reset");
        steady(1,12'hfff,C,"P2 turbo survived reset");

        $display("PASS SNAC triple-Start, stable edges, independent buttons/players, cadence, release, OSD and reset");
        $finish;
    end
endmodule
