module hdmi (
    input  wire        pix_clk,
    input  wire        rst_n,
    input  wire [7:0]  red,
    input  wire [7:0]  green,
    input  wire [7:0]  blue,
    input  wire        video_de,
    input  wire        video_sof,
    input  wire        video_eol,
    input  wire        audio_valid,
    input  wire [23:0] pcm_left,
    input  wire [23:0] pcm_right,
    output wire        video_ready,
    output wire        video_locked,
    output wire        ddc_scl,
    inout  wire        ddc_sda,
    output wire [9:0]  tmds_ch0,
    output wire [9:0]  tmds_ch1,
    output wire [9:0]  tmds_ch2,
    output wire [9:0]  tmds_clk
);
    reg [6:0] acr_sample_count;
    reg acr_valid;
    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            acr_sample_count <= 7'd0;
            acr_valid <= 1'b0;
        end else begin
            acr_valid <= 1'b0;
            if (audio_valid) begin
                acr_valid <= (acr_sample_count == 7'd0);
                acr_sample_count <= acr_sample_count + 7'd1;
            end
        end
    end

    // 25.2 MHz * 6144 / (128 * 48 kHz) = CTS 25200.
    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"),
        .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
        .VTOTAL(525), .VSA(2), .VFP(10), .VBP(33), .VACTIVE(480),
        .VIDEO_TPG("Disable"), .VIDEO_FORMAT("RGB"), .VIDEO_VIC(1),
        .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(126)
    ) tx_core (
        .I_pixel_clk(pix_clk), .I_rst(~rst_n),
        .I_edid_read_trig(1'b0),
        .O_edid_read_valid(), .O_edid_read_data(),
        .I_axis_s_user(video_sof & video_de),
        .I_axis_s_valid(video_de),
        .I_axis_s_last(video_eol & video_de),
        .I_axis_s_data({red, green, blue}),
        .O_axis_s_ready(video_ready),
        .I_audio_valid(audio_valid),
        .I_audio_left_data(pcm_left),
        .I_audio_right_data(pcm_right),
        .I_acr_valid(acr_valid),
        .I_acr_cts(20'd25200),
        .I_acr_n(20'd6144),
        .O_video_locked(video_locked),
        .O_ddc_scl(ddc_scl), .IO_ddc_sda(ddc_sda),
        .O_ch0_tmds_data(tmds_ch0),
        .O_ch1_tmds_data(tmds_ch1),
        .O_ch2_tmds_data(tmds_ch2),
        .O_clk_tmds_data(tmds_clk)
    );
endmodule
