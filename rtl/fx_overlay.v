module fx_overlay #(
    parameter integer CLK_HZ=25200000,
    parameter integer DEBOUNCE_CYCLES=252000,
    parameter integer EVENT_CONTROL=0,
    parameter integer SCROLL_MS=33,//speed
    parameter [1023:0] MESSAGE={"CHIPS WITHOUT LIMITS, BEYOND THE UNSEEN. SHANGHAI ANLOGIC INFOTECH CO., LTD. WELCOMES YOU.", {38{8'h20}}}
)(
    input wire clk,rst_n,
    input wire key_n,sw1_n,sw2_n,
    input wire mode_event,step_event,
    input wire frame_commit,
    input wire adjust_enable,subtitle_enable,osd_enable,
    input wire [23:0] in_rgb,
    input wire [9:0] in_x,in_y,
    input wire in_de,in_sof,in_eol,in_hs,in_vs,
    
    input wire [23:0] wave_rgb,
    input wire [8:0] wave_alpha,
    input wire wave_valid,
   
    input wire [2:0] display_slot,
    input wire [11:0] source_width,source_height,
    input wire [4:0] fault_code,
    input wire image_ready,
    input wire [2:0] front_bank,
    input wire transition,
    input wire [7:0] fps_bcd,
    input wire [2:0] applied_hold_index,
    output wire next_req,edit_active,tick_1ms,
    output wire [2:0] active_mode,
    output wire [2:0] hold_index_request,
    output wire signed [8:0] active_brightness,
    output wire [9:0] active_contrast,
    output wire [23:0] out_rgb,
    output wire [9:0] out_x,out_y,
    output wire out_de,out_sof,out_eol,out_hs,out_vs,
    output wire active_subtitle_bottom
);
    wire kp,mp,sp;
    wire [2:0] mode;
    wire [2:0] bi,ci;
    wire [23:0] live_time;
    wire [9:0] live_scroll;
    reg commit_d;
    reg [23:0] snap_time;
    reg [9:0] snap_scroll;
    reg [2:0] snap_slot;
    reg [11:0] snap_w,snap_h;
    reg [4:0] snap_fault;
    reg [2:0] snap_bank;
    reg [7:0] snap_fps;
    reg [2:0] snap_hold_index;
    reg snap_ready,snap_transition,adj_en,sub_en,osd_en;
    fx_button #(.CYCLES(DEBOUNCE_CYCLES)) bk(clk,rst_n,key_n,kp);
    fx_button #(.CYCLES(DEBOUNCE_CYCLES)) bm(clk,rst_n,sw1_n,mp);
    fx_button #(.CYCLES(DEBOUNCE_CYCLES)) bs(clk,rst_n,sw2_n,sp);
    fx_ui #(.KEY2_CONTROL(EVENT_CONTROL)) ui(clk,rst_n,frame_commit,kp,
             EVENT_CONTROL ? mode_event : mp,EVENT_CONTROL ? step_event : sp,next_req,edit_active,
             mode,active_mode,bi,ci,active_brightness,active_contrast,
             active_subtitle_bottom,hold_index_request);
    fx_clock #(.CLK_HZ(CLK_HZ),.SCROLL_MS(SCROLL_MS)) timer(
        clk,rst_n,tick_1ms,live_time,live_scroll);
    always @(posedge clk) begin
        if(!rst_n) begin
            commit_d<=0; snap_time<=0; snap_scroll<=0; snap_slot<=0;
            snap_w<=640; snap_h<=480; snap_fault<=0; snap_ready<=0;
            snap_bank<=0; snap_transition<=0; adj_en<=1; sub_en<=0; osd_en<=0;
            snap_fps<=0;
            snap_hold_index<=2;
        end else begin
            commit_d<=frame_commit;
            if(frame_commit) begin
                adj_en<=adjust_enable; sub_en<=subtitle_enable; osd_en<=osd_enable;
            end
            if(commit_d) begin
                snap_time<=live_time; snap_scroll<=live_scroll;
                snap_slot<=display_slot; snap_w<=source_width; snap_h<=source_height;
                snap_fault<=fault_code; snap_ready<=image_ready;
                snap_bank<=front_bank; snap_transition<=transition;
                snap_fps<=fps_bcd;
                snap_hold_index<=applied_hold_index;
            end
        end
    end
    wire [23:0] adjusted,wave_mix,sub_mix;
    wire [24:0] meta2;
    wire [9:0] x2,y2;
    wire de2,sof2,eol2,hs2,vs2;
    wire [33:0] wave2,sub0,sub2,osd0,osd4;
    wire [23:0] sr,orr;
    wire [8:0] sa,oa;
    wire sv,ov;
    fx_adjust adjust(clk,rst_n,in_rgb,adj_en ? active_brightness : 9'sd0,
                     adj_en ? active_contrast : 10'd256,adjusted);
    fx_delay #(.WIDTH(25),.DEPTH(2)) dm2(clk,rst_n,
        {in_x,in_y,in_de,in_sof,in_eol,in_hs,in_vs},meta2);
    assign {x2,y2,de2,sof2,eol2,hs2,vs2}=meta2;
    fx_delay #(.WIDTH(34),.DEPTH(2)) dw(clk,rst_n,
        {wave_rgb,wave_alpha,wave_valid && in_de},wave2);
    fx_text #(.MESSAGE(MESSAGE)) text_layer(
        x2,y2,de2,sub_en,osd_en,snap_scroll,snap_time,active_mode,bi,ci,
        snap_slot,snap_w,snap_h,snap_fault,snap_ready,snap_bank,snap_transition,
        active_subtitle_bottom,snap_fps,snap_hold_index,
        sr,orr,sa,oa,sv,ov);
    assign sub0={sr,sa,sv};
    assign osd0={orr,oa,ov};
    fx_delay #(.WIDTH(34),.DEPTH(2)) ds(clk,rst_n,sub0,sub2);
    fx_delay #(.WIDTH(34),.DEPTH(4)) dos(clk,rst_n,osd0,osd4);
    fx_blend bw(clk,rst_n,adjusted,wave2[33:10],wave2[9:1],wave2[0],wave_mix);
    fx_blend bt(clk,rst_n,wave_mix,sub2[33:10],sub2[9:1],sub2[0],sub_mix);
    wire [23:0] final_rgb;
    fx_blend bo(clk,rst_n,sub_mix,osd4[33:10],osd4[9:1],osd4[0],final_rgb);
    fx_delay #(.WIDTH(25),.DEPTH(6)) dm6(clk,rst_n,meta2,
        {out_x,out_y,out_de,out_sof,out_eol,out_hs,out_vs});
    assign out_rgb=out_de ? final_rgb : 24'd0;
endmodule
