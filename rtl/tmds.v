module tmds (
    input  wire       pix_clk,
    input  wire       clk_5x,
    input  wire       rst_n,
    input  wire [9:0] ch0,
    input  wire [9:0] ch1,
    input  wire [9:0] ch2,
    input  wire [9:0] clk_lane,
    output wire [3:0] tmds_p
);
    (* async_reg = "true" *) reg [1:0] serial_reset_sync;
    wire serial_rst_n = serial_reset_sync[1];
    always @(posedge clk_5x or negedge rst_n) begin
        if (!rst_n) serial_reset_sync <= 2'b00;
        else serial_reset_sync <= {serial_reset_sync[0], 1'b1};
    end
    (* async_reg = "true" *) reg pix_meta, pix_sync;
    reg pix_prev;
    reg [1:0] phase_warmup;
    reg phase_armed;
    wire word_start = phase_armed && pix_sync && !pix_prev;
    wire [39:0] words = {clk_lane, ch2, ch1, ch0};
    reg [31:0] shifts;
    reg [7:0] pairs;
    genvar lane;
    integer i;

    always @(posedge clk_5x or negedge serial_rst_n) begin
        if (!serial_rst_n) begin
            pix_meta <= 1'b0;
            pix_sync <= 1'b0;
            pix_prev <= 1'b0;
            phase_warmup <= 2'b00;
            phase_armed <= 1'b0;
            shifts <= 32'd0;
            pairs <= 8'd0;
        end else begin
            pix_meta <= pix_clk;
            pix_sync <= pix_meta;
            pix_prev <= pix_sync;
            phase_warmup <= {phase_warmup[0], 1'b1};
            if (phase_warmup[1] && !pix_sync) phase_armed <= 1'b1;
            for (i=0; i<4; i=i+1) begin
                if (word_start) begin
                    pairs[i*2 +: 2] <= words[i*10 +: 2];
                    shifts[i*8 +: 8] <= words[i*10+2 +: 8];
                end else begin
                    pairs[i*2 +: 2] <= shifts[i*8 +: 2];
                    shifts[i*8 +: 8] <= {2'b00, shifts[i*8+2 +: 6]};
                end
            end
        end
    end

    generate for (lane=0; lane<4; lane=lane+1) begin : lane_output
        EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) oddr (
            .q(tmds_p[lane]), .clk(clk_5x),
            .d0(pairs[lane*2]), .d1(pairs[lane*2+1]),
            .rst(~serial_rst_n)
        );
    end endgenerate
endmodule
