module top (
    input  wire       clk_50m,
    input  wire       sw_reset_run,
    input  wire       key1_n,
    input  wire       key2_n,
    input  wire       key3_n,
    input  wire       sw1_n,
    input  wire       sw2_n,
    input  wire       sw_audio_enable,
    input  wire       sd_miso,
    output wire       sd_cs_n,
    output wire       sd_sclk,
    output wire       sd_mosi,
    output wire       hdmi_ddc_scl,
    inout  wire       hdmi_ddc_sda,
    output wire [3:0] hdmi_tmds_p,
    output wire       status_pll_locked,
    output wire       status_image_ready,
    output wire       status_video_locked,
    output wire       status_fault
);
    wire pix_clk, serial_clk_5x, mem_clk, sdram_clk, pll_locked;
    wire reset_hold_n = sw_reset_run && pll_locked;
    reg [1:0] reset_sync;
    reg [1:0] mem_reset_sync;
    wire core_rst_n = reset_sync[1];
    wire [7:0] red, green, blue;
    wire video_de, video_hs, video_vs, video_sof, video_eol;
    wire audio_valid;
    wire signed [23:0] pcm_left, pcm_right;
    wire [2:0] image_number,display_slot,display_bank;
    wire [31:0] video_frames;
    wire [11:0] source_width,source_height;
    wire signed [23:0] sine_left,sine_right;wire sine_valid;
    wire [2:0] active_mode,hold_index_request,active_hold_index;
    wire tick_1ms,edit_active;
    wire transition;
    wire picture_switch,layers_visible;
    level mode_switch(.clk(pix_clk),.rst_n(core_rst_n),.raw(sw1_n),.stable(picture_switch));
    level overlay_switch(.clk(pix_clk),.rst_n(core_rst_n),.raw(sw2_n),.stable(layers_visible));
    wire core_fault,overlay_fault;
    wire [4:0] fault_code;
    wire [23:0] screen_rgb;
    wire screen_de,screen_sof,screen_eol;
    wire video_ready;
    wire [9:0] ch0, ch1, ch2, clk_lane;

    pll u_pll (
        .clk_50m(clk_50m), .reset(~sw_reset_run),
        .pix_clk(pix_clk), .serial_clk_5x(serial_clk_5x),
        .mem_clk(mem_clk),.sdram_clk(sdram_clk),
        .locked(pll_locked)
    );
    always @(posedge pix_clk or negedge reset_hold_n) begin
        if (!reset_hold_n) reset_sync <= 2'b00;
        else reset_sync <= {reset_sync[0], 1'b1};
    end
    always @(posedge mem_clk or negedge reset_hold_n) begin
        if(!reset_hold_n) mem_reset_sync<=0;
        else mem_reset_sync<={mem_reset_sync[0],1'b1};
    end

    core #(.VIDEO_FLOW_CONTROL(1)) player (
        .pix_clk(pix_clk), .rst_n(core_rst_n),
        .mem_clk(mem_clk),.mem_rst_n(mem_reset_sync[1]),.sdram_clk(sdram_clk),
        .next_key_n(key1_n), .auto_key_n(key3_n), .audio_enable(sw_audio_enable),
        .edit_active(edit_active),.tick_1ms(tick_1ms),
        .hold_index_request(hold_index_request),.active_hold_index(active_hold_index),
        .video_mode_request(!picture_switch),
        .video_sink_ready(video_ready),
        .sd_miso(sd_miso), .sd_cs_n(sd_cs_n),
        .sd_sclk(sd_sclk), .sd_mosi(sd_mosi),
        .red(red), .green(green), .blue(blue),
        .video_de(video_de), .video_hs(video_hs),
        .video_vs(video_vs), .video_sof(video_sof),
        .video_eol(video_eol),
        .audio_valid(audio_valid),
        .pcm_left(), .pcm_right(),
        .image_number(image_number),
        .display_slot(display_slot),.display_bank(display_bank),
        .video_frames(video_frames),
        .source_width(source_width),.source_height(source_height),.transition(transition),
        .image_ready(status_image_ready), .fault(core_fault),.fault_code(fault_code)
    );
    post display(
        .clk(pix_clk),.rst_n(core_rst_n),.key2_n(key2_n),.layers_visible(layers_visible),.audio_enable(sw_audio_enable),
        .in_rgb({red,green,blue}),.in_de(video_de),.in_sof(video_sof),
        .in_eol(video_eol),.in_hs(video_hs),.in_vs(video_vs),
        .display_slot(status_image_ready ? display_slot : image_number),.display_bank(display_bank),
        .video_frame_count(video_frames),
        .applied_hold_index(active_hold_index),.hold_index_request(hold_index_request),
        .tick_1ms(tick_1ms),.edit_active(edit_active),
        .source_width(source_width),.source_height(source_height),.transition(transition),
        .audio_valid(audio_valid),.sine_left(sine_left),.sine_right(sine_right),.sine_valid(sine_valid),
        .image_ready(status_image_ready),.fault_code(fault_code),
        .out_rgb(screen_rgb),.out_de(screen_de),.out_sof(screen_sof),
        .out_eol(screen_eol),.out_hs(),.out_vs(),
        .protocol_error(overlay_fault),.active_mode(active_mode),
        .active_brightness(),.active_contrast());
    hdmi bridge (
        .pix_clk(pix_clk), .rst_n(core_rst_n),
        .red(screen_rgb[23:16]), .green(screen_rgb[15:8]), .blue(screen_rgb[7:0]),
        .video_de(screen_de), .video_sof(screen_sof),
        .video_eol(screen_eol),
        .audio_valid(sine_valid),
        .pcm_left(sine_left), .pcm_right(sine_right),
        .video_ready(video_ready),
        .video_locked(status_video_locked),
        .ddc_scl(hdmi_ddc_scl), .ddc_sda(hdmi_ddc_sda),
        .tmds_ch0(ch0), .tmds_ch1(ch1),
        .tmds_ch2(ch2), .tmds_clk(clk_lane)
    );
    tmds serial (
        .pix_clk(pix_clk), .clk_5x(serial_clk_5x),
        .rst_n(core_rst_n), .ch0(ch0), .ch1(ch1),
        .ch2(ch2), .clk_lane(clk_lane), .tmds_p(hdmi_tmds_p)
    );
    assign status_pll_locked = pll_locked;
    assign status_fault = core_fault || overlay_fault;
endmodule
