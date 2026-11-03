module fx_coords #(
    parameter integer WIDTH=640,HEIGHT=480
)(
    input wire clk,rst_n,de,sof,eol,vs,
    output wire [9:0] x,y,
    output reg frame_commit,locked,protocol_error
);
    reg [9:0] cx,cy;
    reg previous_vs,need_sof;
    assign x=de && sof ? 10'd0 : cx;
    assign y=de && sof ? 10'd0 : cy;
    always @(posedge clk) begin
        if(!rst_n) begin
            cx<=0;cy<=0;previous_vs<=1;frame_commit<=0;
            locked<=0;protocol_error<=0;need_sof<=1;
        end else begin
            previous_vs<=vs;
          
            frame_commit<=previous_vs && !vs;
            if(de && sof) begin
                if((locked && !need_sof) || eol) protocol_error<=1;
                cx<=1;cy<=0;locked<=1;need_sof<=0;
            end else if(de && locked) begin
                if(need_sof || (eol && cx!=WIDTH-1) || (!eol && cx==WIDTH-1))
                    protocol_error<=1;
                if(eol) begin
                    cx<=0;
                    if(cy==HEIGHT-1) begin cy<=0;need_sof<=1;end
                    else cy<=cy+1'b1;
                end else cx<=cx+1'b1;
            end
        end
    end
endmodule
