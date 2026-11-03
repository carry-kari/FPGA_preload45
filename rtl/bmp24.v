module bmp24 #(
    parameter integer MAXW = 2048,
    parameter integer MAXH = 2048,
    parameter integer MAX_FILE_BYTES = 8388608,
    parameter integer CHECK_FILE_LENGTH = 0
) (
    input wire clk, rst_n, start, byte_valid,
    input wire [7:0] byte_data,
    input wire [31:0] file_length,
    output reg busy, done, error,
    output reg px_valid,
    output reg [23:0] px_data,
    output reg hdr_valid,
    output reg [11:0] src_w, src_h
);
    reg [23:0] byte_index;
    reg [31:0] file_size;
    reg [12:0] pixel_offset;
    reg [7:0] dib_size;
    reg header_bad;
    reg [1:0] component, pad_left;
    reg [7:0] blue, green;
    reg [11:0] col, row;
    wire [13:0] row_bytes=({2'b00,src_w}*14'd3+14'd3) & 14'h3ffc;
    wire [25:0] payload_bytes=row_bytes*src_h;
    wire [31:0] required_bytes={6'd0,payload_bytes}+{19'd0,pixel_offset};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; done <= 0; error <= 0; px_valid <= 0; px_data <= 0;
            hdr_valid <= 0; src_w <= 0; src_h <= 0;
            byte_index <= 0; file_size <= 0; pixel_offset <= 0; dib_size <= 0;
            header_bad <= 0; component <= 0; pad_left <= 0;
            blue <= 0; green <= 0; col <= 0; row <= 0;
        end else begin
            px_valid <= 0; done <= 0; hdr_valid <= 0;
            if (start) begin
                busy <= 1; error <= 0; byte_index <= 0; file_size <= 0;
                pixel_offset <= 0; dib_size <= 0; header_bad <= 0;
                component <= 0; pad_left <= 0; col <= 0; row <= 0;
                src_w <= 0; src_h <= 0;
            end else if (busy && byte_valid) begin
                byte_index <= byte_index + 1'b1;
                case (byte_index)
                    0: if (byte_data != 8'h42) header_bad <= 1;
                    1: if (byte_data != 8'h4d) header_bad <= 1;
                    2: file_size[7:0] <= byte_data;
                    3: file_size[15:8] <= byte_data;
                    4: file_size[23:16] <= byte_data;
                    5: file_size[31:24] <= byte_data;
                    10: pixel_offset[7:0] <= byte_data;
                    11: begin
                        pixel_offset[12:8] <= byte_data[4:0];
                        if (byte_data[7:5] != 0) header_bad <= 1;
                    end
                    12,13: if (byte_data != 0) header_bad <= 1;
                    14: dib_size <= byte_data;
                    15,16,17: if (byte_data != 0) header_bad <= 1;
                    18: src_w[7:0] <= byte_data;
                    19: begin
                        src_w[11:8] <= byte_data[3:0];
                        if (byte_data[7:4] != 0) header_bad <= 1;
                    end
                    20,21: if (byte_data != 0) header_bad <= 1;
                    22: src_h[7:0] <= byte_data;
                    23: begin
                        src_h[11:8] <= byte_data[3:0];
                        if (byte_data[7:4] != 0) header_bad <= 1;   // also rejects top-down (negative) height
                    end
                    24,25: if (byte_data != 0) header_bad <= 1;
                    26: if (byte_data != 1) header_bad <= 1;
                    27: if (byte_data != 0) header_bad <= 1;
                    28: if (byte_data != 24) header_bad <= 1;
                    29,30,31,32,33: if (byte_data != 0) header_bad <= 1;
                    default: begin end
                endcase
                if (byte_index == 53 &&
                    (header_bad || !(dib_size == 40 || dib_size == 108 || dib_size == 124) ||
                     pixel_offset < 14 + dib_size || pixel_offset > 4096 ||
                     src_w == 0 || src_h == 0 || src_w > MAXW || src_h > MAXH ||
                     // Only exact 4:3 sources are accepted. Reject portrait/square/other ratios
                     // before streaming pixels, so no source edge is ever cropped.
                     (({src_w,1'b0} + src_w) != {src_h,2'b00}) ||
                     file_size < required_bytes || file_size > MAX_FILE_BYTES ||
                     (CHECK_FILE_LENGTH && (file_size > file_length || required_bytes > file_length)))) begin
                    busy <= 0; error <= 1;
                end else if (byte_index == 53) begin
                    hdr_valid <= 1;
                end else if (byte_index >= pixel_offset && byte_index >= 54) begin
                    if (pad_left != 0) pad_left <= pad_left - 1'b1;
                    else case (component)
                        0: begin blue <= byte_data; component <= 1; end
                        1: begin green <= byte_data; component <= 2; end
                        default: begin
                            px_valid <= 1;
                            px_data <= {byte_data, green, blue};
                            component <= 0;
                            if (col == src_w - 12'd1) begin
                                col <= 0;
                                if (row == src_h - 12'd1) begin busy <= 0; done <= 1; end
                                else begin
                                    row <= row + 1'b1;
                                    pad_left <= src_w[1:0];
                                end
                            end else col <= col + 1'b1;
                        end
                    endcase
                end
            end
        end
    end
endmodule
