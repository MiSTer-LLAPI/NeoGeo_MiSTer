// Blazing Star reinitializes its sound driver on $03 and uses a CPU delay
// before $07. An accelerated 68000 can send $07 while the Z80 is still
// zeroing its command queue. Wait only for this observed startup sequence.
module neogeo_sound_guard #(parameter TIMEOUT_BITS = 17) (
    input clk, reset, turbo_cart, tick_4m,
    input command_write,
    input [7:0] command_data,
    input reset_command_read,
    input z80_ram_write,
    input [15:0] z80_addr,
    input [7:0] z80_data,
    input z80_port_write,
    output wait_cpu
);
    localparam IDLE = 3'd0, RESET_SENT = 3'd1, RESET_READ = 3'd2,
               CLEAR_FIRST = 3'd3, CLEAR_CONFIRMED = 3'd4;
    reg [2:0] state;
    reg [TIMEOUT_BITS-1:0] timeout_count;
    reg previous_write, delay_this_write, previous_enable;
    wire first_write = command_write && !previous_write;
    wire needs_delay = (state == CLEAR_CONFIRMED && command_data == 8'h07);
    wire enable_nmi_write = z80_port_write && z80_addr[7:0] == 8'h08;
    wire enable_nmi_done = previous_enable && !enable_nmi_write;
    wire zero_ram_write = z80_ram_write && z80_data == 8'h00;

    // Keep C1's latch and D0's NMI strobe idle for the entire deferred write.
    // Once a bus cycle starts, later RAM activity cannot split its strobe.
    assign wait_cpu = turbo_cart && command_write && state == CLEAR_CONFIRMED &&
                      (previous_write ? delay_this_write : needs_delay);

    always @(posedge clk) begin
        previous_write <= command_write;
        previous_enable <= enable_nmi_write;
        if (first_write) delay_this_write <= needs_delay;
        if (reset || !turbo_cart) begin
            state <= IDLE;
            timeout_count <= 0;
            delay_this_write <= 0;
            previous_write <= 0;
            previous_enable <= 0;
        end else if (first_write && command_data == 8'h03) begin
            state <= RESET_SENT;
            timeout_count <= 0;
        end else if (state != IDLE) begin
            // At 4 MHz this bounds the entire observation window at 32.768 ms.
            if (tick_4m) timeout_count <= timeout_count + 1'b1;
            if ((tick_4m && &timeout_count) || (first_write && !needs_delay) ||
                (state == CLEAR_CONFIRMED && enable_nmi_done)) state <= IDLE;
            else case (state)
                RESET_SENT: if (reset_command_read) state <= RESET_READ;
                RESET_READ: if (zero_ram_write && z80_addr == 16'hF800) state <= CLEAR_FIRST;
                CLEAR_FIRST: if (z80_ram_write && z80_addr != 16'hF800)
                    state <= (zero_ram_write && z80_addr == 16'hF801) ? CLEAR_CONFIRMED : RESET_READ;
                default: ;
            endcase
        end
    end
endmodule
