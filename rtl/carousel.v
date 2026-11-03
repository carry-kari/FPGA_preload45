module carousel #(
 parameter integer HOLD_FRAMES=300,FADE_STEP=16,MILLISECOND_MODE=0
)(
 input wire clk,rst_n,blank,enable,edit_active,next_event,video_available,
 input wire toggle_event,
 input wire tick_1ms,input wire [2:0] hold_index_request,
 output reg [2:0] item,output reg [8:0] gain,
 output wire transition,output reg consume,output reg auto_running,
 output reg [2:0] active_hold_index
);
 reg [1:0] state;
 reg [15:0] hold_count,pending;
 reg [15:0] hold_limit_ms;
 reg toggle_pending;
 assign transition=state!=0;
 
 wire toggle_now=toggle_pending ^ (toggle_event && enable);
 wire run_at_blank=auto_running ^ toggle_now;
 wire [2:0] requested_index=hold_index_request<=5 ? hold_index_request : 3'd2;
 wire setting_changed=requested_index!=active_hold_index;
 wire expired=MILLISECOND_MODE ?
  (hold_count>=hold_limit_ms || (tick_1ms && hold_count==hold_limit_ms-1'b1)) :
  hold_count>=HOLD_FRAMES-1;
 wire request=pending!=0 || next_event ||
  (run_at_blank && !toggle_now && !edit_active && !setting_changed && expired);
 function [15:0] duration_ms;
  input [2:0] index;
  begin case(index)
   0:duration_ms=2000;1:duration_ms=3000;2:duration_ms=5000;
   3:duration_ms=10000;4:duration_ms=15000;5:duration_ms=30000;
   default:duration_ms=5000;
  endcase end
 endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;item<=0;gain<=256;hold_count<=0;pending<=0;consume<=0;
   auto_running<=1;toggle_pending<=0;
   active_hold_index<=2;hold_limit_ms<=5000;
  end
  else begin
   consume<=0;
   
   if(MILLISECOND_MODE)begin
    if(!enable || !auto_running || edit_active || state!=0)hold_count<=0;
    else if(tick_1ms && hold_count<hold_limit_ms)hold_count<=hold_count+1'b1;
   end
   if(blank && setting_changed)begin
    active_hold_index<=requested_index;hold_limit_ms<=duration_ms(requested_index);hold_count<=0;
   end
   if(toggle_event && enable)toggle_pending<=!toggle_pending;
   if(next_event && enable && pending!=65535)pending<=pending+1'b1;
   if(blank && !enable)begin
    state<=0;gain<=256;hold_count<=0;pending<=0;toggle_pending<=0;
   end
   else if(blank && enable)begin
    auto_running<=run_at_blank;
    toggle_pending<=0;
    case(state)
    0:begin
     if(!run_at_blank || toggle_now || edit_active || setting_changed)hold_count<=0;
     else if(!MILLISECOND_MODE && hold_count!=65535)hold_count<=hold_count+1'b1;
     if(request)begin state<=1;hold_count<=0;
      if(pending!=0 || next_event)begin consume<=1;if(pending!=0 && !next_event)pending<=pending-1'b1;else if(pending==0)pending<=0;else pending<=pending;end
     end
    end
    1:if(gain<=FADE_STEP)begin gain<=0;item<=item==3 ? 0 : item+1'b1;state<=2;end
      else gain<=gain-FADE_STEP;
    2:if(gain>=256-FADE_STEP)begin gain<=256;state<=0;end else gain<=gain+FADE_STEP;
    endcase
   end
  end
 end
endmodule
