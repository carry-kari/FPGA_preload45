module level #(parameter integer CYCLES=252000,DEFAULT=1)(
 input wire clk,rst_n,raw,output reg stable
);
 localparam integer CW=CYCLES<2 ? 1 : $clog2(CYCLES);
 reg meta,sync;
 reg [CW-1:0] count;
 always @(posedge clk)begin
  if(!rst_n)begin meta<=DEFAULT;sync<=DEFAULT;stable<=DEFAULT;count<=0;end
  else begin
   meta<=raw;sync<=meta;
   if(sync==stable)count<=0;
   else if(count==CYCLES-1)begin stable<=sync;count<=0;end
   else count<=count+1'b1;
  end
 end
endmodule
