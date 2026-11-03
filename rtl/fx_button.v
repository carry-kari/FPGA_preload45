module fx_button #(parameter integer CYCLES = 252000)(
    input wire clk, rst_n, key_n, output reg pressed
);
    localparam integer CW = (CYCLES < 2) ? 1 : $clog2(CYCLES);
    reg meta, sync, stable;
    reg [CW-1:0] count;
    always @(posedge clk) begin
        if (!rst_n) begin
            meta<=1; sync<=1; stable<=1; count<=0; pressed<=0;
        end else begin
            meta<=key_n; sync<=meta; pressed<=0;
            if (sync == stable) count<=0;
            else if (count == CYCLES-1) begin
                stable<=sync; count<=0; pressed<=!sync;
            end else count<=count+1'b1;
        end
    end
endmodule
