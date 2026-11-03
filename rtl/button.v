module button #(
    parameter integer STABLE_CYCLES = 500000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  pressed
);
    (* async_reg = "true" *) reg sync0, sync1;
    reg stable;
    localparam integer CW = STABLE_CYCLES > 1 ? $clog2(STABLE_CYCLES) : 1;
    reg [CW-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync0 <= 1'b1;
            sync1 <= 1'b1;
            stable <= 1'b1;
            count <= 0;
            pressed <= 1'b0;
        end else begin
            sync0 <= key_n;
            sync1 <= sync0;
            pressed <= 1'b0;
            if (sync1 == stable) begin
                count <= 0;
            end else if (count == STABLE_CYCLES - 1) begin
                count <= 0;
                stable <= sync1;
                if (!sync1) pressed <= 1'b1;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
