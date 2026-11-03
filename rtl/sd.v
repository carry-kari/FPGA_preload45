module sd #(
    parameter integer POWER_WAIT_CYCLES = 25200,
    parameter integer RETRY_WAIT_CYCLES = 12600000,
    parameter integer TOKEN_MAX_BYTES = 200000,
    parameter integer FAST_HALF_PERIOD = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        read_start,
    input  wire        abort_read,
    input  wire [31:0] read_lba,
    input  wire        sd_miso,
    output reg         sd_cs_n,
    output wire        sd_sclk,
    output wire        sd_mosi,
    output reg         initialized,
    output reg         read_done,
    output reg         error,
    output reg         byte_valid,
    output reg [7:0]   byte_data,
    output reg [3:0]   error_code
);
    localparam [4:0] PWR_START=0, PWR_WAIT=1, IDLE=2,
                     CMD_START=3, CMD_WAIT=4, RSP_START=5, RSP_WAIT=6,
                     EXT_START=7, EXT_WAIT=8, TOKEN_START=9, TOKEN_WAIT=10,
                     DATA_START=11, DATA_WAIT=12, CRC_START=13,
                     CRC_WAIT=14, FAIL=15, POWER_DELAY=16,
                     GAP_START=17, GAP_WAIT=18;
    localparam integer WC = RETRY_WAIT_CYCLES > POWER_WAIT_CYCLES ?
                            RETRY_WAIT_CYCLES : POWER_WAIT_CYCLES;
    localparam integer WW = WC > 1 ? $clog2(WC) : 1;
    localparam integer TW = TOKEN_MAX_BYTES > 1 ? $clog2(TOKEN_MAX_BYTES) : 1;
    reg [4:0] state;
    reg [WW-1:0] wait_count;
    reg [5:0] cmd;
    reg [31:0] arg;
    reg [2:0] cmd_index;
    reg [3:0] power_count;
    reg [7:0] response_tries;
    reg [TW-1:0] token_tries;
    reg [11:0] acmd_tries;
    reg [2:0] ext_index;
    reg [9:0] data_index;
    reg crc_second;
    reg [7:0] ocr_first;
    reg [15:0] data_crc;
    reg crc_bad;
    reg gap_read;
    reg spi_start;
    reg [7:0] spi_tx;
    wire [7:0] spi_rx;
    wire spi_busy, spi_done;
    // 196.875 kHz identification, 12.6 MHz data transfer at the default setting.
    wire [7:0] half_period = initialized ? FAST_HALF_PERIOD : 8'd64;

    spi byte_phy (
        .clk(clk), .rst_n(rst_n && !abort_read), .start(spi_start), .tx_data(spi_tx),
        .half_period(half_period), .miso(sd_miso), .sclk(sd_sclk),
        .mosi(sd_mosi), .rx_data(spi_rx), .busy(spi_busy), .done(spi_done)
    );

    function [7:0] command_byte;
        input [5:0] number;
        input [31:0] argument;
        input [2:0] index;
        begin
            case (index)
                0: command_byte = 8'h40 | {2'b00, number};
                1: command_byte = argument[31:24];
                2: command_byte = argument[23:16];
                3: command_byte = argument[15:8];
                4: command_byte = argument[7:0];
                default: command_byte = number == 0 ? 8'h95 :
                                        number == 8 ? 8'h87 : 8'h01;
            endcase
        end
    endfunction

    function [15:0] crc16_byte;
        input [15:0] previous;
        input [7:0] data;
        reg [15:0] crc;
        integer bit_number;
        begin
            crc = previous ^ {data, 8'd0};
            for (bit_number=0; bit_number<8; bit_number=bit_number+1)
                crc = crc[15] ? (crc << 1) ^ 16'h1021 : (crc << 1);
            crc16_byte = crc;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= POWER_DELAY; sd_cs_n <= 1'b1;
            initialized <= 1'b0; read_done <= 1'b0; error <= 1'b0;
            byte_valid <= 1'b0; byte_data <= 8'd0;
            cmd <= 6'd0; arg <= 32'd0; cmd_index <= 3'd0;
            power_count <= 4'd0; response_tries <= 8'd0;
            token_tries <= 0; acmd_tries <= 12'd0;
            ext_index <= 3'd0;
            data_index <= 10'd0; crc_second <= 1'b0;
            ocr_first <= 8'd0; wait_count <= 0;
            data_crc <= 16'd0; crc_bad <= 1'b0;
            gap_read <= 1'b0; error_code <= 4'd0;
            spi_start <= 1'b0; spi_tx <= 8'hff;
        end else begin
            spi_start <= 1'b0;
            read_done <= 1'b0;
            byte_valid <= 1'b0;
            if (abort_read) begin
                // Retire the timed-out transaction and reinitialize the card.
                spi_start<=0; byte_valid<=0; read_done<=0;
                sd_cs_n<=1; initialized<=0; error<=1; error_code<=4'd11;
                wait_count<=0; gap_read<=0; state<=FAIL;
            end else case (state)
                POWER_DELAY: begin
                    if (wait_count == POWER_WAIT_CYCLES-1) begin
                        wait_count <= 0;
                        state <= PWR_START;
                    end else wait_count <= wait_count + 1'b1;
                end
                PWR_START: if (!spi_busy) begin
                    sd_cs_n <= 1'b1;
                    spi_tx <= 8'hff; spi_start <= 1'b1;
                    state <= PWR_WAIT;
                end
                PWR_WAIT: if (spi_done) begin
                    if (power_count == 4'd9) begin
                        sd_cs_n <= 1'b0;
                        cmd <= 6'd0; arg <= 32'd0; cmd_index <= 3'd0;
                        state <= CMD_START;
                    end else begin
                        power_count <= power_count + 4'd1;
                        state <= PWR_START;
                    end
                end
                IDLE: if (read_start) begin
                    sd_cs_n <= 1'b0;
                    cmd <= 6'd17; arg <= read_lba;
                    cmd_index <= 3'd0;
                    state <= CMD_START;
                end
                CMD_START: if (!spi_busy) begin
                    spi_tx <= command_byte(cmd, arg, cmd_index);
                    spi_start <= 1'b1;
                    state <= CMD_WAIT;
                end
                CMD_WAIT: if (spi_done) begin
                    if (cmd_index == 3'd5) begin
                        response_tries <= 8'd0;
                        state <= RSP_START;
                    end else begin
                        cmd_index <= cmd_index + 3'd1;
                        state <= CMD_START;
                    end
                end
                RSP_START: if (!spi_busy) begin
                    spi_tx <= 8'hff; spi_start <= 1'b1;
                    state <= RSP_WAIT;
                end
                RSP_WAIT: if (spi_done) begin
                    if (spi_rx[7]) begin
                        if (response_tries == 8'hff) begin
                            error_code <= 4'd1; state <= FAIL;
                        end
                        else begin
                            response_tries <= response_tries + 8'd1;
                            state <= RSP_START;
                        end
                    end else if (cmd == 0 && spi_rx == 8'h01) begin
                        cmd <= 6'd8; arg <= 32'h000001aa;
                        cmd_index <= 3'd0; state <= CMD_START;
                    end else if (cmd == 8 && spi_rx == 8'h01) begin
                        ext_index <= 3'd0; state <= EXT_START;
                    end else if (cmd == 55 && (spi_rx == 8'h01 || spi_rx == 8'h00)) begin
                        cmd <= 6'd41; arg <= 32'h40000000;
                        cmd_index <= 3'd0; state <= CMD_START;
                    end else if (cmd == 41 && spi_rx == 8'h01) begin
                        if (acmd_tries == 12'hfff) begin
                            error_code <= 4'd2; state <= FAIL;
                        end
                        else begin
                            acmd_tries <= acmd_tries + 12'd1;
                            cmd <= 6'd55; arg <= 32'd0;
                            cmd_index <= 3'd0; state <= CMD_START;
                        end
                    end else if (cmd == 41 && spi_rx == 8'h00) begin
                        cmd <= 6'd58; arg <= 32'd0;
                        cmd_index <= 3'd0; state <= CMD_START;
                    end else if (cmd == 58 && spi_rx == 8'h00) begin
                        ext_index <= 3'd0; state <= EXT_START;
                    end else if (cmd == 17 && spi_rx == 8'h00) begin
                        token_tries <= 0; state <= TOKEN_START;
                    end else begin error_code <= 4'd3; state <= FAIL; end
                end
                EXT_START: if (!spi_busy) begin
                    spi_tx <= 8'hff; spi_start <= 1'b1;
                    state <= EXT_WAIT;
                end
                EXT_WAIT: if (spi_done) begin
                    if (cmd == 58 && ext_index == 0) ocr_first <= spi_rx;
                    if (cmd == 8 && spi_rx !=
                        (ext_index == 2 ? 8'h01 : ext_index == 3 ? 8'haa : 8'h00)) begin
                        error_code <= 4'd4; state <= FAIL;
                    end else if (cmd == 58 && ext_index == 1 && spi_rx[5:4] == 0) begin
                        error_code <= 4'd5; state <= FAIL;
                    end
                    else if (ext_index == 3) begin
                        if (cmd == 8) begin
                            cmd <= 6'd55; arg <= 32'd0;
                            cmd_index <= 3'd0; state <= CMD_START;
                        end else if (ocr_first[7:6] == 2'b11) begin
                            gap_read <= 1'b0;
                            state <= GAP_START;
                        end else begin error_code <= 4'd5; state <= FAIL; end
                    end else begin
                        ext_index <= ext_index + 3'd1;
                        state <= EXT_START;
                    end
                end
                TOKEN_START: if (!spi_busy) begin
                    spi_tx <= 8'hff; spi_start <= 1'b1;
                    state <= TOKEN_WAIT;
                end
                TOKEN_WAIT: if (spi_done) begin
                    if (spi_rx == 8'hfe) begin
                        data_index <= 10'd0; data_crc <= 16'd0;
                        crc_bad <= 1'b0; state <= DATA_START;
                    end else if (token_tries == TOKEN_MAX_BYTES-1 || spi_rx != 8'hff) begin
                        error_code <= 4'd6; state <= FAIL;
                    end
                    else begin
                        token_tries <= token_tries + 1'b1;
                        state <= TOKEN_START;
                    end
                end
                DATA_START: if (!spi_busy) begin
                    spi_tx <= 8'hff; spi_start <= 1'b1;
                    state <= DATA_WAIT;
                end
                DATA_WAIT: if (spi_done) begin
                    byte_valid <= 1'b1;
                    byte_data <= spi_rx;
                    data_crc <= crc16_byte(data_crc, spi_rx);
                    if (data_index == 10'd511) begin
                        crc_second <= 1'b0; state <= CRC_START;
                    end else begin
                        data_index <= data_index + 10'd1;
                        state <= DATA_START;
                    end
                end
                CRC_START: if (!spi_busy) begin
                    spi_tx <= 8'hff; spi_start <= 1'b1;
                    state <= CRC_WAIT;
                end
                CRC_WAIT: if (spi_done) begin
                    if (!crc_second) begin
                        crc_bad <= spi_rx != data_crc[15:8];
                        crc_second <= 1'b1; state <= CRC_START;
                    end else if (crc_bad || spi_rx != data_crc[7:0]) begin
                        error_code <= 4'd7; state <= FAIL;
                    end else begin
                        gap_read <= 1'b1; state <= GAP_START;
                    end
                end
                GAP_START: if (!spi_busy) begin
                    sd_cs_n <= 1'b1;
                    spi_tx <= 8'hff; spi_start <= 1'b1;
                    state <= GAP_WAIT;
                end
                GAP_WAIT: if (spi_done) begin
                    read_done <= gap_read;
                    initialized <= 1'b1;
                    error_code <= 4'd0;
                    state <= IDLE;
                end
                FAIL: begin
                    error <= 1'b1;
                    initialized <= 1'b0;
                    sd_cs_n <= 1'b1;
                    if (wait_count == RETRY_WAIT_CYCLES-1) begin
                        wait_count <= 0;
                        error <= 1'b0;
                        power_count <= 0; acmd_tries <= 0;
                        state <= POWER_DELAY;
                    end else wait_count <= wait_count + 1'b1;
                end
                default: state <= FAIL;
            endcase
        end
    end
endmodule
