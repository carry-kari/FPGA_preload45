module fx_blend(
    input wire clk, rst_n,
    input wire [23:0] bg, fg,
    input wire [8:0] alpha,
    input wire valid,
    output reg [23:0] mixed
);
    wire [8:0] a= !valid ? 9'd0 : alpha>256 ? 9'd256 : alpha;
    wire [8:0] inv=9'd256-a;
    reg [17:0] r,g,b;
    always @(posedge clk) begin
        if(!rst_n) begin r<=0; g<=0; b<=0; mixed<=0; end
        else begin
            r<=bg[23:16]*inv+fg[23:16]*a+18'd128;
            g<=bg[15:8]*inv+fg[15:8]*a+18'd128;
            b<=bg[7:0]*inv+fg[7:0]*a+18'd128;
            mixed<={r[15:8],g[15:8],b[15:8]};
        end
    end
endmodule
