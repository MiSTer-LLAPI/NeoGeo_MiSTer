`timescale 1ns/1ps
// Exercise the same eight-word GET_STATUS / SET_STATUS2 exchange as MiSTer Main.
module autofire_hps_tb;
    reg clk = 0, reset = 1;
    always #5 clk = !clk;
    reg enabled = 0, strobe = 0;
    reg [15:0] data = 0;
    wire [45:0] bus;
    wire [35:0] ext;
    assign bus[35:33] = {1'b0, enabled, strobe};
    assign bus[31:16] = data;
    assign ext[32] = 0;

    wire [127:0] status, request;
    wire status_set;
    hps_io #(.CONF_STR("NEOGEO;;"), .WIDE(1), .VDNUM(2)) bridge(
        .clk_sys(clk), .HPS_BUS(bus), .EXT_BUS(ext), .status(status),
        .status_in(request), .status_set(status_set)
    );

    reg [3:0] gesture1 = 0, gesture2 = 0;
    wire [1:0] mode1, mode2, button1, button2;
    neogeo_autofire_settings settings(
        .clk(clk), .reset(reset), .status(status), .gesture1(gesture1), .gesture2(gesture2),
        .mode1(mode1), .mode2(mode2), .button1(button1), .button2(button2),
        .status_in(request), .status_set(status_set)
    );

    task transfer(input [15:0] word_in, output [15:0] word_out);
        @(negedge clk);
        enabled = 1; strobe = 1; data = word_in;
        @(negedge clk);
        word_out = bus[15:0];
        strobe = 0;
    endtask

    task deselect;
        enabled = 0;
        @(negedge clk);
    endtask

    task send_status(input [127:0] value);
        reg [15:0] unused;
        transfer(16'h1e, unused);
        for (int i = 0; i < 8; i++)
            transfer(value[16*i +: 16], unused);
        deselect();
    endtask

    task read_request(input [3:0] change_count, output [127:0] value);
        reg [15:0] response;
        transfer(16'h29, response);
        if (response !== {8'h00, 4'ha, change_count}) $fatal(1, "Wrong request counter %h", response);
        for (int i = 0; i < 8; i++) begin
            transfer(0, response);
            value[16*i +: 16] = response;
        end
        deselect();
    endtask

    task gesture(input [3:0] p1, input [3:0] p2);
        @(negedge clk);
        gesture1 = p1; gesture2 = p2;
        @(negedge clk);
        gesture1 = 0; gesture2 = 0;
    endtask

    reg [127:0] expected = 128'hac10_0673_8254_cf00_9532_2371_ace8_fff0;
    reg [127:0] readback, first_request;
    reg check_echo = 0;
    always @(posedge clk)
        if (check_echo && {mode1, button1, mode2, button2} !==
             {expected[67:66], expected[65:64], expected[73:72], expected[71:70]})
            $fatal(1, "Partial host echo changed the effective mode/button");

    initial begin
        expected[76] = 1; // The experimental speed selection shares this OSD word.
        expected[75:64] = {2'd1, 2'd0, 2'd0, 2'd2, 2'd0, 2'd0};
        send_status(expected);
        reset = 0;
        // Hold/A is in flight. Undo it before the host has even polled:
        // gameplay must immediately return to the original Off/A state.
        first_request = expected;
        first_request[67:66] = 1;
        gesture(4'b0001, 0);
        if ({mode1, button1} !== 4'b0100) $fatal(1, "First gesture delayed until host poll");
        gesture(4'b0001, 0);
        if ({mode1, button1} !== 4'b0000) $fatal(1, "Undo delayed until host poll");
        gesture(0, 4'b0010);
        {expected[73:72], expected[71:70]} = {2'd1, 2'd1};
        check_echo = 1;

        // Main must still be able to read the first untouched snapshot.
        read_request(1, readback);
        if (readback !== first_request) $fatal(1, "In-flight request overwritten by a later gesture");
        send_status(readback);
        if (status !== first_request) $fatal(1, "First host echo incomplete");

        // The second snapshot must retain the undo and the P2 change.
        read_request(2, readback);
        if (readback !== expected) $fatal(1, "Undo, P2 gesture or other status lost after stale echo");
        send_status(readback);
        if (status !== expected) $fatal(1, "Final host echo incomplete");
        check_echo = 0;

        // A manual P1 Toggle/C edit must be honored. Simultaneous gestures
        // then turn off P1/C and replace P2/B with P2/A in one snapshot.
        {expected[67:66], expected[65:64]} = {2'd2, 2'd2};
        send_status(expected);
        if ({mode1, button1} !== 4'b1010) $fatal(1, "Manual OSD edit was ignored");
        gesture(4'b0100, 4'b0001);
        {expected[67:66], expected[65:64]} = {2'd0, 2'd2};
        {expected[73:72], expected[71:70]} = {2'd1, 2'd0};
        check_echo = 1;
        read_request(3, readback);
        if (readback !== expected) $fatal(1, "Simultaneous requests did not merge");
        send_status(readback);
        if (status !== expected) $fatal(1, "Second host echo is incorrect");
        $display("PASS real HPS bridge: manual edit, delayed and simultaneous gestures, atomic echo, speeds and 128-bit status");
        $finish;
    end
endmodule
