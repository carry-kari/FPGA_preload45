module post #(
    parameter integer SW_STABLE_CYCLES=252000,KEY_LONG_CYCLES=20160000,FPS_CLK_HZ=25200000,CLK_HZ=25200000
)(
    input wire clk,rst_n,key2_n,layers_visible,audio_enable,
    input wire [23:0] in_rgb,input wire in_de,in_sof,in_eol,in_hs,in_vs,
    input wire [2:0] display_slot,display_bank,
    input wire [31:0] video_frame_count,input wire [2:0] applied_hold_index,
    input wire [11:0] source_width,source_height,
    input wire transition,audio_valid,image_ready,input wire [4:0] fault_code,
    output wire [23:0] out_rgb,output wire out_de,out_sof,out_eol,out_hs,out_vs,protocol_error,
    output wire [2:0] active_mode,hold_index_request,output wire tick_1ms,edit_active,
    output wire signed [8:0] active_brightness,output wire [9:0] active_contrast,
    output wire signed [23:0] sine_left,sine_right,output wire sine_valid
);
    wire [23:0] rgb;wire de,sof,eol,hs,vs,visible,screen_error,scope_error;
    screen #(.SW_STABLE_CYCLES(SW_STABLE_CYCLES),.KEY_LONG_CYCLES(KEY_LONG_CYCLES),.FPS_CLK_HZ(FPS_CLK_HZ),.CLK_HZ(CLK_HZ)) osd(
        .clk(clk),.rst_n(rst_n),.key2_n(key2_n),.layers_visible(layers_visible),
        .in_rgb(in_rgb),.in_de(in_de),.in_sof(in_sof),.in_eol(in_eol),.in_hs(in_hs),.in_vs(in_vs),
        .display_slot(display_slot),.display_bank(display_bank),.video_frame_count(video_frame_count),
        .applied_hold_index(applied_hold_index),.source_width(source_width),.source_height(source_height),
        .transition(transition),.audio_valid(audio_valid),.pcm_left(sine_left),.pcm_right(sine_right),
        .image_ready(image_ready),.fault_code(fault_code!=0 ? fault_code : scope_error ? 5'd19 : 5'd0),.out_rgb(rgb),.out_de(de),.out_sof(sof),.out_eol(eol),
        .out_hs(hs),.out_vs(vs),.protocol_error(screen_error),.active_layers_visible(visible),
        .active_mode(active_mode),.hold_index_request(hold_index_request),.tick_1ms(tick_1ms),.edit_active(edit_active),
        .active_brightness(active_brightness),.active_contrast(active_contrast));
    fx_audio_vis #(.EXTERNAL_VISIBILITY(1)) audio(.clk(clk),.rst_n(rst_n),.key3_n(1'b1),
        .audio_valid(audio_valid),.audio_enable(audio_enable),.visibility_enable(visible),
        .in_rgb(rgb),.in_de(de),.in_sof(sof),.in_eol(eol),.in_hs(hs),.in_vs(vs),
        .sine_left(sine_left),.sine_right(sine_right),.sine_valid(sine_valid),.out_rgb(out_rgb),
        .out_de(out_de),.out_sof(out_sof),.out_eol(out_eol),.out_hs(out_hs),.out_vs(out_vs),.protocol_error(scope_error));
    assign protocol_error=screen_error || scope_error;
endmodule
