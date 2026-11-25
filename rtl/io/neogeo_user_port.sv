// The mode is written by hps_io on clk. A quiet interval releases all pins
// while the old reader stops and the two LLAPI clock domains drain reports.
module neogeo_user_port (
    input clk, reset, game_reset, vblank, osd,
    input [2:0] requested,
    input [6:0] user_in, llapi_out,
    output reg [6:0] user_out,
    output llapi_active, snac_active, db15_drive,
    output [11:0] pad1, pad2,
    output snac_report_ready,
    output [3:0] gesture1, gesture2
);
    localparam LLAPI = 3'd0, MD = 3'd1, DB15 = 3'd2, SNES = 3'd3, SATURN = 3'd4;
    reg [2:0] selected = LLAPI;
    reg [8:0] settle = 0;
    always @(posedge clk) begin
        if (reset || osd || requested != selected) begin
            selected <= requested;
            settle <= 0;
        end else if (!(&settle)) begin
            settle <= settle + 1'b1;
        end
    end
    wire granted = (&settle) && (requested == selected) && !reset && !osd;
    assign llapi_active = granted && selected == LLAPI;
    assign db15_drive = granted && selected == DB15;
    assign snac_active = granted && selected >= MD && selected <= SATURN;

    wire [1:0] pad_mode = !granted ? 2'd0 : selected == MD ? 2'd1 :
                          selected == SNES ? 2'd2 : selected == SATURN ? 2'd3 : 2'd0;
    wire [6:0] serial_out, db15_out;
    wire [11:0] serial_pad1, serial_pad2, db15_pad1, db15_pad2;
    wire serial_ready, db15_ready;
    assign snac_report_ready = snac_active && (db15_drive ? db15_ready : serial_ready);
    neogeo_snac_pads serial (
        .clk(clk), .reset(reset), .mode(pad_mode), .user_in(user_in),
        .user_out(serial_out), .report_ready(serial_ready), .pad1(serial_pad1), .pad2(serial_pad2)
    );
    neogeo_snac_db15 splitter (
        .clk(clk), .reset(reset), .enable(db15_drive), .user_in(user_in),
        .user_out(db15_out), .report_ready(db15_ready), .pad1(db15_pad1), .pad2(db15_pad2)
    );
    always @* begin
        user_out = 7'h7f;
        if (llapi_active) user_out = llapi_out;
        else if (db15_drive) user_out = db15_out;
        else if (snac_active) user_out = serial_out;
    end
    // Keep the programmed buttons when the OSD temporarily releases USER I/O.
    wire clear_autofire = reset || game_reset || requested != selected;
    neogeo_snac_autofire autofire_p1 (
        .clk(clk), .reset(clear_autofire), .active(snac_active), .vblank(vblank),
        .gesture(gesture1),
        .pad_in(db15_drive ? db15_pad1 : serial_pad1), .pad_out(pad1)
    );
    neogeo_snac_autofire autofire_p2 (
        .clk(clk), .reset(clear_autofire), .active(snac_active), .vblank(vblank),
        .gesture(gesture2),
        .pad_in(db15_drive ? db15_pad2 : serial_pad2), .pad_out(pad2)
    );
endmodule
