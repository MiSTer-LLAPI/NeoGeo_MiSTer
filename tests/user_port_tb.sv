`timescale 1ns/1ps
module user_port_tb;
    reg clk = 0, reset = 1, game_reset = 0, vblank = 0, osd = 0;
    always #5 clk = !clk;
    reg [2:0] requested = 0;
    wire [3:0] gesture1, gesture2;
    wire [6:0] user_in = 7'h7f, llapi_out = 7'h29;
    wire [6:0] user_out;
    wire llapi_active, snac_active, db15_drive, snac_report_ready;
    wire [11:0] pad1, pad2;
    neogeo_user_port dut(.*);
    task released;
        begin
            #1;
            if ({user_out, llapi_active, snac_active, db15_drive, pad1, pad2} !== {7'h7f,27'd0})
                $fatal(1,"Pins or buttons active without a grant");
        end
    endtask
    task select_mode(input [2:0] target);
        begin
            @(negedge clk);
            requested = target;
            released;
            repeat (500) begin @(negedge clk); released; end
            repeat (15) @(negedge clk);
            if (llapi_active !== (target==0) || snac_active !== (target>=1 && target<=4) ||
                db15_drive !== (target==2)) $fatal(1,"Wrong USER I/O owner in mode %0d",target);
            if (target==0 && user_out!==llapi_out) $fatal(1,"LLAPI drive lost");
            if (target>4) released;
        end
    endtask
    reg [11:0] reader1 = 0, reader2 = 0;
    task frames(input integer count);
        repeat (count) begin
            @(negedge clk); vblank = 1;
            repeat (3) @(negedge clk);
            vblank = 0;
            repeat (3) @(negedge clk);
        end
    endtask
    // The pin-level tests cover the readers. Drive their complete reports here
    // to verify the gesture through the real mode multiplexer and output ports.
    reg [3:0] observed_gesture1 = 0, observed_gesture2 = 0;
    always @(posedge clk) begin
        if (gesture1 != 0) observed_gesture1 <= gesture1;
        if (gesture2 != 0) observed_gesture2 <= gesture2;
    end
    task test_autofire_route(input [2:0] target);
        begin
            select_mode(target);
            observed_gesture1 = 0;
            observed_gesture2 = 0;
            if (target == 2) begin
                force dut.db15_pad1 = reader1;
                force dut.db15_pad2 = reader2;
            end else begin
                force dut.serial_pad1 = reader1;
                force dut.serial_pad2 = reader2;
            end
            reader1 = 12'h010; reader2 = target==2 || target==3 ? 12'h020 : 0;
            frames(4);
            if (pad1 !== reader1 || pad2 !== reader2) $fatal(1,"Wrong raw pad in mode %d",target);
            repeat (3) begin
                reader1[8] = 1; frames(4);
                if (pad1[8]) $fatal(1,"Start leaked in mode %d",target);
                reader1[8] = 0; frames(4);
            end
            if (observed_gesture1 !== 4'b0001 || observed_gesture2 !== 0)
                $fatal(1,"Gesture routed to wrong button or player in mode %d",target);
            if (pad1 !== reader1 || pad2 !== reader2)
                $fatal(1,"Raw buttons changed after gesture in mode %d",target);
            reader1 = 0; #1;
            if (pad1 !== 0) $fatal(1,"Fire stuck in mode %d",target);
            release dut.db15_pad1; release dut.db15_pad2;
            release dut.serial_pad1; release dut.serial_pad2;
            reader2 = 0;
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        select_mode(0);
        select_mode(2);
        osd = 1;
        released;
        repeat (8) @(negedge clk);
        requested = 1;
        released;
        osd = 0;
        select_mode(1);
        select_mode(3);
        select_mode(4);
        select_mode(7);
        select_mode(2);
        reset = 1;
        released;
        repeat (3) @(negedge clk);
        reset = 0;
        select_mode(0);
        test_autofire_route(1);
        test_autofire_route(2);
        test_autofire_route(3);
        test_autofire_route(4);
        select_mode(0);
        $display("PASS exclusive USER I/O grants, LLAPI default, reset, OSD and released transitions");
        $finish;
    end
endmodule
