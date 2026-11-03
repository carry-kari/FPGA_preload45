module video #(
    parameter integer FLOW_CONTROL = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sink_ready,
    output reg [9:0] x,
    output reg [9:0] y,
    output wire       de,
    output wire       hs,
    output wire       vs,
    output wire       frame_start
);
    localparam H_ACTIVE = 640, H_FRONT = 16, H_SYNC = 96, H_BACK = 48;
    localparam V_ACTIVE = 480, V_FRONT = 10, V_SYNC = 2, V_BACK = 33;
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
   
    wire line_wait = FLOW_CONTROL && x == 0 && y < V_ACTIVE && !sink_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (line_wait) begin
            x <= x;
            y <= y;
        end else if (x == H_TOTAL - 1) begin
            x <= 10'd0;
            y <= (y == V_TOTAL - 1) ? 10'd0 : y + 10'd1;
        end else begin
            x <= x + 10'd1;
        end
    end

    assign de = (x < H_ACTIVE) && (y < V_ACTIVE) && !line_wait;
    assign hs = !((x >= H_ACTIVE + H_FRONT) &&
                  (x < H_ACTIVE + H_FRONT + H_SYNC));
    assign vs = !((y >= V_ACTIVE + V_FRONT) &&
                  (y < V_ACTIVE + V_FRONT + V_SYNC));
    assign frame_start = (x == 0) && (y == 0) && !line_wait;
endmodule
