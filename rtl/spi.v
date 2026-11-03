module spi (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  tx_data,
    input  wire [7:0]  half_period,
    input  wire        miso,
    output reg         sclk,
    output reg         mosi,
    output reg  [7:0]  rx_data,
    output reg         busy,
    output reg         done
);
    reg [7:0] tx_shift, rx_shift;
    reg [7:0] timer;
    reg [2:0] bit_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk <= 1'b0; mosi <= 1'b1; rx_data <= 8'hff;
            busy <= 1'b0; done <= 1'b0; tx_shift <= 8'd0;
            rx_shift <= 8'd0; timer <= 8'd0; bit_index <= 3'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                sclk <= 1'b0;
                mosi <= tx_data[7];
                tx_shift <= tx_data;
                rx_shift <= 8'd0;
                bit_index <= 3'd0;
                timer <= half_period - 8'd1;
            end else if (busy) begin
                if (timer != 0) timer <= timer - 8'd1;
                else begin
                    timer <= half_period - 8'd1;
                    if (!sclk) begin
                        sclk <= 1'b1;
                        rx_shift <= {rx_shift[6:0], miso};
                    end else begin
                        sclk <= 1'b0;
                        tx_shift <= {tx_shift[6:0], 1'b1};
                        mosi <= tx_shift[6];
                        if (bit_index == 3'd7) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            rx_data <= rx_shift;
                            mosi <= 1'b1;
                        end else bit_index <= bit_index + 3'd1;
                    end
                end
            end
        end
    end
endmodule
