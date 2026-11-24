// The mode is written by hps_io on clk. A quiet interval releases all pins
// while the old reader stops and the two LLAPI clock domains drain reports.
module neogeo_user_port (
    input clk, reset, osd,
    input [2:0] requested,
    input [6:0] user_in, llapi_out,
    output reg [6:0] user_out,
    output llapi_active, snac_active, db15_drive,
    output [11:0] pad1, pad2
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
    neogeo_snac_pads serial (
        .clk(clk), .reset(reset), .mode(pad_mode), .user_in(user_in),
        .user_out(serial_out), .pad1(serial_pad1), .pad2(serial_pad2)
    );
    neogeo_snac_db15 splitter (
        .clk(clk), .reset(reset), .enable(db15_drive), .user_in(user_in),
        .user_out(db15_out), .pad1(db15_pad1), .pad2(db15_pad2)
    );
    always @* begin
        user_out = 7'h7f;
        if (llapi_active) user_out = llapi_out;
        else if (db15_drive) user_out = db15_out;
        else if (snac_active) user_out = serial_out;
    end
    assign pad1 = !snac_active ? 12'd0 : db15_drive ? db15_pad1 : serial_pad1;
    assign pad2 = !snac_active ? 12'd0 : db15_drive ? db15_pad2 : serial_pad2;
endmodule
