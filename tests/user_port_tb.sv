`timescale 1ns/1ps
module user_port_tb;
    reg clk = 0, reset = 1, osd = 0;
    always #5 clk = !clk;
    reg [2:0] requested = 0;
    wire [6:0] user_in = 7'h7f, llapi_out = 7'h29;
    wire [6:0] user_out;
    wire llapi_active, snac_active, db15_drive;
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
        $display("PASS exclusive USER I/O grants, LLAPI default, reset, OSD and released transitions");
        $finish;
    end
endmodule
