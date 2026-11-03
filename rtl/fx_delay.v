module fx_delay #(parameter integer WIDTH=1, DEPTH=1)(
    input wire clk, rst_n,
    input wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout
);
    reg [WIDTH-1:0] pipe [0:DEPTH-1];
    integer i;
    always @(posedge clk) begin
        if(!rst_n) for(i=0;i<DEPTH;i=i+1) pipe[i]<=0;
        else begin
            pipe[0]<=din;
            for(i=1;i<DEPTH;i=i+1) pipe[i]<=pipe[i-1];
        end
    end
    assign dout=pipe[DEPTH-1];
endmodule
