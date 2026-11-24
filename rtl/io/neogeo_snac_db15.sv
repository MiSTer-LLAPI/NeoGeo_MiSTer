// Serial format of the Antonio Villena DB15 splitter, after Aitor Pelaez's
// JTFRAME joy_db15 reader. Each 26-clock frame carries 24 active-low contacts.
// At 48 MHz the default half period is 10 us (about 0.52 ms per complete scan).
module neogeo_snac_db15 #(
    parameter integer HALF_TICKS = 480
)(
    input clk, reset, enable,
    input [6:0] user_in,
    output [6:0] user_out,
    output reg [11:0] pad1 = 0,
    output reg [11:0] pad2 = 0
);
    localparam DIV_WIDTH = HALF_TICKS < 2 ? 1 : $clog2(HALF_TICKS);
    reg [DIV_WIDTH-1:0] divider = 0;
    reg [5:0] step = 0;
    reg serial_clk = 1, nload = 1;
    (* async_reg = "true" *) reg data_meta = 1, data_sync = 1;
    reg [23:0] shift = 24'hffffff;
    wire [23:0] contacts = ~{data_sync, shift[23:1]};
    wire running = enable && !reset;

    // The serializer owns only USER0 (/LOAD) and USER1 (CLK).
    // USER5 is always an input. Other protocol modes own their own outputs.
    assign user_out = running ? {5'b11111, serial_clk, nload} : 7'h7f;
    always @(posedge clk) begin
        data_meta <= user_in[5];
        data_sync <= data_meta;

        if (!running) begin
            divider <= 0;
            step <= 0;
            serial_clk <= 1;
            nload <= 1;
            shift <= 24'hffffff;
            pad1 <= 0;
            pad2 <= 0;
        end else if (divider == HALF_TICKS-1) begin
            divider <= 0;
            step <= step == 51 ? 0 : step + 1'b1;
            serial_clk <= step[0];
            // Change /LOAD on falling clock edges to provide hold/setup at
            // the first rising shift clock, independent of PCB pin skew.
            if (step == 0) nload <= 0;
            if (step == 2) nload <= 1;
            if (step[0] && step >= 3 && step <= 49) begin
                // Sample the stable bit BEFORE driving the next rising edge.
                shift <= {data_sync, shift[23:1]};
                if (step == 49) begin
                    // Native joystick bits: ABC combo, Coin, Select, Start,
                    // D, C, B, A, Up, Down, Left, Right. Select also inserts
                    // a credit on MVS. The non-NeoGeo E/F contacts are unused.
                    pad1 <= {1'b0, contacts[14], contacts[14], contacts[15],
                             contacts[0], contacts[1], contacts[2], contacts[3],
                             contacts[7], contacts[6], contacts[5], contacts[4]};
                    pad2 <= {1'b0, contacts[18], contacts[18], contacts[19],
                             contacts[20], contacts[21], contacts[22], contacts[23],
                             contacts[11], contacts[10], contacts[9], contacts[8]};
                end
            end
        end else begin
            divider <= divider + 1'b1;
        end
    end
endmodule
