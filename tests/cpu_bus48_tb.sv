`timescale 1ns/1ps
// Boot the actual fx68k microcode and run a small 68000 program against a
// 48 MHz target. Every bus transaction must survive variable DTACK delays.
module cpu_bus48_tb;
    bit clk_cpu, clk_sys;
    integer offset_ps;
    always #5.208 clk_cpu = ~clk_cpu;
    initial begin
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

    wire [23:1] ba;
    wire [15:0] bw, read_data;
    wire [2:0] bf;
    wire bas, bus_upper, bus_lower, brw, ndtack;
    bit irq_done, saw_iack, tas_locked, saw_tas_write;
    wire irq2 = !cd && memory_end != 0 && !irq_done;
    wire native_p = turbo24 ? phi24p : phi12p;
    wire native_n = turbo24 ? phi24n : phi12n;
    neogeo_cpu_modes cpu(.clk_fast(clk_cpu), .clk_board(clk_sys), .reset(reset), .experimental(turbo48),
        .native_p(native_p), .native_n(native_n), .system_cd(cd), .ipl({!irq2,1'b1}),
        .nbr(1'b1), .nbgack(1'b1), .read_data(read_data), .ndtack(ndtack), .addr(ba),
        .write_data(bw), .fc(bf), .nas(bas), .nuds(bus_upper), .nlds(bus_lower), .rnw(brw));
    // Observe the selected CPU's own cycle for IACK and TAS across the bridge.
    wire [23:1] ca = turbo48 ? cpu.fast_addr : cpu.native_addr;
    wire [2:0] cf = turbo48 ? cpu.fast_fc : cpu.native_fc;
    wire cas = turbo48 ? cpu.fast_as : cpu.native_as;
    wire cus = turbo48 ? cpu.fast_us : cpu.native_us;
    wire cls = turbo48 ? cpu.fast_ls : cpu.native_ls;
    wire crw = turbo48 ? cpu.fast_rw : cpu.native_rw;
    // The board-visible bus must match the original CPU in every native mode.
    wire [23:1] ref_addr;
    wire [15:0] ref_wdata;
    wire [2:0] ref_fc;
    wire ref_as, ref_us, ref_ls, ref_rw;
    cpu_68k native_reference(.CLK(clk_sys), .CLK_EN_68K_P(turbo24 ? phi24p : phi12p),
        .CLK_EN_68K_N(turbo24 ? phi24n : phi12n), .nRESET(!reset),
        .M68K_ADDR(ref_addr), .FX68K_DATAOUT(ref_wdata), .FX68K_DATAIN(read_data),
        .nDTACK(ndtack), .nAS(ref_as), .nUDS(ref_us), .nLDS(ref_ls), .M68K_RW(ref_rw),
        .FC2(ref_fc[2]), .FC1(ref_fc[1]), .FC0(ref_fc[0]), .IPL2(1'b1),
        .IPL1(!irq2), .IPL0(1'b1), .nBR(1'b1), .nBGACK(1'b1), .SYSTEM_CDx(cd));
    always @(negedge clk_sys) begin
        #1ps;
        if (!reset && !turbo48) begin
            if ({bas,bus_upper,bus_lower,brw,bf} !== {ref_as,ref_us,ref_ls,ref_rw,ref_fc} ||
                (!bas && ba !== ref_addr) || (!bas && !brw && bw !== ref_wdata))
                $fatal(1, "Native bus differs from original CPU at address %h", ca);
        end
    end

    reg [15:0] rom[0:255], ram[0:1];
    int ip = 'h80;
    task emit(input [15:0] word_in);
        rom[ip] = word_in;
        ip++;
    endtask

    wire [23:0] addr = {ba,1'b0};
    wire active = !bas && (!bus_upper || !bus_lower);
    int wait_age, writes, benchmark_start, benchmark_end, memory_end, cpu_ticks;
    int native_p_count, native_n_count, fast_p_count, fast_n_count;
    always @(posedge clk_cpu) begin
        if (cpu.fast_p) fast_p_count <= fast_p_count + 1;
        else fast_n_count <= fast_n_count + 1;
    end
    always @(posedge clk_sys) begin
        if (native_p && native_n) $fatal(1, "Overlapping native CPU phases");
        if (native_p) native_p_count <= native_p_count + 1;
        if (native_n) native_n_count <= native_n_count + 1;
    end
    wire [31:0] phi1_count = turbo48 ? fast_p_count : native_p_count;
    wire [31:0] phi2_count = turbo48 ? fast_n_count : native_n_count;
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
