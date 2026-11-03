module fps #(parameter integer CLK_HZ=25200000)(
 input wire clk,rst_n,video_active,
 input wire [31:0] frame_count,
 output reg [7:0] fps_bcd
);
 localparam integer CW=CLK_HZ>1 ? $clog2(CLK_HZ) : 1;
 reg [CW-1:0] clocks;
 reg [31:0] previous_frames;
 reg [7:0] count_bcd;
 wire new_frame=frame_count!=previous_frames;
 wire [7:0] incremented=count_bcd==8'h99 ? 8'h99 :
       count_bcd[3:0]==9 ? {count_bcd[7:4]+4'd1,4'd0} : count_bcd+8'd1;
 wire [7:0] count_next=new_frame ? incremented : count_bcd;
 always @(posedge clk)begin
  if(!rst_n)begin clocks<=0;previous_frames<=0;count_bcd<=0;fps_bcd<=0;end
  else begin
   previous_frames<=frame_count;
   if(!video_active)begin clocks<=0;count_bcd<=0;fps_bcd<=0;end
   else if(clocks==CLK_HZ-1)begin clocks<=0;fps_bcd<=count_next;count_bcd<=0;end
   else begin clocks<=clocks+1'b1;count_bcd<=count_next;end
  end
 end
endmodule
