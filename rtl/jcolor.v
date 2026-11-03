
module jcolor(input wire [7:0] y,cb,cr,output wire [23:0] rgb);
    wire signed [23:0] u=$signed({1'b0,cb})-24'sd128;
    wire signed [23:0] v=$signed({1'b0,cr})-24'sd128;
    wire signed [23:0] vr=(v<<<8)+(v<<<6)+(v<<<5)+(v<<<2)+(v<<<1)+v;
    wire signed [23:0] ug=(u<<<6)+(u<<<4)+(u<<<3);
    wire signed [23:0] vg=(v<<<7)+(v<<<5)+(v<<<4)+(v<<<2)+(v<<<1)+v;
    wire signed [23:0] ub=(u<<<9)-(u<<<6)+(u<<<3)-(u<<<1);
    wire signed [23:0] r=$signed({1'b0,y})+((vr+24'sd128)>>>8);
    wire signed [23:0] g=$signed({1'b0,y})-((ug+vg+24'sd128)>>>8);
    wire signed [23:0] b=$signed({1'b0,y})+((ub+24'sd128)>>>8);
    function [7:0] clip;input signed [23:0] n;begin clip=n<0 ? 0 : n>255 ? 255 : n[7:0];end endfunction
    assign rgb={clip(r),clip(g),clip(b)};
endmodule
