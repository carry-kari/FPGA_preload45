
module fx_text #(
    parameter [1023:0] MESSAGE = {"CHIPS WITHOUT LIMITS, BEYOND THE UNSEEN. SHANGHAI ANLOGIC INFOTECH CO., LTD. WELCOMES YOU.", {38{8'h20}}}
)(
    input wire [9:0] x,y,
    input wire de, subtitle_enable, osd_enable,
    input wire [9:0] scroll,
    input wire [23:0] uptime_bcd,
    input wire [2:0] mode,
    input wire [2:0] brightness_index, contrast_index,
    input wire [2:0] display_slot,
    input wire [11:0] source_width, source_height,
    input wire [4:0] fault_code,
    input wire image_ready,
    input wire [2:0] front_bank,
    input wire transition,
    input wire subtitle_bottom,
    input wire [7:0] fps_bcd,
    input wire [2:0] hold_index,
    output wire [23:0] sub_rgb, osd_rgb,
    output wire [8:0] sub_alpha, osd_alpha,
    output wire sub_valid, osd_valid
);
    wire [9:0] subtitle_y=subtitle_bottom ? 10'd448 : 10'd16;
    wire marquee=de && x>=16 && x<624 && y>=subtitle_y && y<subtitle_y+10'd16;
    wire clock_area=de && x>=16 && x<104 && y>=40 && y<56;
    wire panel=de && x>=416 && x<640 && y>=64 && y<160;
    wire [9:0] sx=x-10'd16, sy=y-subtitle_y;
    wire [9:0] scroll_x=sx+scroll;
    wire [9:0] px=x-10'd416, py=y-10'd64;
    wire [4:0] pc=px[7:3];
    wire [2:0] line=py[6:4];
    wire [7:0] marquee_char=MESSAGE[1023-scroll_x[9:3]*8 -: 8];
    reg [7:0] clock_char, panel_char;
    wire mi, ci, pi;
    reg [7:0] hold_bcd;
    always @* begin
        case(hold_index)
            0:hold_bcd=8'h02;1:hold_bcd=8'h03;2:hold_bcd=8'h05;
            3:hold_bcd=8'h10;4:hold_bcd=8'h15;5:hold_bcd=8'h30;
            default:hold_bcd=8'h05;
        endcase
    end
    function [7:0] at28;
        input [223:0] text;
        input [4:0] col;
        begin at28=col<28 ? text[223-col*8 -: 8] : 8'd32; end
    endfunction
    function [15:0] bcd4;
        input [11:0] value;
        reg [27:0] work;integer bit_index,digit;
        begin
            work={16'd0,value};
            for(bit_index=0;bit_index<12;bit_index=bit_index+1)begin
                for(digit=0;digit<4;digit=digit+1)
                    if(work[12+digit*4 +: 4]>=5)work[12+digit*4 +: 4]=work[12+digit*4 +: 4]+4'd3;
                work=work<<1;
            end
            bcd4=work[27:12];
        end
    endfunction
    wire [15:0] width_bcd=bcd4(source_width),height_bcd=bcd4(source_height);
    always @* begin
        case(sx[6:3])
            0:clock_char="U"; 1:clock_char="P"; 2:clock_char=" ";
            3:clock_char=48+uptime_bcd[23:20]; 4:clock_char=48+uptime_bcd[19:16];
            5:clock_char=":"; 6:clock_char=48+uptime_bcd[15:12];
            7:clock_char=48+uptime_bcd[11:8]; 8:clock_char=":";
            9:clock_char=48+uptime_bcd[7:4]; 10:clock_char=48+uptime_bcd[3:0];
            default:clock_char=" ";
        endcase
        panel_char=" ";
        case(line)
            0:begin
                case(mode)
                    0:panel_char=at28("MODE BROWSE                 ",pc);
                    1:panel_char=at28("MODE BRIGHTNESS             ",pc);
                    2:panel_char=at28("MODE CONTRAST               ",pc);
                    3:panel_char=at28("MODE TEXT POSITION          ",pc);
                    4:panel_char=at28("MODE SLIDE TIME             ",pc);
                    default:panel_char=at28("MODE BROWSE                 ",pc);
                endcase
            end
            1:begin
                case(brightness_index)
                    0:panel_char=at28("BRT -064                    ",pc);
                    1:panel_char=at28("BRT -032                    ",pc);
                    2:panel_char=at28("BRT +000                    ",pc);
                    3:panel_char=at28("BRT +032                    ",pc);
                    default:panel_char=at28("BRT +064                    ",pc);
                endcase
            end
            2:begin
                case(contrast_index)
                    0:panel_char=at28("CTR 0.50X                   ",pc);
                    1:panel_char=at28("CTR 0.75X                   ",pc);
                    2:panel_char=at28("CTR 1.00X                   ",pc);
                    3:panel_char=at28("CTR 1.25X                   ",pc);
                    default:panel_char=at28("CTR 1.50X                   ",pc);
                endcase
            end
            3:begin
                panel_char=at28("PIC 0 SIZE 0000X0000        ",pc);
                if(pc==4) panel_char=display_slot==4 ? "V" : 8'd49+display_slot;
                if(pc>=11 && pc<=14) panel_char=8'd48+width_bcd[15-(pc-11)*4 -: 4];
                if(pc>=16 && pc<=19) panel_char=8'd48+height_bcd[15-(pc-16)*4 -: 4];
            end
            4:begin
                panel_char=subtitle_bottom ? at28("TEXT BOTTOM                 ",pc) :
                                             at28("TEXT TOP                    ",pc);
            end
            5:begin
                panel_char=at28("FPS 00  HOLD 05S            ",pc);
                if(pc==4)panel_char=8'd48+fps_bcd[7:4];
                if(pc==5)panel_char=8'd48+fps_bcd[3:0];
                if(pc==13)panel_char=8'd48+hold_bcd[7:4];
                if(pc==14)panel_char=8'd48+hold_bcd[3:0];
            end
            default:panel_char=" ";
        endcase
    end
    fx_font fm(marquee_char,scroll_x[2:0],sy[3:0],mi);
    fx_font fc(clock_char,sx[2:0],y[3:0]-4'd8,ci);
    fx_font fp(panel_char,px[2:0],py[3:0],pi);
    assign sub_valid=(subtitle_enable && marquee) || (osd_enable && clock_area);
    assign sub_rgb=(marquee && mi) ? 24'hffe060 :
                   (clock_area && ci) ? 24'hffffff : 24'h102030;
    assign sub_alpha=((marquee && mi)||(clock_area && ci)) ? 9'd256 : 9'd96;
    assign osd_valid=osd_enable && panel;
    assign osd_rgb=pi ? 24'hffffff : 24'h102030;
    assign osd_alpha=pi ? 9'd256 : 9'd160;
endmodule
