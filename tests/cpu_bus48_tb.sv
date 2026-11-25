`timescale 1ns/1ps
// Boot the actual fx68k microcode and run a small 68000 program against a
// 48 MHz target. Every bus transaction must survive variable DTACK delays.
module cpu_bus48_tb;
    bit clk_cpu, clk_sys;
    always #5.208 clk_cpu = ~clk_cpu;
    initial begin
        integer offset_ps;
        if (!$value$plusargs("offset_ps=%d", offset_ps)) offset_ps = 0;
        #(offset_ps * 1ps);
        forever #10.416 clk_sys = ~clk_sys;
    end

    bit reset = 1, turbo48, turbo24, cd;
    bit phi24n = 0, phi24p = 1;
    always @(posedge clk_sys) begin
        phi24n <= !phi24n;
        phi24p <= phi24n;
    end
    wire phi12p, phi12n;
    clocks_sync native_clocks(.CLK(clk_sys), .CLK_EN_24M_P(phi24p), .CLK_EN_24M_N(phi24n),
        .nRESETP(1'b1), .CLK_EN_68K_P(phi12p), .CLK_EN_68K_N(phi12n));

    wire [23:1] ca, ba;
    wire [15:0] cw, bw, cr;
    wire [2:0] cf, bf;
    wire cas, cus, cls, crw, bas, bus_upper, bus_lower, brw, cpu_ack;
    wire [15:0] read_data;
    wire ndtack;
    wire [23:1] proxy_addr;
    wire [15:0] proxy_wdata;
    wire [2:0] proxy_fc;
    wire proxy_as, proxy_upper, proxy_lower, proxy_rw;
    neogeo_cpu_bus48 bridge(
        .clk_cpu(clk_cpu), .clk_sys(clk_sys), .reset(reset || !turbo48),
        .cpu_addr(ca), .cpu_write_data(cw), .cpu_fc(cf), .cpu_nas(cas),
        .cpu_nuds(cus), .cpu_nlds(cls), .cpu_rnw(crw), .cpu_read_data(cr), .cpu_ndtack(cpu_ack),
        .bus_addr(proxy_addr), .bus_write_data(proxy_wdata), .bus_fc(proxy_fc),
        .bus_nas(proxy_as), .bus_nuds(proxy_upper), .bus_nlds(proxy_lower), .bus_rnw(proxy_rw),
        .bus_read_data(read_data), .bus_ndtack(ndtack)
    );
    assign {ba, bw, bf, bas, bus_upper, bus_lower, brw} = turbo48 ?
        {proxy_addr, proxy_wdata, proxy_fc, proxy_as, proxy_upper, proxy_lower, proxy_rw} :
        {ca, cw, cf, cas, cus, cls, crw};
    wire core_clk = turbo48 ? clk_cpu : clk_sys;
    wire phi1, phi2;
    neogeo_cpu_phases phases(.clk_cpu(core_clk), .experimental(turbo48),
        .legacy_p(turbo24 ? phi24p : phi12p), .legacy_n(turbo24 ? phi24n : phi12n),
        .phi1(phi1), .phi2(phi2));
    bit irq_done, saw_iack, tas_locked, saw_tas_write;
    wire irq2 = !cd && memory_end != 0 && !irq_done;
    cpu_68k cpu(.CLK(core_clk), .CLK_EN_68K_P(phi1), .CLK_EN_68K_N(phi2),
        .nRESET(!reset), .M68K_ADDR(ca), .FX68K_DATAOUT(cw),
        .FX68K_DATAIN(turbo48 ? cr : read_data), .nDTACK(turbo48 ? cpu_ack : ndtack),
        .nAS(cas), .nUDS(cus), .nLDS(cls), .M68K_RW(crw),
        .FC2(cf[2]), .FC1(cf[1]), .FC0(cf[0]),
        .IPL2(1'b1), .IPL1(!irq2), .IPL0(1'b1), .nBR(1'b1), .nBGACK(1'b1), .SYSTEM_CDx(cd));

    reg [15:0] rom[0:255], ram[0:1];
    int ip = 'h80;
    task emit(input [15:0] word_in);
        rom[ip] = word_in;
        ip++;
    endtask

    wire [23:0] addr = {ba,1'b0};
    wire active = !bas && (!bus_upper || !bus_lower);
    int wait_age, writes, benchmark_start, benchmark_end, memory_end, cpu_ticks;
    int phi1_count, phi2_count;
    always @(posedge core_clk) begin
        if (phi1 && phi2) $fatal(1,"Overlapping 68000 phases");
        if (phi1) phi1_count <= phi1_count + 1;
        if (phi2) phi2_count <= phi2_count + 1;
    end
    bit in_transfer, accepted;
    reg [23:0] held_addr;
    reg [2:0] held_lanes;
    reg [15:0] held_data;
    always @(posedge clk_cpu) begin
        if (reset) begin
            saw_iack <= 0; tas_locked <= 0; saw_tas_write <= 0;
        end else begin
            if (!cas && cf == 7) saw_iack <= 1;
            if (!cas && {ca,1'b0} == 'h100002 && !cus && cls && crw)
                tas_locked <= 1;
            if (tas_locked && !cas && !cus && !crw) begin
                saw_tas_write <= 1;
                tas_locked <= 0;
            end else if (tas_locked && cas) $fatal(1, "TAS did not hold CPU AS between read and write");
        end
    end
    wire [3:0] delay_ticks = addr[23:20] >= 3 ? 7 : addr[23:20] == 0 ? (2 + addr[3:2]) : 1;
    assign ndtack = !active || wait_age < delay_ticks;
    assign read_data = ndtack ? 16'hbad0 :
        addr[23:20] == 1 ? ram[addr[1]] : addr[23:9] == 0 ? rom[addr[8:1]] : 16'hffff;
    function bit benchmarked_stack_push(input [23:0] a);
        return irq2 && a >= 'h100ffa && a <= 'h100ffe;
    endfunction
    always @(posedge clk_cpu) cpu_ticks <= cpu_ticks + 1;
    always @(posedge clk_sys) begin
        if (reset || !active) begin
            in_transfer <= 0; accepted <= 0; wait_age <= 0;
            if (reset) begin writes <= 0; benchmark_start <= 0; benchmark_end <= 0; memory_end <= 0; irq_done <= 0; end
            else if (in_transfer && !accepted) $fatal(1, "Bus cycle ended before DTACK at %h", held_addr);
        end else begin
            if (turbo48 && bf == 7) $fatal(1, "Cartridge IACK was sent to native memory");
            if (!in_transfer) begin
                held_addr <= addr;
                held_lanes <= {brw,bus_upper,bus_lower};
                held_data <= bw;
            end else if (addr !== held_addr || {brw,bus_upper,bus_lower} !== held_lanes || (!brw && bw !== held_data))
                $fatal(1, "Bus changed during active strobe at %h", addr);
            in_transfer <= 1;
            if (ndtack) wait_age <= wait_age + 1;
            else if (!accepted) begin
                accepted <= 1;
                if (!brw) begin
                    if (benchmarked_stack_push(addr)) begin
                        if ({bus_lower,bus_upper} != 0) $fatal(1,"Invalid exception stack word");
                    end else begin
                        case (writes)
                            0: if (addr != 'h100000 || {bus_upper,bus_lower} != 0 || bw != 'h1357) $fatal(1, "RAM word write");
                            1: if (addr != 'h300000 || bw != 'h49f3 || {bus_upper,bus_lower} != 0) $fatal(1, "ALU word result %h", bw);
                            2: if (addr != 'h100002 || {bus_upper,bus_lower} != 2'b10 || bw[7:0] != 'h5a) $fatal(1, "Odd byte write");
                            3: if (addr != 'h100002 || {bus_upper,bus_lower} != 2'b01 || bw[15:8] != 'h25) $fatal(1, "Even byte write");
                            4: if (addr != 'h100002 || {bus_upper,bus_lower} != 2'b01 || bw[15:8] != 'ha5) $fatal(1, "TAS write %h", bw);
                            5: begin
                                if (addr != 'h400000 || bw != 'ha55a || {bus_upper,bus_lower} != 0) $fatal(1, "RAM/TAS readback %h", bw);
                                benchmark_start <= cpu_ticks;
                            end
                            6: begin
                                if (addr != 'h400002 || bw != 'h3e81 || {bus_upper,bus_lower} != 0) $fatal(1, "Calculation loop result %h", bw);
                                benchmark_end <= cpu_ticks;
                            end
                            7: begin
                                if (addr != 'h400006 || bw != 'h1357 || {bus_upper,bus_lower} != 0)
                                    $fatal(1, "Memory loop result %h", bw);
                                memory_end <= cpu_ticks;
                            end
                            8: begin
                                if (addr != 'h400004 || bw != 'hbeef || {bus_upper,bus_lower} != 0 || !saw_iack)
                                    $fatal(1, "Level 2 autovector handler result %h", bw);
                                irq_done <= 1;
                            end
                            default: $fatal(1, "Unexpected duplicate write");
                        endcase
                        if (addr[23:20] == 1) begin
                            if (!bus_upper) ram[addr[1]][15:8] <= bw[15:8];
                            if (!bus_lower) ram[addr[1]][7:0] <= bw[7:0];
                        end
                        writes <= writes + 1;
                    end
                end
            end
        end
    end

    task run(input int mhz, input bit is_cd, output int duration, output int memory_duration);
        int p1_before, p2_before, expected_pulses;
        @(negedge clk_sys);
        reset = 1;
        repeat (80) @(negedge clk_sys);
        cd = is_cd; turbo24 = mhz==24 && !cd; turbo48 = mhz==48 && !cd;
        repeat (80) @(negedge clk_sys);
        @(negedge clk_cpu);
        p1_before = phi1_count; p2_before = phi2_count;
        repeat (192) @(negedge clk_cpu);
        expected_pulses = 2 * (is_cd ? 12 : mhz);
        if (phi1_count - p1_before != expected_pulses || phi2_count - p2_before != expected_pulses)
            $fatal(1, "Wrong phase frequency at %0d MHz CD=%b", mhz, cd);
        @(negedge clk_sys);
        reset = 0;
        repeat (100000) begin
            @(negedge clk_sys);
            if (memory_end && (is_cd || irq_done)) begin
                if (!saw_tas_write) $fatal(1,"No atomic TAS completed");

                duration = benchmark_end - benchmark_start;
                memory_duration = memory_end - benchmark_end;
                $display("CPU request %0d MHz CD=%b: MULU loop %0d, RAM loop %0d ticks at 96 MHz", mhz, cd, duration, memory_duration);
                return;
            end
        end
        $fatal(1,"CPU stalled request=%0d CD=%b writes=%0d CPU=%h bus=%h AS=%b/%b",mhz,cd,writes,{ca,1'b0},addr,cas,bas);
    endtask

    int t12,t24,t48,tcd, m12,m24,m48,mcd;
    initial begin
        rom[0]=16'h0010; rom[1]=16'h1000;
        rom[2]=0; rom[3]=16'h0100;
        // Write and read a full word, add, and send its result to a slow peripheral.
        emit('h33fc); emit('h1357); emit('h0010); emit(0);
        emit('h3039); emit('h0010); emit(0);
        emit('h0640); emit('h369c);
        emit('h33c0); emit('h0030); emit(0);
        // Separate byte lanes and TAS.B (read/modify/write while AS is held).
        emit('h13fc); emit('h005a); emit('h0010); emit(3);
        emit('h13fc); emit('h0025); emit('h0010); emit(2);
        emit('h4af9); emit('h0010); emit(2);
        emit('h3239); emit('h0010); emit(2);
        emit('h33c1); emit('h0040); emit(0);
        // D4.L = 3 * (D4.W), 32 times; final low word = 0x3e81.
        emit('h741f); emit('h7603); emit('h7801);
        emit('hc8c3); emit('h51ca); emit('hfffc);
        emit('h33c4); emit('h0040); emit(2);
        // Contrast the multiply loop with 32 absolute-address memory reads.
        emit('h741f);
        emit('h3039); emit('h0010); emit(0);
        emit('h51ca); emit('hfff8);
        emit('h33c0); emit('h0040); emit(6);
        emit('h46fc); emit('h2000); // Unmask IRQs after the benchmark.
        emit('h60fe); emit('h4e71);
        rom['h34]=0; rom['h35]='h0180; // Level 2 autovector.
        ip='hc0;
        emit('h33fc); emit('hbeef); emit('h0040); emit(4);
        emit('h60fe); emit('h4e71);
        run(12,0,t12,m12); run(24,0,t24,m24); run(48,0,t48,m48); run(48,1,tcd,mcd);
        if (t48 >= t24 || t24 >= t12 || tcd != t12 || mcd != m12)
            $fatal(1,"CPU throughput or native CD timing regression");
        $display("PASS real 68000 fetch, delayed DTACK, byte lanes, TAS, autovector and computational speed");
        $finish;
    end
endmodule
