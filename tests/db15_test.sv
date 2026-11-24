`timescale 1ns/1ns
module db15_test;
    reg clk=0, reset=1, enable=0, connected=1;
    always #10 clk=!clk;
    wire [6:0] user_out;
    wire [11:0] pad1,pad2;
    wire nload,serial_clk,data_line;
    // Deliberately different propagation/rise times; a common-clock model
    // would hide LOAD/CLK races and sampling the bit after it's shifted.
    assign #(1100,5) nload = user_out[0];
    assign #(850,7) serial_clk = user_out[1];
    reg [23:0] contacts_n=24'hffffff;
    reg [23:0] shifter=24'hffffff;
    always @(negedge nload or posedge serial_clk)
        if (!nload) shifter <= contacts_n;
        else shifter <= {1'b1,shifter[23:1]};
    assign #(1040,40) data_line=connected ? shifter[0] : 1'b1;
    wire [6:0] user_in={1'b1,data_line,3'b111,serial_clk,nload};
    neogeo_snac_db15 dut(.*);
    reg [23:0] expected1[0:23];
    reg [23:0] expected2[0:23];
    integer count=0, previous_clocks=0, iterations=0;
    always @(posedge serial_clk) if(enable) count=count+1;
    always @(negedge nload) if(enable && !reset) begin
        if(iterations>0 && count-previous_clocks!=26) $fatal(1,"bad frame length %0d",count-previous_clocks);
        iterations=iterations+1;
        previous_clocks=count;
    end
    always @(negedge clk) if(user_out[6:2]!==5'b11111) $fatal(1,"unowned output");
    task frame;
        begin @(negedge nload); @(negedge nload); #400; end
    endtask
    task expect_pad(input [11:0] p1,input [11:0] p2);
        if(pad1!==p1 || pad2!==p2) $fatal(1,"expected=%h/%h actual=%h/%h input=%h",p1,p2,pad1,pad2,contacts_n);
    endtask
    integer i;
    initial begin
        // Ordered according to the physical six-button DB15 chain, beginning
        // at the immediately visible P1 D bit and ending at P2 A.
        for(i=0;i<24;i=i+1) begin expected1[i]=0;expected2[i]=0;end
        expected1[0]='h080; expected1[1]='h040;expected1[2]='h020;expected1[3]='h010;
        expected1[4]='h001; expected1[5]='h002;expected1[6]='h004;expected1[7]='h008;
        expected2[8]='h001; expected2[9]='h002;expected2[10]='h004;expected2[11]='h008;
        expected1[14]='h600;expected1[15]='h100;
        expected2[18]='h600;expected2[19]='h100;
        expected2[20]='h080;expected2[21]='h040;expected2[22]='h020;expected2[23]='h010;
        #2010;
        if(user_out!==7'h7f) $fatal(1,"inactive outputs");
        reset=0;enable=1;
        frame();expect_pad(0,0);
        for(i=0;i<24;i=i+1) begin
            contacts_n=~(24'd1<<i);frame();expect_pad(expected1[i],expected2[i]);
        end

        contacts_n=0;frame();expect_pad('h7ff,'h7ff);
        contacts_n=24'hffffff;frame();expect_pad(0,0);
        @(posedge nload); repeat(2) @(posedge serial_clk);
        contacts_n=0; @(negedge nload);
        repeat(16) @(posedge serial_clk);
        expect_pad(0,0); // no mixed-player intermediate report
        repeat(9) @(posedge serial_clk); #10; expect_pad('h7ff,'h7ff);
        connected=0; frame();expect_pad(0,0);
        connected=1; frame();expect_pad('h7ff,'h7ff);
        enable=0; @(negedge clk); @(posedge clk); #1;
        if(user_out!==7'h7f) $fatal(1,"disabled pins");
        expect_pad(0,0);
        iterations=0;enable=1;contacts_n=24'hffffff;
        frame(); expect_pad(0,0);
        reset=1; @(posedge clk); #1;
        if(user_out!==7'h7f) $fatal(1,"reset pins");
        expect_pad(0,0);
        $display("PASS: 26 clocks, 24 one-hot contacts, simultaneous and atomic 2P, released buttons, disconnect, reset and disable");
        $finish;
    end
endmodule
