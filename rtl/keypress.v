module keypress #(parameter integer STABLE_CYCLES=252000,LONG_CYCLES=20160000)(
 input wire clk,rst_n,key_n,output reg short_event,long_event
);
 wire up;
 level #(.CYCLES(STABLE_CYCLES)) debounce(clk,rst_n,key_n,up);
 localparam integer CW=LONG_CYCLES<2 ? 1 : $clog2(LONG_CYCLES);
 reg [CW-1:0] held;
 reg down,long_sent;
 always @(posedge clk)begin
  if(!rst_n)begin short_event<=0;long_event<=0;held<=0;down<=0;long_sent<=0;end
  else begin
   short_event<=0;long_event<=0;
   if(up)begin
    if(down && !long_sent)short_event<=1;
    held<=0;down<=0;long_sent<=0;
   end else begin
    down<=1;
    if(!long_sent)begin
     if(held==LONG_CYCLES-1)begin long_event<=1;long_sent<=1;end
     else held<=held+1'b1;
    end
   end
  end
 end
endmodule
