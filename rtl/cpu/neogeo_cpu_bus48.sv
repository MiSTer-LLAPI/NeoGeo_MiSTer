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

module neogeo_cpu_phases (
    input clk_cpu, experimental, legacy_p, legacy_n,
    output phi1, phi2
);
    reg phase = 0;
    always @(posedge clk_cpu) phase <= !phase;
    assign phi1 = experimental ? phase : legacy_p;
    assign phi2 = experimental ? !phase : legacy_n;
endmodule
