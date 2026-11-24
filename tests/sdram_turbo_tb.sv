`timescale 1ns/1ps
module sdram_turbo_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg nreset = 0, turbo = 0, ready = 1, sprite = 1, fix = 1, nromoe = 1, nas = 1;
    wire rd, rom_ready;
    reg [15:0] din = 0;
    wire [15:0] rom_data, fix_data;
    wire [25:0] addr;
    localparam [25:0] ROM_ADDR = 26'h100123, C_ADDR = 26'h567890, S_ADDR = 26'h40001;
    sdram_mux dut (
        .CLK(clk), .nRESET(nreset), .cpu_turbo(turbo), .SYSTEM_CDx(1'b0), .nSYSTEM_G(1'b1),
        .M68K_ADDR(20'h00123), .nROMOE(nromoe), .nSROMOE(1'b1), .nPORTOE(1'b1), .nAS(nas),
        .nLDS(1'b0), .nUDS(1'b0), .PCK1(sprite), .PCK2(fix), .CROM_ADDR({C_ADDR,1'b0}),
        .S_LATCH(16'd0), .FIX_BANK(2'd0), .SPR_EN(1'b1), .FIX_EN(1'b1), .REFRESH_EN(1'b0),
        .SDRAM_READY(ready), .SDRAM_RD(rd), .SDRAM_ADDR(addr), .SDRAM_DOUT(din),
        .PROM_DATA(rom_data), .PROM_DATA_READY(rom_ready), .SROM_DATA(fix_data),
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
    task exercise(input mode);
        begin
            nreset = 0;
            turbo = mode;
            sprite = 1;
            fix = 1;
            nromoe = 1;
            nas = 1;
            repeat (4) tick;
            nreset = 1;
            tick;
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
    initial begin
        exercise(0);
        exercise(1);
        exercise(0);
        $display("PASS simultaneous program, sprite and FIX requests: native, turbo, native");
        $finish;
    end
endmodule
