module fx_clock #(
    parameter integer CLK_HZ=25200000,
    parameter integer SCROLL_MS=33
)(
    input wire clk, rst_n,
    output wire tick_1ms,
    output reg [23:0] uptime_bcd,
    output reg [9:0] scroll
);
    localparam integer DIV=CLK_HZ/1000;
    localparam integer CW=(DIV<2) ? 1 : $clog2(DIV);
    localparam integer SW=(SCROLL_MS<2) ? 1 : $clog2(SCROLL_MS);
    reg [CW-1:0] divider;
    reg [9:0] millis;
    reg [SW-1:0] scroll_ms;
    assign tick_1ms = rst_n && divider==DIV-1;
    always @(posedge clk) begin
        if (!rst_n) begin
            divider<=0; millis<=0; scroll_ms<=0; uptime_bcd<=0; scroll<=0;
        end else if (tick_1ms) begin
            divider<=0;
            if(scroll_ms==SCROLL_MS-1) begin scroll_ms<=0; scroll<=scroll+1'b1; end
            else scroll_ms<=scroll_ms+1'b1;
            if(millis==999) begin
                millis<=0;
                if(uptime_bcd[3:0]!=9) uptime_bcd[3:0]<=uptime_bcd[3:0]+1'b1;
                else begin
                    uptime_bcd[3:0]<=0;
                    if(uptime_bcd[7:4]!=5) uptime_bcd[7:4]<=uptime_bcd[7:4]+1'b1;
                    else begin
                        uptime_bcd[7:4]<=0;
                        if(uptime_bcd[11:8]!=9) uptime_bcd[11:8]<=uptime_bcd[11:8]+1'b1;
                        else begin
                            uptime_bcd[11:8]<=0;
                            if(uptime_bcd[15:12]!=5) uptime_bcd[15:12]<=uptime_bcd[15:12]+1'b1;
                            else begin
                                uptime_bcd[15:12]<=0;
                                if(uptime_bcd[19:16]!=9) uptime_bcd[19:16]<=uptime_bcd[19:16]+1'b1;
                                else begin
                                    uptime_bcd[19:16]<=0;
                                    uptime_bcd[23:20]<=uptime_bcd[23:20]==9 ? 0 : uptime_bcd[23:20]+1'b1;
                                end
                            end
                        end
                    end
                end
            end else millis<=millis+1'b1;
        end else divider<=divider+1'b1;
    end
endmodule
