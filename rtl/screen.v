module screen #(
    parameter integer SW_STABLE_CYCLES=252000,KEY_LONG_CYCLES=20160000,FPS_CLK_HZ=25200000,CLK_HZ=25200000
)(
    input wire clk,rst_n,key2_n,layers_visible,
    input wire [23:0] in_rgb,
    input wire in_de,in_sof,in_eol,in_hs,in_vs,
    input wire [2:0] display_slot,
    input wire [2:0] display_bank,
    input wire [31:0] video_frame_count,
    input wire [2:0] applied_hold_index,
    input wire [11:0] source_width,source_height,
    input wire transition,audio_valid,
    input wire signed [23:0] pcm_left,pcm_right,
    input wire image_ready,
    input wire [4:0] fault_code,
    output wire [23:0] out_rgb,
    output wire out_de,out_sof,out_eol,out_hs,out_vs,
    output wire protocol_error,
    output wire active_layers_visible,
    output wire [2:0] active_mode,
    output wire [2:0] hold_index_request,
    output wire tick_1ms,edit_active,
    output wire signed [8:0] active_brightness,
    output wire [9:0] active_contrast
);
    wire [9:0] x,y,out_x,out_y;
    wire frame_commit,coords_locked,next_req;
    wire [4:0] diagnostic_fault;
    wire [23:0] wave_rgb;
    wire [8:0] wave_alpha;
    wire wave_valid;
    wire [7:0] measured_fps;
    fps #(.CLK_HZ(FPS_CLK_HZ)) stats(.clk(clk),.rst_n(rst_n),
        .video_active(display_slot==4 && image_ready),.frame_count(video_frame_count),.fps_bcd(measured_fps));
    wire key_short,key_long;
    reg show_wave;
    keypress #(.STABLE_CYCLES(SW_STABLE_CYCLES),.LONG_CYCLES(KEY_LONG_CYCLES)) controls(
        .clk(clk),.rst_n(rst_n),.key_n(key2_n),.short_event(key_short),.long_event(key_long));
    always @(posedge clk)begin
        if(!rst_n)show_wave<=0;
        else if(frame_commit)show_wave<=layers_visible;
    end
    assign active_layers_visible=show_wave;
    assign wave_rgb=0;assign wave_alpha=0;assign wave_valid=0;
    /* waveform wave(.clk(clk),.rst_n(rst_n),.blank(frame_commit),.sample_valid(audio_valid),
        .pcm_left(pcm_left),.pcm_right(pcm_right),.x(x),.y(y),.de(in_de),
        .rgb(wave_rgb),.alpha(wave_alpha),.valid(wave_valid)); */
    // Preserve core errors; report a sticky coordinate error as ERR 19 in OSD.
    assign diagnostic_fault = fault_code != 0 ? fault_code : protocol_error ? 5'd19 : 5'd0;
    fx_coords coords(
        .clk(clk),.rst_n(rst_n),.de(in_de),.sof(in_sof),.eol(in_eol),.vs(in_vs),
        .x(x),.y(y),.frame_commit(frame_commit),.locked(coords_locked),
        .protocol_error(protocol_error));
    fx_overlay #(.CLK_HZ(CLK_HZ),.DEBOUNCE_CYCLES(SW_STABLE_CYCLES),.EVENT_CONTROL(1)) effects(
        .clk(clk),.rst_n(rst_n),.key_n(1'b1),.sw1_n(1'b1),.sw2_n(1'b1),
        .mode_event(key_long),.step_event(key_short),
        .frame_commit(frame_commit),
        .adjust_enable(1'b1),.subtitle_enable(1'b1),.osd_enable(layers_visible),
        .in_rgb(in_rgb),.in_x(x),.in_y(y),.in_de(in_de),
        .in_sof(in_sof),.in_eol(in_eol),.in_hs(in_hs),.in_vs(in_vs),
        .wave_rgb(wave_rgb),.wave_alpha(wave_alpha),.wave_valid(wave_valid && show_wave),
        .display_slot(display_slot),.source_width(source_width),.source_height(source_height),
        .fault_code(diagnostic_fault),.image_ready(image_ready),
        .front_bank(display_bank),.transition(transition),
        .fps_bcd(measured_fps),
        .applied_hold_index(applied_hold_index),.hold_index_request(hold_index_request),
        .next_req(next_req),.edit_active(edit_active),.tick_1ms(tick_1ms),
        .active_mode(active_mode),.active_brightness(active_brightness),
        .active_contrast(active_contrast),.active_subtitle_bottom(),
        .out_rgb(out_rgb),.out_x(out_x),.out_y(out_y),
        .out_de(out_de),.out_sof(out_sof),.out_eol(out_eol),.out_hs(out_hs),.out_vs(out_vs));
endmodule
