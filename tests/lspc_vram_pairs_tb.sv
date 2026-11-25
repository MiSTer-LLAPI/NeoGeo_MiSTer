// Exercise interleaved Neo Geo sprite coordinate and tile writes against the
// LSPC, its address counter and both RAM write ports. All data are synthetic.
`timescale 1ns/1ps
module lspc_vram_pairs_tb;
    reg clk=0, phase=0, reset=1;
    always #5 clk=~clk;
    always @(posedge clk) phase<=~phase;
    reg [3:1] addr=0;
    reg raw_nread=1, raw_nwrite=1;
    reg [15:0] write_data=0;
    wire [15:0] bus;
    assign bus = !raw_nwrite ? write_data : 16'hzzzz;
    wire nread,nwrite,wait_cpu;
    neogeo_lspc_guard guard(.clk(clk),.reset(reset),.turbo(1'b1),.addr(addr),
        .raw_nread(raw_nread),.raw_nwrite(raw_nwrite),.nread(nread),.nwrite(nwrite),.wait_cpu(wait_cpu));
    wire [10:0] fast_addr;
    wire [14:0] slow_addr;
    wire [15:0] fast_data,slow_data,cursor;
    wire fast_we_n,slow_we_n;
    reg [15:0] fast_ram[0:2047],slow_ram[0:32767];
    reg [15:0] fast_q,slow_q;
    lspc2_a2_sync video(.CLK(clk),.CLK_EN_24M_P(phase),.CLK_EN_24M_N(!phase),
        .RESET(!reset),.M68K_ADDR(addr),.M68K_DATA(bus),.LSPOE(nread),.LSPWE(nwrite),
        .DOTA(1'b0),.DOTB(1'b0),.VMODE(1'b0),.CD_VBLANK_IRQ_EN(1'b1),.CD_TIMER_IRQ_EN(1'b1),
        .VRAM_ADDR(cursor),.FVRAM_ADDR(fast_addr),.FVRAM_DATA_IN(fast_q),.FVRAM_DATA_OUT(fast_data),
        .CWE(fast_we_n),.SVRAM_ADDR(slow_addr),.SVRAM_DATA_IN({16'd0,slow_q}),
        .SVRAM_DATA_OUT(slow_data),.BWE(slow_we_n));
    always @(posedge clk) begin
        fast_q<=fast_we_n ? fast_ram[fast_addr] : fast_data;
        slow_q<=slow_we_n ? slow_ram[slow_addr] : slow_data;
        if (!fast_we_n) fast_ram[fast_addr]<=fast_data;
        if (!slow_we_n) slow_ram[slow_addr]<=slow_data;
    end

    task write_word(input [2:0] sel,input [15:0] value,input bit after_address);
        integer wait_ticks;
        begin
            addr=sel; write_data=value; raw_nwrite=0;
            @(negedge clk);
            wait_ticks=1;
            while(wait_cpu && wait_ticks<90) begin @(negedge clk);wait_ticks++;end
            if (wait_cpu || (after_address && wait_ticks>4))
                $fatal(1,"Register %d waited %d ticks after address=%d",sel,wait_ticks,after_address);
            repeat(8) @(negedge clk);
            raw_nwrite=1;
            repeat(3) @(negedge clk);
        end
    endtask

    task sequence_at(input [15:0] base,input [15:0] first,second);
        begin
            write_word(0,base,0);
            write_word(1,first,1);
            write_word(1,second,0);
            repeat(120) @(negedge clk);
            if (cursor !== base+2)
                $fatal(1,"VRAM cursor %h after pair at %h",cursor,base);
            if (base[15]) begin
                if (fast_ram[base[10:0]]!==first || fast_ram[base[10:0]+1]!==second)
                    $fatal(1,"Fast VRAM %h: %h/%h expected %h/%h",base,fast_ram[base[10:0]],fast_ram[base[10:0]+1],first,second);
            end else if (slow_ram[base[14:0]]!==first || slow_ram[base[14:0]+1]!==second)
                $fatal(1,"Slow VRAM %h: %h/%h expected %h/%h",base,slow_ram[base[14:0]],slow_ram[base[14:0]+1],first,second);
        end
    endtask
    integer i, ticks=0;
    always @(posedge clk) ticks<=ticks+1;
    initial begin
        repeat(12) @(negedge clk); reset=0;
        repeat(180) @(negedge clk);
        write_word(2,1,0);
        for (i=0;i<32;i++) begin
            while (ticks%32 != i) @(negedge clk);
            sequence_at(16'h8201,16'h5340+i,16'h4031-i);
            sequence_at(16'h8401,16'h2170+i,16'he80c-i);
            sequence_at(16'h4021,16'h69a5+i,16'h0f51-i);
        end
        // Mirror the raster routine's consecutive Y/X pairs without any
        // artificial gap after the Y data. Check the final address and both words.
        write_word(0,16'h8201,0);
        write_word(1,16'h4743,1);
        write_word(0,16'h8401,0);
        write_word(1,16'hb180,1);
        repeat(120) @(negedge clk);
        if (fast_ram[11'h201]!==16'h4743 || fast_ram[11'h401]!==16'hb180 || cursor!==16'h8402)
            $fatal(1,"Raster Y/X pair corrupted");
        $display("PASS fast and slow VRAM address/data pairs, both bytes and cursor");
        $finish;
    end
endmodule
