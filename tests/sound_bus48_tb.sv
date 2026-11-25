// Verify that the stable board-side write and its acknowledge cross the real
// experimental bridge once, including the first clock after the Z80 is ready.
`timescale 1ps/1ps
module sound_bus48_tb;
    bit clk, cpu_clk, reset=1, upper=1, nas=1;
    bit [15:0] data=0;
    wire [23:1] addr;
    wire [15:0] board_data;
    wire as_n, uds_n, rw, cpu_ndtack, dtack, stall, nSDW;
    tri [7:0] data_bus;
    assign data_bus=rw ? 8'bz : board_data[15:8];
    wire [7:0] latched;
    reg read_z80_n=1, ram_write=0, port_write=0;
    reg [15:0] za=0;
    always #10416 clk=~clk;
    integer offset=0;
    initial begin
        if (!$value$plusargs("offset_ps=%d",offset)) offset=0;
        #(offset); forever #5208 cpu_clk=~cpu_clk;
    end

    neogeo_cpu_bus48 bridge(.clk_cpu(cpu_clk),.clk_sys(clk),.reset(reset),
        .cpu_addr(23'h190000),.cpu_write_data(data),.cpu_fc(3'd1),.cpu_nas(nas),
        .cpu_nuds(upper),.cpu_nlds(1'b1),.cpu_rnw(1'b0),.cpu_ndtack(cpu_ndtack),
        .bus_addr(addr),.bus_write_data(board_data),.bus_nas(as_n),
        .bus_nuds(uds_n),.bus_rnw(rw),.bus_read_data(16'd0),.bus_ndtack(dtack|stall));
    neo_c1 c1(.CLK(clk),.reset(reset),.turbo_cart(1'b1),.tick_4m(1'b0),
        .z80_ram_write(ram_write),.z80_port_write(port_write),.z80_addr(za),
        .sound_wait(stall),.M68K_ADDR(addr[21:17]),.A22Z(addr[22]),.A23Z(addr[23]),
        .M68K_DATA(data_bus),.nUDS(uds_n),.nLDS(1'b1),.RW(rw),.nAS(as_n),
        .SDD_WR(8'd0),.SDD_RD(latched),.nSDZ80R(read_z80_n),.nSDZ80W(1'b1),
        .nSDZ80CLR(1'b1),.nSDW(nSDW),.CLK_EN_68K_P(1'b1),.nDTACK(dtack),
        .SYSTEM_TYPE(2'b00),.nROMWAIT(1'b1),.nPWAIT0(1'b1),.nPWAIT1(1'b1),.PDTACK(1'b1));

    integer pulses=0;
    reg previous_nSDW=1;
    always @(posedge clk) begin
        if (previous_nSDW && !nSDW && !reset) pulses++;
        previous_nSDW<=nSDW;
    end

    task put(input [7:0] value);
        begin
            @(negedge cpu_clk); data=16'hdead; nas=0;
            @(negedge cpu_clk); data={value,8'h00}; upper=0;
            wait (!cpu_ndtack);
            if (latched !== value) $fatal(1,"CPU received acknowledge before C1 latched %h",value);
            @(negedge cpu_clk); upper=1; nas=1;
            repeat (4) @(negedge clk);
        end
    endtask

    initial begin
        repeat (6) @(negedge clk); reset=0;
        put(3);
        read_z80_n=0; repeat (2) @(negedge clk); read_z80_n=1;
        za=16'hf800; ram_write=1; repeat (2) @(negedge clk);
        za=16'hf801; repeat (2) @(negedge clk); ram_write=0;
        fork
            put(7);
            begin
                wait (stall);
                repeat (12) begin
                    @(negedge clk);
                    if (!cpu_ndtack || !nSDW || latched!==3 || pulses!=1)
                        $fatal(1,"Premature CPU acknowledge or sound strobe");
                end
                za=8; port_write=1; repeat (3) @(negedge clk); port_write=0;
            end
        join
        put(8'h28);
        if (pulses!=3) $fatal(1,"Missing/duplicate sound writes");
        $display("PASS: 96/48 MHz sound bridge at offset %0d ps",offset); $finish;
    end
    initial begin #10000000; $fatal(1,"Bridge timeout"); end
endmodule
