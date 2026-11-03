module jidct(
 input wire clk,rst_n,clear,we,start,
 input wire [5:0] addr,input wire signed [23:0] coefficient,
 output reg busy,valid,done,output reg [5:0] pixel_index,output reg [7:0] sample
);
 localparam IDLE=0,RUN=1,TAIL=2,DC1=3,DC2=4,DC3=5,DCOUT=6;
 reg [2:0] state,line,k;
 reg pass,ac_seen;
 reg [63:0] coeff_valid;
 reg signed [23:0] coeff[0:63],temp[0:63];
 reg signed [43:0] even_accum[0:3],odd_accum[0:3];
 wire [5:0] input_index={line,k};
 wire signed [23:0] operand=pass ? temp[{k,line}] : coeff_valid[input_index] ? coeff[input_index] : 24'sd0;
 wire signed [37:0] product[0:3];
 wire signed [43:0] odd_total[0:3],forward_total[0:3],mirror_total[0:3];
 reg [7:0] queued_sample[0:7];
 reg [5:0] queued_index[0:7];
 reg [3:0] remaining;
 reg [2:0] read_pointer;
 reg signed [39:0] dc_scaled;
 reg signed [23:0] dc_temp;
 reg [7:0] uniform;
 reg [5:0] dc_index;
 function signed [13:0] cosine;
 input [2:0] x,u;
 begin case({x,u})
 0:cosine=2896;1:cosine=4017;2:cosine=3784;3:cosine=3406;4:cosine=2896;5:cosine=2276;6:cosine=1567;7:cosine=799;
 8:cosine=2896;9:cosine=3406;10:cosine=1567;11:cosine=-799;12:cosine=-2896;13:cosine=-4017;14:cosine=-3784;15:cosine=-2276;
 16:cosine=2896;17:cosine=2276;18:cosine=-1567;19:cosine=-4017;20:cosine=-2896;21:cosine=799;22:cosine=3784;23:cosine=3406;
 24:cosine=2896;25:cosine=799;26:cosine=-3784;27:cosine=-2276;28:cosine=2896;29:cosine=3406;30:cosine=-1567;31:cosine=-4017;
 32:cosine=2896;33:cosine=-799;34:cosine=-3784;35:cosine=2276;36:cosine=2896;37:cosine=-3406;38:cosine=-1567;39:cosine=4017;
 40:cosine=2896;41:cosine=-2276;42:cosine=-1567;43:cosine=4017;44:cosine=-2896;45:cosine=-799;46:cosine=3784;47:cosine=-3406;
 48:cosine=2896;49:cosine=-3406;50:cosine=1567;51:cosine=799;52:cosine=-2896;53:cosine=4017;54:cosine=-3784;55:cosine=2276;
 56:cosine=2896;57:cosine=-4017;58:cosine=3784;59:cosine=-3406;60:cosine=2896;61:cosine=-2276;62:cosine=1567;default:cosine=-799;
 endcase end endfunction
 function signed [39:0] m2896;
 input signed [23:0] n;reg signed [39:0] x;
 begin x=n;m2896=(x<<<11)+(x<<<10)-(x<<<7)-(x<<<6)+(x<<<4);end endfunction
 function [7:0] clip;input signed [43:0] n;
 begin clip=n<0 ? 0 : n>255 ? 255 : n[7:0];end endfunction
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:mac
  localparam [2:0] ID=lane;
  assign product[lane]=operand*cosine(ID,k);
  assign odd_total[lane]=odd_accum[lane]+product[lane];
  assign forward_total[lane]=even_accum[lane]+odd_total[lane];
  assign mirror_total[lane]=even_accum[lane]-odd_total[lane];
 end endgenerate
 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;valid<=0;done<=0;pixel_index<=0;sample<=0;
   coeff_valid<=0;ac_seen<=0;pass<=0;line<=0;k<=0;
   remaining<=0;read_pointer<=0;dc_scaled<=0;dc_temp<=0;uniform<=0;dc_index<=0;
   for(i=0;i<4;i=i+1)begin even_accum[i]<=0;odd_accum[i]<=0;end
  end else begin
   valid<=0;done<=0;
   if(clear && !busy)begin coeff_valid<=0;ac_seen<=0;end
   else if(we && !busy)begin
    coeff[addr]<=coefficient;coeff_valid[addr]<=1;
    if(addr!=0 && coefficient!=0)ac_seen<=1;
   end
   // A new eight-pixel group replaces the queue on the same edge that reads
   // the previous group's final pixel. Nonblocking assignments preserve it.
   if(remaining!=0)begin
    valid<=1;sample<=queued_sample[read_pointer];pixel_index<=queued_index[read_pointer];
    read_pointer<=read_pointer+1'b1;remaining<=remaining-1'b1;
    if(state==TAIL && remaining==1)begin done<=1;busy<=0;state<=IDLE;end
   end
   if(start && !busy)begin
    busy<=1;pass<=0;line<=0;k<=0;remaining<=0;dc_index<=0;
    for(i=0;i<4;i=i+1)begin even_accum[i]<=0;odd_accum[i]<=0;end
    if(!ac_seen)begin dc_scaled<=m2896(coeff_valid[0] ? coeff[0] : 24'sd0);state<=DC1;end
    else state<=RUN;
   end else case(state)
    RUN:begin
     if(k==7)begin
      k<=0;
      for(i=0;i<4;i=i+1)begin
       even_accum[i]<=0;odd_accum[i]<=0;
       if(!pass)begin
        temp[{line,i[2:0]}]<=(forward_total[i]+44'sd2048)>>>12;
        temp[{line,(3'd7-i[2:0])}]<=(mirror_total[i]+44'sd2048)>>>12;
       end else begin
        queued_sample[i]<=clip(((forward_total[i]+44'sd8192)>>>14)+44'sd128);
        queued_sample[i+4]<=clip(((mirror_total[i]+44'sd8192)>>>14)+44'sd128);
        queued_index[i]<={i[2:0],line};
        queued_index[i+4]<={(3'd7-i[2:0]),line};
       end
      end
      if(pass)begin remaining<=8;read_pointer<=0;end
      if(line==7)begin line<=0;if(pass)state<=TAIL;else pass<=1;end
      else line<=line+1'b1;
     end else begin
      k<=k+1'b1;
      for(i=0;i<4;i=i+1)
       if(k[0])odd_accum[i]<=odd_total[i];
       else even_accum[i]<=even_accum[i]+product[i];
     end
    end
    DC1:begin dc_temp<=(dc_scaled+44'sd2048)>>>12;state<=DC2;end
    DC2:begin dc_scaled<=m2896(dc_temp);state<=DC3;end
    DC3:begin uniform<=clip(((dc_scaled+44'sd8192)>>>14)+44'sd128);state<=DCOUT;end
    DCOUT:begin
     valid<=1;sample<=uniform;pixel_index<=dc_index;
     if(dc_index==63)begin done<=1;busy<=0;state<=IDLE;end else dc_index<=dc_index+1'b1;
    end
   endcase
  end
 end
endmodule
