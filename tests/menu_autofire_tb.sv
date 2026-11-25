`timescale 1ns/1ps
module menu_autofire_tb;
    reg clk = 0, reset = 1, osd = 0, vblank = 0;
    always #5 clk = !clk;
    reg [1:0] mode1 = 0, mode2 = 0, speed1 = 0, speed2 = 0;
    reg [1:0] button1 = 0, button2 = 0;
    reg [11:0] raw1 = 0, raw2 = 0;
    wire [11:0] pad1, pad2;
    reg report_ready = 1;
    neogeo_menu_autofire p1(clk, reset, osd, vblank, report_ready, mode1, speed1, button1, raw1, pad1);
    neogeo_menu_autofire p2(clk, reset, osd, vblank, report_ready, mode2, speed2, button2, raw2, pad2);

    task settle;
        repeat (3) @(negedge clk);
    endtask
    task frame;
        begin
            vblank = 1; settle();
            vblank = 0; settle();
        end
    endtask

    integer rate, ticks, count;
    initial begin
        settle();
        reset = 0;
        raw1 = 12'hfff; settle();
        if (pad1 !== raw1) $fatal(1, "Off must preserve all controls");
        button1 = 2; mode1 = 1;
        for (rate = 0; rate < 3; rate = rate + 1) begin
            speed1 = rate[1:0]; settle();
            ticks = rate == 0 ? 4 : rate == 1 ? 8 : 2;
            count = 0;
            repeat (ticks) begin
                frame();
                if (pad1[6]) count = count + 1;
                if ((pad1 & 12'hfbf) !== 12'hfbf || pad2 !== 0)
                    $fatal(1, "Only P1 C may be affected");
            end
            if (count != ticks / 2) $fatal(1, "Incorrect repeat rate");
        end
        raw1 = 0; settle();
        if (pad1 !== 0) $fatal(1, "Hold must stop on release");

        button2 = 3; mode2 = 2; settle();
        raw2 = 12'h080; settle();
        raw2 = 0; settle();
        if (!pad2[7] || pad1 !== 0) $fatal(1, "P2 D must toggle independently");
        frame(); frame();
        if (pad2[7]) $fatal(1, "Toggle must pulse");
        osd = 1; settle();
        if (pad2 !== 0) $fatal(1, "No synthetic button in OSD");
        osd = 0; settle();
        if (!pad2[7]) $fatal(1, "Menu opening must preserve toggle");
        raw2 = 12'h080; settle();
        raw2 = 0; settle();
        if (pad2 !== 0) $fatal(1, "Second press must stop toggle");
        raw2 = 12'h080; settle();
        raw2 = 0; settle();
        button2 = 1; settle();
        if (pad2 !== 0) $fatal(1, "Changing selector must clear toggle");
        // Mimic a pad held throughout menu closure and a new reader scan.
        osd = 1; raw2 = 0; report_ready = 0; settle();
        osd = 0; settle();
        raw2 = 12'h020; report_ready = 1; settle();
        raw2 = 0; settle();
        if (pad2 !== 0) $fatal(1, "A held button from a new reader report toggled by itself");
        raw2 = 12'h020; settle();
        raw2 = 0; settle();
        if (!pad2[5]) $fatal(1, "First actual press after reader acquisition lost");
        $display("PASS menu autofire: selected button, speeds, Hold, Toggle, independent players and OSD");
        $finish;
    end
endmodule
