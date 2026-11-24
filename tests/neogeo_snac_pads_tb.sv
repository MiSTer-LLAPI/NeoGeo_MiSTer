// Independent controller-side models. Check each button, connector pin release,
// pad signatures, port priority and switching away in the middle of a scan.
module neogeo_snac_pads_tb;
    reg clk=0, reset=1;
    always #1 clk=~clk;
    reg [1:0] mode=0;
    reg [6:0] input_lines;
    wire [6:0] pins;
    wire [11:0] pad1,pad2;
    localparam TICK=8, SCAN=80;
    neogeo_snac_pads #(.TICK_CYCLES(TICK),.SCAN_TICKS(SCAN)) dut(
        .clk(clk),.reset(reset),.mode(mode),.user_in(input_lines),
        .user_out(pins),.pad1(pad1),.pad2(pad2));

    reg plugged=1, six=1, sat_digital=1;
    reg [15:0] snes1=0,snes2=0;
    integer bit1=0,bit2=0;
    always @(negedge pins[0]) begin bit1=0; bit2=0; end
    always @(negedge pins[1]) if (mode==2 && !pins[0] && bit1<15) bit1++;
    always @(negedge pins[3]) if (mode==2 && !pins[0] && bit2<15) bit2++;
    reg [5:0] md_std=0; // C B Right Left Down Up
    reg [1:0] md_as=0; // Start A
    reg [3:0] md_extension=0; // Mode X Y Z
    integer md_edges=0,idle=0;
    always @(negedge pins[4]) if (mode==1) md_edges++;
    always @(posedge clk) begin
        if (mode!=1 || reset) begin md_edges=0;idle=0; end
        else if (pins[4]) begin
            idle++;
            if (idle>80) md_edges=0;
        end else idle=0;
    end
    reg [3:0] sat_dir=0,sat_main=0,sat_extra=0;
    reg sat_l=0;
    reg [5:0] md;
    reg [3:0] sat;
    always @* begin
        input_lines=7'h7f;
        md=~md_std;
        if (!pins[4]) begin
            md={~md_as,2'b00,~md_std[1:0]};
            if (six && md_edges==3) md[3:0]=0;
        end else if (six && md_edges==3) md={2'b11,~md_extension};
        case ({pins[6],pins[4]})
            0: sat=~sat_extra;
            1: sat=~sat_main;
            2: sat=~sat_dir;
            3: sat={~sat_l,sat_digital ? 3'b100 : 3'b001};
        endcase
        if (plugged) case(mode)
            1: {input_lines[6],input_lines[2],input_lines[3],input_lines[5],
                input_lines[0],input_lines[1]}=md;
            2: begin
                input_lines[5]=pins[0] ? ~snes1[0] : ~snes1[bit1];
                input_lines[6]=pins[0] ? ~snes2[0] : ~snes2[bit2];
            end
            3: {input_lines[3],input_lines[5],input_lines[0],input_lines[1]}=sat;
        endcase
    end
    always @(posedge clk) begin
        if (mode==0 && pins!==7'h7f) $fatal(1,"disabled reader drives pins");
        if (mode==1 && (pins & 7'h6f)!==7'h6f) $fatal(1,"MD drives a data pin");
        if (mode==2 && (pins & 7'h74)!==7'h74) $fatal(1,"SNES drives a data pin");
        if (mode==3 && (pins & 7'h2f)!==7'h2f) $fatal(1,"Saturn drives a data pin");
    end
    integer checks=0;
    task expect_pads(input [11:0] a,b);
        begin
            repeat(2*SCAN*TICK) @(negedge clk);
            if ({pad1,pad2} !== {a,b})
                $fatal(1,"mode=%d expected %h/%h got %h/%h",mode,a,b,pad1,pad2);
            checks++;
        end
    endtask
    task switch_mode(input [1:0] next);
        begin
            @(negedge clk); mode=next; #0;
            if (pins!==7'h7f || {pad1,pad2}!==24'd0) $fatal(1,"state leaked across mode switch");
        end
    endtask
    function automatic [11:0] snes_expected(input integer b);
        case(b)
             0: snes_expected='h010;  1: snes_expected='h040;
             2: snes_expected='h600;  3: snes_expected='h100;
             4: snes_expected='h008;  5: snes_expected='h004;
             6: snes_expected='h002;  7: snes_expected='h001;
             8: snes_expected='h020;  9: snes_expected='h080;
            11: snes_expected='h800;
            default: snes_expected=0;
        endcase
    endfunction
    integer i;
    initial begin
        repeat(8) @(negedge clk);
        reset=0;
        switch_mode(2);
        for (i=0;i<12;i++) begin
            snes1=1<<i; snes2=1<<(11-i);
            expect_pads(snes_expected(i),snes_expected(11-i));
        end
        snes1='h1001; snes2='h0200; expect_pads(0,'h080); // reject reserved ID on P1
        snes1='h030f; snes2=1; expect_pads('h7f0,'h010); // held buttons, both ports
        plugged=0; expect_pads(0,0); plugged=1;
        switch_mode(1);
        md_as=1; expect_pads('h010,0); md_as=2; expect_pads('h100,0); md_as=0;
        for (i=0;i<6;i++) begin
            md_std=1<<i;
            case (i)
                0: expect_pads('h008,0); 1: expect_pads('h004,0);
                2: expect_pads('h002,0); 3: expect_pads('h001,0);
                4: expect_pads('h020,0); 5: expect_pads('h040,0);
            endcase
        end
        md_std=0; md_extension=4; expect_pads('h080,0);
        md_extension=8; expect_pads('h600,0);
        md_extension=15; six=0; expect_pads(0,0);
        md_as=2; md_std=2; expect_pads('h604,0);
        md_as=1; md_std='h30; expect_pads('h070,0);
        plugged=0; expect_pads(0,0); plugged=1;
        switch_mode(3);
        for (i=0;i<4;i++) begin sat_dir=1<<i; expect_pads(1<<(3-i),0); end
        sat_dir=0;
        sat_main=1; expect_pads('h020,0); sat_main=2; expect_pads('h040,0);
        sat_main=4; expect_pads('h010,0); sat_main=8; expect_pads('h100,0);
        sat_main=0; sat_extra=4; expect_pads('h080,0); sat_extra=8; expect_pads('h800,0);
        sat_extra=0; sat_l=1; expect_pads('h600,0);
        sat_digital=0; expect_pads(0,0);
        sat_digital=1; plugged=0; expect_pads(0,0); plugged=1;
        expect_pads('h600,0);
        // Abort an active scan and select another protocol.
        wait(!pins[4]); switch_mode(2);
        snes1=1; snes2=0; expect_pads('h010,0);
        wait(!pins[1]); @(negedge clk); reset=1; #0;
        if (pins!==7'h7f || {pad1,pad2}!==0) $fatal(1,"pins driven during reset");
        repeat(16) @(negedge clk); switch_mode(0);
        $display("PASS %0d SNAC pad cases including all pin-direction checks",checks);
        $finish;
    end
endmodule
