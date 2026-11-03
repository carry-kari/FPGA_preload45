
module fx_ui #(parameter integer KEY2_CONTROL=0)(
    input wire clk, rst_n, frame_commit,
    input wire key_event, mode_event, step_event,
    output wire next_req, edit_active,
    output reg [2:0] mode, active_mode,
    output reg [2:0] brightness_index, contrast_index,
    output reg signed [8:0] brightness,
    output reg [9:0] contrast,
    output reg subtitle_bottom,
    output reg [2:0] hold_index
);
    reg [2:0] pending_b, pending_c;
    reg pending_bottom;
    reg [2:0] pending_hold;
    assign next_req = key_event;
    assign edit_active = mode != 0;
    function signed [8:0] bvalue;
        input [2:0] index;
        begin
            case(index)
                0:bvalue=-9'sd64; 1:bvalue=-9'sd32;
                2:bvalue=0; 3:bvalue=32; default:bvalue=64;
            endcase
        end
    endfunction
    function [9:0] cvalue;
        input [2:0] index;
        begin
            case(index)
                0:cvalue=128; 1:cvalue=192; 2:cvalue=256;
                3:cvalue=320; default:cvalue=384;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if (!rst_n) begin
            mode<=0; active_mode<=0; pending_b<=2; pending_c<=2;
            brightness_index<=2; contrast_index<=2;
            brightness<=0; contrast<=256;
            pending_bottom<=0; subtitle_bottom<=0;
            pending_hold<=2;hold_index<=2;
        end else begin
            if (mode_event) mode <= (mode==(KEY2_CONTROL ? 4 : 2)) ? 0 : mode+1'b1;
            // Simultaneous mode/step uses the mode preceding this edge.
            if (step_event && mode==(KEY2_CONTROL ? 3 : 0)) pending_bottom <= ~pending_bottom;
            if (step_event && mode==1) pending_b <= pending_b==4 ? 0 : pending_b+1'b1;
            if (step_event && mode==2) pending_c <= pending_c==4 ? 0 : pending_c+1'b1;
            if (KEY2_CONTROL && step_event && mode==4) pending_hold <= pending_hold==5 ? 0 : pending_hold+1'b1;
            if (frame_commit) begin
                active_mode<=mode;
                brightness_index<=pending_b; contrast_index<=pending_c;
                brightness<=bvalue(pending_b); contrast<=cvalue(pending_c);
                subtitle_bottom<=pending_bottom;
                hold_index<=pending_hold;
            end
        end
    end
endmodule
