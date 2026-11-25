// Exercise the real C1 command latch / DTACK and D0 NMI from both bus sides.
module sound_guard_tb;
    bit clk, reset = 1, turbo = 1, cd = 0;
    always #5 clk = ~clk;
    bit [23:0] address = 0;
    bit [7:0] wd = 0, zd = 0;
    tri [7:0] bus;
    bit nas = 1, nuds = 1, nlds = 1, rw = 1;
    bit [15:0] za = 0;
    bit nrd = 1, nwr = 1, nmreq = 1, niorq = 1;
    wire [7:0] command;
    wire nSDW, nSDZ80R, nSDZ80W, nSDZ80CLR, nZRAMCS, nSDMWR, nmi, raw_dtack, stall;
    wire board_ndtack = raw_dtack | stall;
    assign bus = rw ? 8'bz : wd;

    neo_c1 c1 (.CLK(clk), .reset(reset), .turbo_cart(turbo && !cd), .tick_4m(1'b1),
        .z80_ram_write(!nZRAMCS && !nSDMWR), .z80_port_write(!niorq && !nwr),
        .z80_addr(za), .sound_wait(stall), .M68K_ADDR(address[21:17]),
        .A22Z(address[22]), .A23Z(address[23]), .M68K_DATA(bus),
        .nUDS(nuds), .nLDS(nlds), .RW(rw), .nAS(nas), .SYSTEM_TYPE({cd,1'b0}),
        .SDD_WR(zd), .SDD_RD(command), .nSDZ80R(nSDZ80R), .nSDZ80W(nSDZ80W),
        .nSDZ80CLR(nSDZ80CLR), .nSDW(nSDW), .nDTACK(raw_dtack),
        .CLK_EN_68K_P(1'b1), .nROMWAIT(1'b1), .nPWAIT0(1'b1), .nPWAIT1(1'b1), .PDTACK(1'b1));
    defparam c1.sound_guard.TIMEOUT_BITS = 8;

    z80ctrl d0 (.CLK(clk), .SDA_L(za[4:2]), .SDA_U(za[15:11]), .nSDRD(nrd),
        .nSDWR(nwr), .nMREQ(nmreq), .nIORQ(niorq), .nSDW(nSDW), .nRESET(!reset),
        .nZ80NMI(nmi), .nSDZ80R(nSDZ80R), .nSDZ80W(nSDZ80W), .nSDZ80CLR(nSDZ80CLR),
        .nZRAMCS(nZRAMCS), .nSDMWR(nSDMWR));

    integer strobes = 0, interrupts = 0;
    reg sampled_nSDW = 1;
    always @(posedge clk) begin
        sampled_nSDW <= nSDW;
        if (sampled_nSDW && !nSDW && !reset) strobes++;
    end
    always @(negedge nmi) if (!reset) interrupts++;
    task tick; begin @(posedge clk); #1; end endtask

    task zwrite(input bit mem, input [15:0] addr, input [7:0] data);
        begin
            za=addr; zd=data; nwr=0; nmreq=!mem; niorq=mem;
            repeat (3) tick();
            nwr=1; nmreq=1; niorq=1; repeat (2) tick();
        end
    endtask
    task zread; begin
        za=0; nrd=0; niorq=0; repeat (3) tick();
        nrd=1; niorq=1; repeat (2) tick();
    end endtask
    task begin_write(input [7:0] data); begin
        address=24'h320000; wd=~data; nas=0; rw=0; tick();
        wd=data; nuds=0; #1;
    end endtask
    task end_write; begin
        nuds=1; nas=1; rw=1; repeat (3) tick();
    end endtask
    task immediate_write(input [7:0] data);
        integer original_strobes;
        begin
            original_strobes=strobes;
            begin_write(data);
            repeat (4) begin
                if (stall || nSDW) $fatal(1, "Unexpected wait on command %h", data);
                tick();
            end
            if (board_ndtack !== 0 || command !== data) $fatal(1, "No acceptance/latch for %h (latch=%h bus=%h dtack=%b nICOM=%b wait=%b)", data, command, bus, board_ndtack, c1.nICOM_ZONE, stall);
            end_write();
            if (strobes != original_strobes+1) $fatal(1, "Repeated ordinary write");
        end
    endtask
    task clear_driver; begin zwrite(1,16'hf800,0); zwrite(1,16'hf801,0); end endtask
    task begin_reset_sequence; begin
        immediate_write(3); zread(); zwrite(0,0,0); clear_driver();
    end endtask

    integer before_pulse, before_nmi;
    initial begin
        repeat (3) tick(); reset=0; tick();
        zwrite(0,8,0);
        begin_reset_sequence();
        before_pulse=strobes; before_nmi=interrupts;
        begin_write(7);
        repeat (12) begin
            if (!stall || !board_ndtack || !nSDW || command !== 0 || interrupts != before_nmi)
                $fatal(1,"Early command escaped during Z80 reset");
            tick();
        end
        zwrite(0,16'h0018,0); // disabling NMIs must not count as ready
        zwrite(1,16'hf808,0); // a RAM write to xx08 must not count as ready
        if (!stall || strobes != before_pulse) $fatal(1,"Released by wrong Z80 access stall=%b pulses %d (before %d), state %d", stall, strobes, before_pulse, c1.sound_guard.state);
        za=8; niorq=0; nwr=0; repeat (3) tick();
        if (!stall || command !== 0) $fatal(1,"Released before OUT $08 completed");
        niorq=1; nwr=1; tick(); tick();
        if (stall || board_ndtack || nSDW || command !== 7) $fatal(1,"Ready command was not latched");
        end_write();
        if (strobes != before_pulse+1 || interrupts != before_nmi+1) $fatal(1,"Wrong number of writes or NMIs");
        zread(); immediate_write(8'h28);
        begin_reset_sequence(); zwrite(0,8,0); immediate_write(7); // native gap already long enough

        immediate_write(3); clear_driver(); immediate_write(7); // reset was never consumed
        immediate_write(3); zread(); zwrite(1,16'hf800,0); zwrite(1,16'hf802,0);
        zwrite(1,16'hf801,0); immediate_write(7); // different RAM writes
        begin_reset_sequence(); immediate_write(8'h28); immediate_write(7); // a different next command
        begin_reset_sequence();
        address=24'h320000; rw=1; nas=0; nuds=0; repeat (3) tick();
        if (stall || !nSDW) $fatal(1,"Sound reply read changed");
        end_write();
        address=24'h320000; rw=0; nas=0; wd=7; nlds=0; repeat (3) tick();
        if (stall || !nSDW) $fatal(1,"Low-byte write changed");
        nlds=1; end_write();

        before_pulse=strobes;
        begin_write(7); if (!stall) $fatal(1,"Expected bounded wait");
        repeat (260) tick();
        if (stall || board_ndtack || command !== 7) $fatal(1,"Timeout did not deliver command");
        end_write(); if (strobes!=before_pulse+1) $fatal(1,"Timeout delivered twice");

        turbo=0; tick(); begin_reset_sequence(); immediate_write(7); // 12 MHz cartridge
        turbo=1; cd=1; tick(); begin_reset_sequence(); immediate_write(7); // Neo Geo CD
        cd=0; tick(); begin_reset_sequence(); reset=1; tick();
        reset=0; tick(); immediate_write(7); // stale sequence must not survive reset
        $display("PASS: sound latch, DTACK, NMI, timeout and native/CD bypass"); $finish;
    end
endmodule
