`timescale 1ns/1ps
module sdram_turbo_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg nreset = 0, turbo = 0, ready = 1, sprite = 1, fix = 1, nromoe = 1, nas = 1;
    reg refresh_en = 0;
    wire rd, rom_ready, refresh;
    reg [15:0] din = 0;
    wire [15:0] rom_data, fix_data;
    wire [25:0] addr;
    localparam [25:0] ROM_ADDR = 26'h100123, C_ADDR = 26'h567890, S_ADDR = 26'h40001;
    sdram_mux dut (
        .CLK(clk), .nRESET(nreset), .cpu_turbo(turbo), .SYSTEM_CDx(1'b0), .nSYSTEM_G(1'b1),
        .M68K_ADDR(20'h00123), .nROMOE(nromoe), .nSROMOE(1'b1), .nPORTOE(1'b1), .nAS(nas),
        .nLDS(1'b0), .nUDS(1'b0), .PCK1(sprite), .PCK2(fix), .CROM_ADDR({C_ADDR,1'b0}),
        .S_LATCH(16'd0), .FIX_BANK(2'd0), .SPR_EN(1'b1), .FIX_EN(1'b1), .REFRESH_EN(refresh_en),
        .SDRAM_READY(ready), .SDRAM_RD(rd), .SDRAM_ADDR(addr), .SDRAM_DOUT(din),
        .PROM_DATA(rom_data), .PROM_DATA_READY(rom_ready), .SROM_DATA(fix_data), .SDRAM_RFSH(refresh),
        .DL_EN(1'b0), .DL_WR(1'b0), .DMA_RUNNING(1'b0), .CD_EXT_WR(1'b0), .CD_EXT_RD(1'b0),
        .CD_USE_SPR(1'b0), .CD_USE_FIX(1'b0), .CD_TR_RD_SPR(1'b0), .CD_TR_RD_FIX(1'b0),
        .CD_TR_WR_SPR(1'b0), .CD_TR_WR_FIX(1'b0)
    );
    task tick;
        begin @(posedge clk); #1; end
    endtask
    task reply(input [25:0] expected, input [15:0] value);
        begin
            if (rd !== 1'b1 || addr !== expected)
                $fatal(1, "Unexpected SDRAM transaction, wanted %h, got %h (rd=%b)",expected,addr,rd);
            ready = 0;
            tick;
            if (rd !== 0) $fatal(1,"Read strobe repeated while memory busy");
            din = value;
            ready = 1;
            tick;
        end
    endtask
    task reset_mux(input mode);
        begin
            nreset = 0;
            turbo = mode;
            sprite = 1;
            fix = 1;
            nromoe = 1;
            nas = 1;
            ready = 1;
            refresh_en = 0;
            repeat (4) tick;
            nreset = 1;
            tick;
        end
    endtask
    task exercise(input mode);
        begin
            reset_mux(mode);
            sprite = 0;
            fix = 0;
            nromoe = 0;
            nas = 0;
            tick;
            if (mode) begin
                reply(C_ADDR,16'hcccc);
                reply(S_ADDR,16'hffff);
                if (rom_ready !== 0) $fatal(1,"CPU acknowledged before program word arrived");
                reply(ROM_ADDR,16'h1234);
            end else begin
                reply(ROM_ADDR,16'h1234);
                reply(C_ADDR,16'hcccc);
                reply(S_ADDR,16'hffff);
            end
            if (rd !== 0 || rom_ready !== 1 || rom_data !== 16'h1234 || fix_data !== 16'hffff)
                $fatal(1,"Missing, duplicate or misdirected response");
            nas = 1;
            nromoe = 1;
            tick;
            if (rom_ready !== 0) $fatal(1,"Stale CPU response");
        end
    endtask
    task reset_during_fetch(input mode);
        begin
            reset_mux(mode);
            nromoe = 0; nas = 0; tick;
            reply(ROM_ADDR, 16'h1111);
            if (rom_ready !== 1) $fatal(1,"Missing response before reset");
            // Reset & Apply may interrupt the CPU before AS has risen.
            nreset = 0; tick;
            nromoe = 1; nas = 1; repeat (4) tick;
            nreset = 1; tick;
            nromoe = 0; nas = 0; tick;
            if (rom_ready !== 0) $fatal(1,"Stale vector read across reset");
            reply(ROM_ADDR, 16'h2222);
            if (rom_ready !== 1 || rom_data !== 16'h2222) $fatal(1,"Missing new vector data");
        end
    endtask
    task refresh_edge;
        begin
            sprite = 1; tick;
            sprite = 0; tick;
        end
    endtask
    task check_refresh_rate(input mode, input contend);
        reg expected;
        integer edge_num;
        begin
            reset_mux(mode);
            refresh_en = 1;
            expected = refresh;
            for (edge_num=1; edge_num<=32; edge_num=edge_num+1) begin
                sprite = 1; tick;
                sprite = 0;
                if (contend) begin nromoe = 0; nas = 0; end
                tick;
                if (!(edge_num % 2)) begin
                    expected = !expected;
                    if (contend) begin
                        if (rd !== 0) $fatal(1,"CPU preempted a due refresh");
                        tick;
                    end
                end
                if (refresh !== expected) $fatal(1,"Incorrect refresh cadence on edge %d", edge_num);
                if (contend) begin
                    reply(ROM_ADDR,16'h1000+edge_num);
                    if (rom_data !== 16'h1000+edge_num || rom_ready !== 1) $fatal(1,"Lost program read");
                    nromoe = 1; nas = 1;
                end
                repeat (24) tick;
                if (refresh !== expected) $fatal(1,"Duplicate refresh");
            end
        end
    endtask
    task refresh_across_blanking;
        reg before_refresh;
        begin
            reset_mux(1);
            refresh_en = 1; ready = 0;
            before_refresh = refresh;
            // Several eligible edges while unavailable coalesce to one service.
            repeat (4) refresh_edge;
            if (refresh !== before_refresh) $fatal(1,"Refresh issued while memory busy");
            sprite = 1; tick;
            refresh_en = 0; sprite = 0; fix = 0; nromoe = 0; nas = 0; ready = 1; tick;
            reply(C_ADDR,16'h3333);
            if (refresh !== before_refresh) $fatal(1,"Refresh preempted FIX");
            reply(S_ADDR,16'h4444);
            if (refresh === before_refresh || rd !== 0) $fatal(1,"Deferred refresh lost at blanking end");
            tick;
            reply(ROM_ADDR,16'h5555);
            repeat (12) tick;
            if (refresh === before_refresh || rom_ready !== 1 || rom_data !== 16'h5555)
                $fatal(1,"Duplicate refresh or lost program data after blanking");
        end
    endtask
    initial begin
        exercise(0);
        exercise(1);
        exercise(0);
        reset_during_fetch(0);
        reset_during_fetch(1);
        check_refresh_rate(0,0);
        check_refresh_rate(1,0);
        check_refresh_rate(1,1);
        refresh_across_blanking;
        $display("PASS video arbitration, clean restart, native refresh rate and contended turbo refresh");
        $finish;
    end
endmodule
