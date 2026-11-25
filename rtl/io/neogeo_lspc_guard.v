// Enforce VRAM port recovery in real time when the cartridge 68000 is faster.
// SNK Neo Geo Development Manual, Hardware 7-8: 16 original CPU clocks for
// address/read and data/address, 12 for successive data writes. At 48 MHz
// these are 64 and 48 ticks respectively; the stock path is a direct wire.
module neogeo_lspc_guard(
    input clk, reset, turbo,
    input [3:1] addr,
    input raw_nread, raw_nwrite,
    output nread, nwrite, wait_cpu
);
    wire selected = !raw_nread || !raw_nwrite;
    wire write_addr = !raw_nwrite && addr == 3'd0;
    wire write_data = !raw_nwrite && addr == 3'd1;
    wire write_mod = !raw_nwrite && addr == 3'd2;
    // The read multiplexer only decodes A2/A1: +8/+A mirror +0/+2.
    wire read_data = !raw_nread && !addr[2];
    wire vram_access = write_addr || write_data || write_mod || read_data;

    reg [6:0] recovery = 0;
    reg last_write_data = 0;
    reg issued = 0, sampled = 0;
    wire short_gap = last_write_data && write_data;
    // The address register loads on release. The following data write can
    // issue at the next bus cycle; only a VRAM read needs the prefetched word.
    wire address_to_data = !last_write_data && write_data;
    wire can_issue = !vram_access || address_to_data || (short_gap ? recovery <= 7'd16 : recovery == 0);

    // Stalling only DTACK would still expose the new write to the LSPC.
    // Gate both pins, passing exactly one continuous strobe per transaction.
    assign nread = raw_nread || (turbo && !issued);
    assign nwrite = raw_nwrite || (turbo && !issued);
    assign wait_cpu = turbo && selected && !sampled;

    always @(posedge clk) begin
        if (reset || !turbo) begin
            issued <= 0;
            sampled <= 0;
            recovery <= 0;
            last_write_data <= 0;
        end else begin
            if (!selected) begin
                issued <= 0;
                sampled <= 0;
            end else begin
                if (can_issue) issued <= 1;
                sampled <= issued;
            end

            // Measure from the last visible tick of the previous strobe. The
            // video hardware applies an address change on write release.
            if (!nwrite && (write_data || write_addr)) begin
                recovery <= 7'd64;
                last_write_data <= write_data;
            end else if (recovery != 0) begin
                recovery <= recovery - 1'b1;
            end
        end
    end
endmodule
