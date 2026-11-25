// The 68000 and board clocks come from the same PLL. Only phase tokens
// cross before the corresponding held address/data buses are sampled.
module neogeo_cpu_bus48 (
    input clk_cpu, clk_sys, reset,
    input [23:1] cpu_addr,
    input [15:0] cpu_write_data,
    input [2:0] cpu_fc,
    input cpu_nas, cpu_nuds, cpu_nlds, cpu_rnw,
    output reg [15:0] cpu_read_data = 0,
    output cpu_ndtack,
    output reg [23:1] bus_addr = 0,
    output reg [15:0] bus_write_data = 0,
    output reg [2:0] bus_fc = 0,
    output reg bus_nas = 1, bus_nuds = 1, bus_nlds = 1, bus_rnw = 1,
    input [15:0] bus_read_data,
    input bus_ndtack
);
    reg request = 0, acknowledged = 0;
    reg acknowledge_sample = 0, request_sample = 0;
    reg [23:1] held_addr;
    reg [15:0] held_write_data, held_read_data;
    reg [2:0] held_fc;
    reg held_rnw, held_nuds, held_nlds;
    wire data_cycle = !cpu_nas && !(cpu_nlds && cpu_nuds);

    localparam CPU_IDLE = 0, CPU_WAIT = 1, CPU_ACK = 2;
    reg [1:0] cpu_state = CPU_IDLE;
    assign cpu_ndtack = !(cpu_state == CPU_ACK && data_cycle);
    always @(posedge clk_cpu) begin
        acknowledge_sample <= acknowledged;
        if (reset) begin
            cpu_state <= CPU_IDLE;
            request <= 0;
            acknowledge_sample <= 0;
        end else case (cpu_state)
            CPU_IDLE: if (data_cycle && cpu_fc != 3'b111) begin
                // FC=7 cartridge interrupt acknowledge uses the 68000 VPA
                // autovector. It has no native memory transaction.
                held_addr <= cpu_addr;
                held_write_data <= cpu_write_data;
                held_fc <= cpu_fc;
                {held_rnw,held_nuds,held_nlds} <= {cpu_rnw,cpu_nuds,cpu_nlds};
                request <= !request;
                cpu_state <= CPU_WAIT;
            end
            CPU_WAIT: if (acknowledge_sample == request) begin
                cpu_read_data <= held_read_data;
                cpu_state <= CPU_ACK;
            end
            // TAS keeps AS low across its read and write. The byte strobes
            // delimit each transfer even when AS stays asserted.
            CPU_ACK: if (!data_cycle) cpu_state <= CPU_IDLE;
            default: cpu_state <= CPU_IDLE;
        endcase
    end

    localparam SYS_IDLE = 0, SYS_ADDRESS = 1, SYS_SETTLE = 2, SYS_WAIT = 3;
    reg [1:0] sys_state = SYS_IDLE;
    always @(posedge clk_sys) begin
        request_sample <= request;
        if (reset) begin
            sys_state <= SYS_IDLE;
            bus_nas <= 1;
            bus_nuds <= 1;
            bus_nlds <= 1;
            bus_rnw <= 1;
            acknowledged <= 0;
            request_sample <= 0;
        end else case (sys_state)
            SYS_IDLE: if (request_sample != acknowledged) begin
                bus_addr <= held_addr;
                bus_write_data <= held_write_data;
                bus_fc <= held_fc;
                bus_rnw <= held_rnw;
                bus_nas <= 0;
                // Native write selects precede the byte strobes. Keep this
                // ordering for carts and I/O as on the original bus.
                bus_nuds <= held_rnw ? held_nuds : 1'b1;
                bus_nlds <= held_rnw ? held_nlds : 1'b1;
                sys_state <= held_rnw ? SYS_SETTLE : SYS_ADDRESS;
            end
            SYS_ADDRESS: begin
                {bus_nuds,bus_nlds} <= {held_nuds,held_nlds};
                sys_state <= SYS_SETTLE;
            end
            // Synchronous WRAM and the native DTACK decoder need one board
            // clock with valid byte strobes before data can be acknowledged.
            SYS_SETTLE: sys_state <= SYS_WAIT;
            SYS_WAIT: if (!bus_ndtack) begin
                held_read_data <= bus_read_data;
                acknowledged <= request_sample;
                bus_nas <= 1;
                bus_nuds <= 1;
                bus_nlds <= 1;
                bus_rnw <= 1;
                sys_state <= SYS_IDLE;
            end
        endcase
    end
endmodule

// The native CPU has the original direct 48 MHz board connection. The
// experimental cartridge CPU runs on 96 MHz and can reach the board only
// through the registered transaction bridge. The mode is latched in reset.
module neogeo_cpu_modes (
    input clk_fast, clk_board, reset, experimental, native_p, native_n, system_cd,
    input [1:0] ipl, input nbr, nbgack, output nbg,
    input [15:0] read_data, input ndtack,
    output [23:1] addr, output [15:0] write_data, output [2:0] fc,
    output nas, nuds, nlds, rnw
);
    wire [23:1] native_addr, fast_addr, bridge_addr;
    wire [15:0] native_write, fast_write, bridge_write, fast_read;
    wire [2:0] native_fc, fast_fc, bridge_fc;
    wire native_as, native_us, native_ls, native_rw, native_bg;
    wire fast_as, fast_us, fast_ls, fast_rw, fast_ack;
    wire bridge_as, bridge_us, bridge_ls, bridge_rw;

    cpu_68k native_cpu (
        .CLK(clk_board), .CLK_EN_68K_P(native_p), .CLK_EN_68K_N(native_n),
        .nRESET(!reset && !experimental), .SYSTEM_CDx(system_cd),
        .IPL2(1'b1), .IPL1(ipl[1]), .IPL0(ipl[0]), .nBR(nbr), .nBGACK(nbgack), .nBG(native_bg),
        .M68K_ADDR(native_addr), .FX68K_DATAIN(read_data), .FX68K_DATAOUT(native_write), .nDTACK(ndtack),
        .FC2(native_fc[2]), .FC1(native_fc[1]), .FC0(native_fc[0]),
        .nAS(native_as), .nUDS(native_us), .nLDS(native_ls), .M68K_RW(native_rw)
    );

    reg fast_p = 0;
    always @(posedge clk_fast) fast_p <= !fast_p;
    cpu_68k fast_cpu (
        .CLK(clk_fast), .CLK_EN_68K_P(fast_p), .CLK_EN_68K_N(!fast_p),
        .nRESET(!reset && experimental), .SYSTEM_CDx(1'b0),
        .IPL2(1'b1), .IPL1(ipl[1]), .IPL0(ipl[0]), .nBR(1'b1), .nBGACK(1'b1), .nBG(),
        .M68K_ADDR(fast_addr), .FX68K_DATAIN(fast_read), .FX68K_DATAOUT(fast_write), .nDTACK(fast_ack),
        .FC2(fast_fc[2]), .FC1(fast_fc[1]), .FC0(fast_fc[0]),
        .nAS(fast_as), .nUDS(fast_us), .nLDS(fast_ls), .M68K_RW(fast_rw)
    );
    neogeo_cpu_bus48 bridge (
        .clk_cpu(clk_fast), .clk_sys(clk_board), .reset(reset || !experimental),
        .cpu_addr(fast_addr), .cpu_write_data(fast_write), .cpu_fc(fast_fc),
        .cpu_nas(fast_as), .cpu_nuds(fast_us), .cpu_nlds(fast_ls), .cpu_rnw(fast_rw),
        .cpu_read_data(fast_read), .cpu_ndtack(fast_ack),
        .bus_addr(bridge_addr), .bus_write_data(bridge_write), .bus_fc(bridge_fc),
        .bus_nas(bridge_as), .bus_nuds(bridge_us), .bus_nlds(bridge_ls), .bus_rnw(bridge_rw),
        .bus_read_data(read_data), .bus_ndtack(ndtack)
    );
    assign {addr, write_data, fc, nas, nuds, nlds, rnw} = experimental
        ? {bridge_addr, bridge_write, bridge_fc, bridge_as, bridge_us, bridge_ls, bridge_rw}
        : {native_addr, native_write, native_fc, native_as, native_us, native_ls, native_rw};
    assign nbg = experimental ? 1'b1 : native_bg;
endmodule
