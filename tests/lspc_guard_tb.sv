`timescale 1ns/1ps
module lspc_guard_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1, turbo = 1, raw_nread = 1, raw_nwrite = 1;
    reg [3:1] addr;
    wire nread, nwrite, wait_cpu;
    neogeo_lspc_guard dut(.*);
    integer cycle = 0, last_write, wd, rd;
    always @(posedge clk) cycle <= cycle + 1;
    always @(negedge nwrite) wd = wd + 1;
    always @(negedge nread) rd = rd + 1;
    task access(input writing, input [2:0] reg_addr, input integer min_gap);
        integer timeout;
        begin
            @(negedge clk);
            addr = reg_addr;
            raw_nwrite = !writing;
            raw_nread = writing;
            #1;
            timeout = 0;
            while (nread && nwrite && timeout < 100) begin
                if (!wait_cpu) $fatal(1,"CPU released before video strobe");
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 100 || cycle-last_write < min_gap) $fatal(1,"Missing or premature strobe");
            repeat (3) @(negedge clk);
            if (wait_cpu || (writing ? nwrite : nread)) $fatal(1,"Strobe dropped during access");
            if (writing) last_write = cycle;
            raw_nwrite = 1;
            raw_nread = 1;
            @(negedge clk);
        end
    endtask
    initial begin
        wd = 0; rd = 0; last_write = -100;
        repeat (2) @(negedge clk);
        reset = 0;
        access(1,0,0);    // address
        access(0,5,64);   // mirrored VRAM read
        access(1,1,0);    // data
        access(1,1,48);   // back-to-back data
        access(1,0,64);   // data to new address
        access(0,0,64);
        if (wd != 4 || rd != 2) $fatal(1,"Lost or duplicate strobe");
        turbo = 0;
        addr = 1; raw_nwrite = 0; #1;
        if (nwrite || wait_cpu) $fatal(1,"Stock write must pass directly");
        raw_nwrite = 1; raw_nread = 0; #1;
        if (nread || wait_cpu) $fatal(1,"Stock read must pass directly");
        $display("PASS video port recovery, mirrored read, stock bypass");
        $finish;
    end
endmodule
