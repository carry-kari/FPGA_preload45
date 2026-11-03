module fx_adjust(
    input wire clk, rst_n,
    input wire [23:0] rgb,
    input wire signed [8:0] brightness,
    input wire [9:0] contrast,
    output reg [23:0] adjusted
);
    reg signed [19:0] pr, pg, pb;
    reg signed [8:0] b;
    wire signed [9:0] r=$signed({1'b0,rgb[23:16]})-10'sd128;
    wire signed [9:0] g=$signed({1'b0,rgb[15:8]})-10'sd128;
    wire signed [9:0] bl=$signed({1'b0,rgb[7:0]})-10'sd128;
    function [7:0] finish;
        input signed [19:0] p;
        input signed [8:0] offset;
        reg signed [20:0] value;
        begin
            value=($signed(p) >>> 8)+21'sd128+$signed(offset);
            finish=value<0 ? 0 : value>255 ? 255 : value[7:0];
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin pr<=0; pg<=0; pb<=0; b<=0; adjusted<=0; end
        else begin
            pr<=r*$signed({1'b0,contrast});
            pg<=g*$signed({1'b0,contrast});
            pb<=bl*$signed({1'b0,contrast}); b<=brightness;
            adjusted<={finish(pr,b),finish(pg,b),finish(pb,b)};
        end
    end
endmodule
