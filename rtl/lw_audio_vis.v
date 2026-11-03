module fx_sine_src #(
    parameter [23:0] PHASE_INC = 24'd349525, // 1 kHz at 48 kHz
    parameter [23:0] LFO_INC   = 24'd175     // 0.5 Hz at 48 kHz
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire               enable,
    output reg signed [23:0]  left,
    output reg signed [23:0]  right
);
    reg [23:0] phase;
    reg [23:0] lfo_phase;
    reg        enable_meta;
    reg        enable_sync;

    wire [1:0] quad = phase[23:22];
    wire [5:0] qidx = phase[21:16];
    wire [5:0] sidx = quad[0] ? (6'd63 - qidx) : qidx;
    wire signed [15:0] sval = quad[1] ? -sine_q(sidx) : sine_q(sidx);

    wire [7:0] lfo_tri = lfo_phase[23] ? (8'd255 - lfo_phase[22:15])
                                       : lfo_phase[22:15];
    wire [8:0] amp_q8 = 9'd160 + {3'd0, lfo_tri[7:2]}; // 160..223

    wire signed [25:0] prod = sval * $signed({1'b0, amp_q8});
    wire signed [23:0] pcm  = prod >>> 3;

    function signed [15:0] sine_q;
        input [5:0] idx;
        begin
            case (idx)
                6'd0: sine_q = 16'sd0;      6'd1: sine_q = 16'sd804;
                6'd2: sine_q = 16'sd1608;   6'd3: sine_q = 16'sd2410;
                6'd4: sine_q = 16'sd3212;   6'd5: sine_q = 16'sd4011;
                6'd6: sine_q = 16'sd4808;   6'd7: sine_q = 16'sd5602;
                6'd8: sine_q = 16'sd6393;   6'd9: sine_q = 16'sd7179;
                6'd10: sine_q = 16'sd7962;  6'd11: sine_q = 16'sd8739;
                6'd12: sine_q = 16'sd9512;  6'd13: sine_q = 16'sd10278;
                6'd14: sine_q = 16'sd11039; 6'd15: sine_q = 16'sd11793;
                6'd16: sine_q = 16'sd12539; 6'd17: sine_q = 16'sd13279;
                6'd18: sine_q = 16'sd14010; 6'd19: sine_q = 16'sd14732;
                6'd20: sine_q = 16'sd15446; 6'd21: sine_q = 16'sd16151;
                6'd22: sine_q = 16'sd16846; 6'd23: sine_q = 16'sd17530;
                6'd24: sine_q = 16'sd18204; 6'd25: sine_q = 16'sd18868;
                6'd26: sine_q = 16'sd19519; 6'd27: sine_q = 16'sd20159;
                6'd28: sine_q = 16'sd20787; 6'd29: sine_q = 16'sd21403;
                6'd30: sine_q = 16'sd22005; 6'd31: sine_q = 16'sd22594;
                6'd32: sine_q = 16'sd23170; 6'd33: sine_q = 16'sd23731;
                6'd34: sine_q = 16'sd24279; 6'd35: sine_q = 16'sd24811;
                6'd36: sine_q = 16'sd25329; 6'd37: sine_q = 16'sd25832;
                6'd38: sine_q = 16'sd26319; 6'd39: sine_q = 16'sd26790;
                6'd40: sine_q = 16'sd27245; 6'd41: sine_q = 16'sd27683;
                6'd42: sine_q = 16'sd28105; 6'd43: sine_q = 16'sd28510;
                6'd44: sine_q = 16'sd28898; 6'd45: sine_q = 16'sd29268;
                6'd46: sine_q = 16'sd29621; 6'd47: sine_q = 16'sd29956;
                6'd48: sine_q = 16'sd30273; 6'd49: sine_q = 16'sd30571;
                6'd50: sine_q = 16'sd30852; 6'd51: sine_q = 16'sd31113;
                6'd52: sine_q = 16'sd31356; 6'd53: sine_q = 16'sd31580;
                6'd54: sine_q = 16'sd31785; 6'd55: sine_q = 16'sd31971;
                6'd56: sine_q = 16'sd32137; 6'd57: sine_q = 16'sd32285;
                6'd58: sine_q = 16'sd32412; 6'd59: sine_q = 16'sd32521;
                6'd60: sine_q = 16'sd32609; 6'd61: sine_q = 16'sd32678;
                6'd62: sine_q = 16'sd32728; default: sine_q = 16'sd32757;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 24'd0;
            lfo_phase <= 24'd0;
            enable_meta <= 1'b0;
            enable_sync <= 1'b0;
            left <= 24'sd0;
            right <= 24'sd0;
        end else begin
            enable_meta <= enable;
            enable_sync <= enable_meta;
            if (sample_valid) begin
                phase <= phase + PHASE_INC;
                lfo_phase <= lfo_phase + LFO_INC;
                left  <= enable_sync ? pcm : 24'sd0;
                right <= enable_sync ? pcm : 24'sd0;
            end
        end
    end
endmodule


// Frame-published triggered PCM capture; pixel control latency is one clock.
module fx_scope_render #(
    parameter integer PANEL_X0=16,PANEL_X1=255,PANEL_Y0=356,PANEL_Y1=435,
    parameter integer TRACE_X0=18,TRACE_X1=253,TRACE_Y0=358,TRACE_Y1=433,
    parameter integer CENTER_Y=396,NSAMP=60,COORD_WIDTH=640,COORD_HEIGHT=480
)(
    input wire clk,rst_n,vis_en,
    input wire signed [23:0] sample,
    input wire sample_valid,
    input wire [23:0] in_rgb,
    input wire in_de,in_sof,in_eol,in_vs,
    output reg [23:0] out_rgb,
    output reg out_de,out_sof,out_eol,
    input wire in_hs,
    output reg out_hs,out_vs,
    output wire protocol_error
);
    localparam integer IW=NSAMP>1 ? $clog2(NSAMP) : 1;
    localparam [23:0] BORDER_RGB=24'h30c8ff,TRACE_RGB=24'h40ff80;
    reg [7:0] wav[0:NSAMP*2-1];
    reg capture_bank,display_bank,display_valid,ready_pending,filling,previous_sign;
    reg [IW-1:0] wr_idx;
    reg [11:0] idle_count;
    reg active_vis,snap_stale;
    wire [9:0] x,y;
    wire frame_commit,locked;
    wire signed [23:0] scaled=sample >>> 13;
    wire signed [7:0] code=scaled>24'sd127 ? 8'sd127 :
                            scaled< -24'sd128 ? 8'sh80 : scaled[7:0];
    wire trigger=!filling && !ready_pending && previous_sign && !sample[23];
    fx_coords #(.WIDTH(COORD_WIDTH),.HEIGHT(COORD_HEIGHT)) coords(
        .clk(clk),.rst_n(rst_n),.de(in_de),.sof(in_sof),.eol(in_eol),.vs(in_vs),
        .x(x),.y(y),.frame_commit(frame_commit),.locked(locked),.protocol_error(protocol_error));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            capture_bank<=0;display_bank<=0;display_valid<=0;ready_pending<=0;
            filling<=0;previous_sign<=0;wr_idx<=0;idle_count<=0;active_vis<=1;snap_stale<=1;
        end else begin
            if(sample_valid)begin
                previous_sign<=sample[23];
                if(idle_count!=12'hfff)idle_count<=idle_count+1'b1;
                if(trigger)begin
                    wav[capture_bank*NSAMP]<=code;idle_count<=0;
                    if(NSAMP==1)begin filling<=0;ready_pending<=1;end
                    else begin filling<=1;wr_idx<=1;end
                end else if(filling)begin
                    wav[capture_bank*NSAMP+wr_idx]<=code;
                    if(wr_idx==NSAMP-1)begin filling<=0;ready_pending<=1;end
                    else wr_idx<=wr_idx+1'b1;
                end
            end
            if(frame_commit)begin
                active_vis<=vis_en;
                snap_stale<=idle_count[11] || (!display_valid && !ready_pending);
                if(ready_pending)begin
                    display_bank<=capture_bank;display_valid<=1;
                    capture_bank<=~capture_bank;ready_pending<=0;
                end
            end
        end
    end
    wire in_panel=in_de && x>=PANEL_X0 && x<=PANEL_X1 && y>=PANEL_Y0 && y<=PANEL_Y1;
    wire in_trace=in_de && x>=TRACE_X0 && x<=TRACE_X1 && y>=TRACE_Y0 && y<=TRACE_Y1;
    wire [9:0] xr=x-TRACE_X0;
    wire [7:0] rel_x=in_trace ? xr[7:0] : 0;
    wire [5:0] raw_idx=rel_x[7:2];
    wire [IW-1:0] idx=raw_idx>=NSAMP ? NSAMP-1 : raw_idx;
    wire [IW-1:0] prev_idx=idx==0 ? 0 : idx-1'b1;
    wire signed [7:0] s0=(snap_stale || !display_valid) ? 8'sd0 :
        (display_bank ? wav[NSAMP+prev_idx] : wav[prev_idx]);
    wire signed [7:0] s1=(snap_stale || !display_valid) ? 8'sd0 :
        (display_bank ? wav[NSAMP+idx] : wav[idx]);
    wire signed [8:0] diff=$signed({s1[7],s1})-$signed({s0[7],s0});
    wire signed [11:0] delta={{3{diff[8]}},diff};
    reg signed [11:0] product;
    always @*case(rel_x[1:0])
        0:product=delta;1:product=delta<<<1;
        2:product=(delta<<<1)+delta;default:product=delta<<<2;
    endcase
    wire signed [11:0] interp=$signed({{4{s0[7]}},s0})+(product>>>2);
    localparam signed [11:0] CY=CENTER_Y;
    wire signed [11:0] yy=CY-(interp>>>2);
    wire [9:0] yline=yy[9:0];
    wire border=in_panel && (x<=PANEL_X0+1 || x>=PANEL_X1-1 || y<=PANEL_Y0+1 || y>=PANEL_Y1-1);
    wire trace=in_trace && display_valid && (y==yline || y==yline+10'd1);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin out_rgb<=0;out_de<=0;out_sof<=0;out_eol<=0;out_hs<=1;out_vs<=1;end
        else begin
            out_rgb<=active_vis && border ? BORDER_RGB : active_vis && trace ? TRACE_RGB : in_rgb;
            {out_de,out_sof,out_eol,out_hs,out_vs}<={in_de,in_sof,in_eol,in_hs,in_vs};
        end
    end
endmodule

// PCM valid is aligned with the newly registered sine data at the HDMI input.
module fx_audio_vis #(
    parameter integer KEY_DEBOUNCE=252000,
    parameter integer EXTERNAL_VISIBILITY=0
)(
    input wire clk,rst_n,key3_n,audio_valid,audio_enable,
    input wire [23:0] in_rgb,
    input wire in_de,in_sof,in_eol,in_vs,
    output wire signed [23:0] sine_left,sine_right,
    output wire [23:0] out_rgb,
    output wire out_de,out_sof,out_eol,
    input wire in_hs,
    output wire out_hs,out_vs,
    output reg sine_valid,
    output wire protocol_error,
    input wire visibility_enable
);
    wire key3_press;
    reg vis_en;
    fx_button #(.CYCLES(KEY_DEBOUNCE)) b3(clk,rst_n,key3_n,key3_press);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin vis_en<=1;sine_valid<=0;end
        else begin
            sine_valid<=audio_valid;
            if(key3_press)vis_en<=~vis_en;
        end
    end
    fx_sine_src sine(.clk(clk),.rst_n(rst_n),.sample_valid(audio_valid),.enable(audio_enable),
        .left(sine_left),.right(sine_right));
    fx_scope_render scope(.clk(clk),.rst_n(rst_n),.vis_en(EXTERNAL_VISIBILITY ? visibility_enable : vis_en),
        .sample(sine_left),.sample_valid(sine_valid),.in_rgb(in_rgb),
        .in_de(in_de),.in_sof(in_sof),.in_eol(in_eol),.in_vs(in_vs),.in_hs(in_hs),
        .out_rgb(out_rgb),.out_de(out_de),.out_sof(out_sof),.out_eol(out_eol),
        .out_hs(out_hs),.out_vs(out_vs),.protocol_error(protocol_error));
endmodule
