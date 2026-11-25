// Copyright 2026 Ricardo Saraiva aka RickDangerous (UltimateMiSTer.com)
// Bit timing follows the 1943 poll_tb and 1944 dual-port adapter fixtures.
// Only the ACK hold duration comes from the physical GamerPRO measurement.
`timescale 1ns/1ps
module receive_start_tb #(
    parameter bit EXTENDED_ACK = 1,
    parameter bit CHECK_NOISE = 0,
    parameter bit EXPECT_FIX = 1
);
    localparam integer FIRST_ACK_CLOCKS = EXTENDED_ACK ? 1310600 : 200;
    reg clk = 0, enable = 0;
    reg remote_latch = 1, remote_data = 1;
    wire host_latch, host_data, valid, update, fault;
    wire [7:0] controller_type;
    wire [31:0] buttons;
    wire [71:0] analog_data;
    always #10 clk = ~clk;

    // Same driver parameters as controller_llapi in the NeoGeo top level.
    LLAPI_Enhanced #(.IMMEDIATE_REPOLL(1), .EXTENDED_POLL_ACK(EXTENDED_ACK)) dut (
        .CLK_50M(clk), .LLAPI_SYNC(1'b0), .ENABLE(enable),
        .IO_LATCH_IN(host_latch & remote_latch), .IO_DATA_IN(host_data & remote_data),
        .IO_LATCH_OUT(host_latch), .IO_DATA_OUT(host_data),
        .STATUS_VALID(valid), .STATUS_UPDATE(update), .LINK_FAULT(fault),
        .LLAPI_TYPE(controller_type), .LLAPI_BUTTONS(buttons), .LLAPI_ANALOG(analog_data)
    );
    integer updates = 0, faults = 0;
    always @(posedge update) updates++;
    always @(posedge fault) faults++;

    task automatic ticks(input integer n);
        repeat (n) @(negedge clk);
    endtask

    task automatic expect_opcode(input [7:0] wanted);
        reg [7:0] decoded;
        @(negedge host_latch);
        ticks(251);
        for (int i = 0; i < 8; i++) begin
            decoded[i] = ~host_data;
            if (i < 7) ticks(224);
        end
        if (decoded !== wanted) $fatal(1, "expected opcode %h, got %h", wanted, decoded);
        @(posedge host_latch);
    endtask

    task automatic remote_reply(input [103:0] payload, input integer bytes);
        ticks(600);
        remote_latch = 0; remote_data = 1; ticks(100);
        for (int n = 0; n < bytes; n++) begin
            for (int i = 0; i < 8; i++) begin
                remote_data = 1; ticks(109);
                remote_data = ~payload[n*8+i]; ticks(115);
            end
            remote_data = 1; ticks(49); remote_data = 0; ticks(50);
        end
        remote_latch = 1; remote_data = 1;
    endtask

    task automatic poll_and_status(input integer ack_clocks, input bit fire);
        reg [103:0] payload;
        payload = 104'h0800008080808080800000001b;
        payload[8] = fire;
        expect_opcode(8'h00); ticks(152);
        remote_latch = 0; remote_data = 0; ticks(ack_clocks);
        remote_latch = 1; remote_data = 1;
        expect_opcode(8'h01); remote_reply(payload, 13);
        @(posedge update); @(negedge clk);
        if (!valid || controller_type !== 8'h1b || buttons !== {31'd0,fire} ||
            analog_data !== 72'h080000808080808080)
            $fatal(1, "wrong complete status: valid=%b id=%h buttons=%h analog=%h",
                   valid, controller_type, buttons, analog_data);
    endtask

    initial begin
        ticks(5); enable = 1;
        if (CHECK_NOISE) begin
            expect_opcode(8'h00); ticks(152);
            remote_latch = 0; remote_data = 0; ticks(500);
            repeat (10) begin
                remote_data = 1; ticks(1); remote_data = 0; ticks(4);
            end
            if (EXPECT_FIX) begin
                if (dut.state !== dut.STATE_READ_START || dut.count !== 0)
                    $fatal(1, "isolated highs qualified a transfer");
                remote_data = 1; ticks(9); remote_data = 0; ticks(4);
                if (dut.state !== dut.STATE_READ_START || dut.count !== 0)
                    $fatal(1, "nine consecutive highs qualified a transfer");
                if (updates || faults) $fatal(1, "noise caused an update or link fault");
                remote_latch = 1; remote_data = 1;
                expect_opcode(8'h01); remote_reply(104'h0800008080808080800000011b, 13);
                @(posedge update); @(negedge clk);
                if (!valid || controller_type !== 8'h1b || buttons !== 32'h1 || faults)
                    $fatal(1, "report after noisy ACK was lost or corrupted");
                expect_opcode(8'h21); remote_reply(104'd0, 1);
                expect_opcode(8'h00); ticks(152);
                remote_latch = 0; remote_data = 0; ticks(500);
                remote_data = 1; ticks(10); remote_data = 0; ticks(4);
                if (dut.state === dut.STATE_READ_START)
                    $fatal(1, "ten consecutive highs did not qualify");
            end else if (dut.state === dut.STATE_READ_START) begin
                $fatal(1, "1.0 baseline did not reproduce its false start");
            end
            if (updates != (EXPECT_FIX ? 1 : 0) || faults) $fatal(1, "unexpected publication or fault");
            $display("PASS receive qualification EXPECT_FIX=%0d EXTENDED_ACK=%0d", EXPECT_FIX, EXTENDED_ACK);
        end else begin
            poll_and_status(FIRST_ACK_CLOCKS, 1);
            expect_opcode(8'h21); remote_reply(104'd0, 1);
            poll_and_status(200, 0);
            poll_and_status(200, 1);
            if (faults) $fatal(1, "unexpected fault before unplug");
            expect_opcode(8'h00); // A disconnected adapter returns no ACK.
            @(posedge fault); @(negedge clk);
            if (valid || controller_type !== 0 || buttons !== 0)
                $fatal(1, "stale controls after unplug");
            poll_and_status(200, 0);
            if (updates != 4 || faults != 1)
                $fatal(1, "unexpected updates=%0d faults=%0d", updates, faults);
            $display("PASS EXTENDED_ACK=%0d first_ACK=%0d clocks, press/release/press, unplug, neutral reconnect",
                     EXTENDED_ACK, FIRST_ACK_CLOCKS);
        end
        $finish;
    end
    initial begin #80000000; $fatal(1, "wire test timed out"); end
endmodule
