module fifo #(
    parameter integer WIDTH=44,
    parameter integer ABITS=8
)(
    input wire wclk, wrst_n, wvalid,
    input wire [WIDTH-1:0] wdata,
    output wire full,
    input wire rclk, rrst_n, pop,
    output wire empty,
    output reg valid,
    output reg [WIDTH-1:0] data
);
    reg [WIDTH-1:0] mem[0:(1<<ABITS)-1];
    reg [ABITS:0] wp, rp, wg, rg;
    (* async_reg="true" *) reg [ABITS:0] rg_meta, rg_sync, wg_meta, wg_sync;
    wire [ABITS:0] wnext=wp+1'b1, rnext=rp+1'b1;
    assign full=wg=={~rg_sync[ABITS:ABITS-1],rg_sync[ABITS-2:0]};
    assign empty=rg==wg_sync;
    always @(posedge wclk) if(wvalid && !full) mem[wp[ABITS-1:0]]<=wdata;
    always @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) begin wp<=0;wg<=0;rg_meta<=0;rg_sync<=0;end
        else begin
            rg_meta<=rg; rg_sync<=rg_meta;
            if(wvalid && !full) begin wp<=wnext;wg<=(wnext>>1)^wnext;end
        end
    end
    always @(posedge rclk) if(pop && !empty) data<=mem[rp[ABITS-1:0]];
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) begin rp<=0;rg<=0;wg_meta<=0;wg_sync<=0;valid<=0;end
        else begin
            wg_meta<=wg;wg_sync<=wg_meta;valid<=pop && !empty;
            if(pop && !empty) begin rp<=rnext;rg<=(rnext>>1)^rnext;end
        end
    end
endmodule
