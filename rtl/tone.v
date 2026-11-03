module tone #(
    parameter integer CYCLES_PER_SAMPLE = 525
) (
    input  wire               pix_clk,
    input  wire               rst_n,
    input  wire               enable,
    output reg                sample_valid,
    output reg signed [23:0] pcm_left,
    output reg signed [23:0] pcm_right
);
    localparam integer CW = CYCLES_PER_SAMPLE > 1 ? $clog2(CYCLES_PER_SAMPLE) : 1;
    reg [CW-1:0] divider;
    reg [5:0] phase;
    wire signed [23:0] tone = phase[5] ? -24'sd1048576 : 24'sd1048576;

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            divider <= 0;
            phase <= 6'd0;
            sample_valid <= 1'b0;
            pcm_left <= 24'sd0;
            pcm_right <= 24'sd0;
        end else begin
            sample_valid <= (divider == CYCLES_PER_SAMPLE - 1);
            if (divider == CYCLES_PER_SAMPLE - 1) begin
                divider <= 0;
                phase <= phase + 6'd1;
                pcm_left <= enable ? tone : 24'sd0;
                pcm_right <= enable ? tone : 24'sd0;
            end else divider <= divider + 1'b1;
        end
    end
endmodule
