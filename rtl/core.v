module core #(
 parameter integer KEY_STABLE_CYCLES=252000,SD_POWER_WAIT_CYCLES=25200,
 SD_RETRY_WAIT_CYCLES=12600000,FILE_IO_TIMEOUT_CYCLES=25200000,
 SDRAM_POWER_CYCLES=8400,VIDEO_FLOW_CONTROL=0,AUTO_HOLD_FRAMES=300,AUTO_MS_MODE=1
)(
 input wire pix_clk,mem_clk,mem_rst_n,sdram_clk,rst_n,next_key_n,auto_key_n,audio_enable,video_sink_ready,sd_miso,
 input wire edit_active,video_mode_request,
 input wire tick_1ms,input wire [2:0] hold_index_request,
 output wire [2:0] active_hold_index,
 output wire sd_cs_n,sd_sclk,sd_mosi,
 output reg [7:0] red,green,blue,
 output reg video_de,video_hs,video_vs,video_sof,video_eol,
 output wire audio_valid,output wire signed [23:0] pcm_left,pcm_right,
 output wire [2:0] image_number,display_slot,display_bank,
 output reg [3:0] loaded_mask,output wire preload_done,image_ready,fault,
 output wire [4:0] fault_code,
 output wire transition,output wire [11:0] source_width,source_height,
 output reg [31:0] video_frames
);
 localparam WAIT_CARD=0,LOAD=1,START_BMP=2,READ_BMP=3,FENCE_BMP=4,INITIAL=5,
  OPEN_MOVIE=6,START_MOVIE_FILE=7,START_JPEG=8,READ_JPEG=9,FENCE_JPEG=10,PUBLISH=11,VIDEO_ERROR=12,ERROR=13,
  WAIT_MOVIE=14,WAIT_NEXT=15;
 reg [3:0] state;
 reg [1:0] slot;
 reg [2:0] file_select;
 reg file_start,bmp_start,jpeg_start,flush_start,ready_flag,fault_flag;
 reg [4:0] fault_reason;
 reg parser_ended,file_ended;
 reg [2:0] video_front,video_back;
 reg video_available;
 reg video_mode;
 wire active_video=video_mode && video_available;
 reg [11:0] photo_w[0:3],photo_h[0:3];
 reg [11:0] loading_w,loading_h;
 reg source_ended;
 wire [2:0] item;
 wire [8:0] gain;
 wire pressed,auto_pressed,consume;
 wire [9:0] x,y;
 wire de,hs,vs,frame_start;
 wire vblank_start=x==0 && y==480;
 assign preload_done=&loaded_mask;
 assign image_ready=ready_flag && (!video_mode || video_available);
 assign image_number=ready_flag ? display_slot : {1'b0,slot};
 assign display_slot=video_mode ? 3'd4 : item;
 assign display_bank=active_video ? video_front : item;
 assign source_width=!ready_flag ? loading_w : video_mode ? 12'd640 : photo_w[item[1:0]];
 assign source_height=!ready_flag ? loading_h : video_mode ? 12'd480 : photo_h[item[1:0]];
 assign fault=fault_flag;
 assign fault_code=fault_flag ? fault_reason : 5'd0;
 button #(.STABLE_CYCLES(KEY_STABLE_CYCLES)) button_next(pix_clk,rst_n,next_key_n,pressed);
 button #(.STABLE_CYCLES(KEY_STABLE_CYCLES)) button_auto(pix_clk,rst_n,auto_key_n,auto_pressed);
 carousel #(.HOLD_FRAMES(AUTO_HOLD_FRAMES),.MILLISECOND_MODE(AUTO_MS_MODE)) slides(.clk(pix_clk),.rst_n(rst_n),.blank(vblank_start),
  .enable(ready_flag && !video_mode && !video_mode_request),.edit_active(edit_active),.next_event(pressed && !video_mode_request),.video_available(video_available),
  .toggle_event(auto_pressed),
  .tick_1ms(tick_1ms),.hold_index_request(hold_index_request),.active_hold_index(active_hold_index),
  .item(item),.gain(gain),.transition(transition),.consume(consume),.auto_running());
 wire sd_initialized,sd_read_done,sd_error,sd_byte_valid;
 wire [7:0] sd_byte;
 wire [3:0] sd_error_code,file_error_code;
 wire sector_start,sector_abort,file_busy,file_done,file_error,file_byte_valid;
 wire [31:0] read_lba,file_length;
 wire [7:0] file_byte;
 sd #(.POWER_WAIT_CYCLES(SD_POWER_WAIT_CYCLES),.RETRY_WAIT_CYCLES(SD_RETRY_WAIT_CYCLES)) card(
  .clk(pix_clk),.rst_n(rst_n),.read_start(sector_start),.abort_read(sector_abort),.read_lba(read_lba),
  .sd_miso(sd_miso),.sd_cs_n(sd_cs_n),.sd_sclk(sd_sclk),.sd_mosi(sd_mosi),.initialized(sd_initialized),
  .read_done(sd_read_done),.error(sd_error),.byte_valid(sd_byte_valid),.byte_data(sd_byte),.error_code(sd_error_code));

 reg [7:0] bytes[0:3];
 reg [1:0] wp,rp;
 reg [2:0] count;
 wire movie_path=file_select==4;
 wire bmp_ready,jpeg_ready;
 wire stream_ready=movie_path ? (state==READ_JPEG && jpeg_ready) : (state==READ_BMP && (source_ended || bmp_ready));
 wire pop=count!=0 && stream_ready;
 wire file_byte_ready=count<2 && state!=VIDEO_ERROR && state!=ERROR;
 always @(posedge pix_clk)begin
  if(!rst_n)begin wp<=0;rp<=0;count<=0;end
  else begin
   if(file_byte_valid)begin bytes[wp]<=file_byte;wp<=wp+1'b1;end
   if(pop)rp<=rp+1'b1;
   case({file_byte_valid,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
  end
 end
 fat32 #(.IO_TIMEOUT_CYCLES(FILE_IO_TIMEOUT_CYCLES)) files(
  .clk(pix_clk),.rst_n(rst_n),.start(file_start),.file_slot(file_select),.busy(file_busy),.done(file_done),
  .error(file_error),.error_code(file_error_code),.mounted(),.file_length(file_length),
  .byte_ready(file_byte_ready),.byte_valid(file_byte_valid),.byte_data(file_byte),
  .sd_initialized(sd_initialized),.sd_read_done(sd_read_done),.sd_error(sd_error),.sd_error_code(sd_error_code),
  .sd_byte_valid(sd_byte_valid),.sd_byte_data(sd_byte),.read_start(sector_start),.read_abort(sector_abort),.read_lba(read_lba));
 wire bmp_done,bmp_error,bmp_valid,jpeg_done,jpeg_error,jpeg_valid;
 wire [18:0] bmp_address,jpeg_address;
 wire [23:0] bmp_rgb,jpeg_rgb;
 wire [11:0] bmp_w,bmp_h;
 wire source_done,bmp_header,parse_error,scale_overrun,scaled_done;
 wire [23:0] parsed_rgb;wire parsed_valid;
 assign bmp_done=scaled_done;assign bmp_error=parse_error;
 wire frame_write_ready,flush_done,memory_initialized,memory_overflow,memory_underrun,memory_fault;
 bmp24 #(.MAXW(1024),.MAX_FILE_BYTES(8388608),.CHECK_FILE_LENGTH(1)) parser(
  .clk(pix_clk),.rst_n(rst_n),.start(bmp_start),.byte_valid(pop && !movie_path && !source_ended),
  .byte_data(bytes[rp]),.file_length(file_length),.busy(),.done(source_done),.error(parse_error),
  .px_valid(parsed_valid),.px_data(parsed_rgb),.hdr_valid(bmp_header),.src_w(bmp_w),.src_h(bmp_h));
 scaler #(.MAXW(1024)) scale_unit(.clk(pix_clk),.rst_n(rst_n),.start(bmp_start),
  .hdr_valid(bmp_header),.src_w(bmp_w),.src_h(bmp_h),.px_valid(parsed_valid),.px_data(parsed_rgb),
  .in_ready(bmp_ready),.write_ready(frame_write_ready),.wr_valid(bmp_valid),
  .wr_addr(bmp_address),.wr_data(bmp_rgb),.busy(),.done(scaled_done),.overrun(scale_overrun));
 jpeg decoder(.clk(pix_clk),.rst_n(rst_n),.start(jpeg_start),.in_valid(count!=0 && state==READ_JPEG),
  .in_data(bytes[rp]),.in_ready(jpeg_ready),.busy(),.done(jpeg_done),.error(jpeg_error),.width(),.height(),
  .pixel_valid(jpeg_valid),.pixel_ready(frame_write_ready),.pixel_address(jpeg_address),.pixel_rgb(jpeg_rgb));
 wire [23:0] fb_rdata;
 wire line_available;
 frame #(.SDRAM_POWER_CYCLES(SDRAM_POWER_CYCLES)) image_ram(
  .pix_clk(pix_clk),.rst_n(rst_n),.mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.sdram_clk(sdram_clk),
  .load_start(bmp_start || jpeg_start),.write_valid(frame_write_ready && (movie_path ? jpeg_valid : bmp_valid)),
  .write_address(movie_path ? jpeg_address : bmp_address),.write_data(movie_path ? jpeg_rgb : bmp_rgb),
  .front_bank(display_bank),.write_slot(movie_path ? video_back : {1'b0,slot}),.display_enable(image_ready),
  .flush_start(flush_start),.flush_done(flush_done),.x(x),.y(y),.de(de),.read_data(fb_rdata),.line_available(line_available),
  .initialized(memory_initialized),.overflow(memory_overflow),.write_ready(frame_write_ready),
  .underrun(memory_underrun),.memory_fault(memory_fault));
 video #(.FLOW_CONTROL(VIDEO_FLOW_CONTROL)) video_time(.clk(pix_clk),.rst_n(rst_n),.x(x),.y(y),.de(de),
  .hs(hs),.vs(vs),.frame_start(frame_start),.sink_ready(video_sink_ready));
 task stop_load;
  input [4:0] reason;
  begin fault_flag<=1;fault_reason<=reason;state<=ready_flag ? VIDEO_ERROR : ERROR;end
 endtask
 integer i;
 always @(posedge pix_clk)begin
  if(!rst_n)begin
   state<=WAIT_CARD;slot<=0;file_select<=0;loaded_mask<=0;file_start<=0;bmp_start<=0;jpeg_start<=0;
   flush_start<=0;ready_flag<=0;fault_flag<=0;fault_reason<=0;parser_ended<=0;file_ended<=0;
   video_front<=4;video_back<=5;video_available<=0;video_frames<=0;video_mode<=0;
   loading_w<=0;loading_h<=0;source_ended<=0;
   for(i=0;i<4;i=i+1)begin photo_w[i]<=0;photo_h[i]<=0;end
  end else begin
   file_start<=0;bmp_start<=0;jpeg_start<=0;flush_start<=0;
   if(vblank_start)video_mode<=video_mode_request;
   if(file_done)file_ended<=1;
   if(memory_fault || memory_overflow || memory_underrun)begin
    ready_flag<=0;stop_load(memory_fault ? 5'd18 : memory_overflow ? 5'd16 : 5'd17);state<=ERROR;
   end else if((file_error || sd_error) && state!=WAIT_CARD && state!=VIDEO_ERROR && state!=ERROR)
    stop_load(sd_error ? {1'b0,sd_error_code} : {1'b0,file_error_code});
   else case(state)
    WAIT_CARD:if(sd_initialized && memory_initialized)state<=LOAD;
    LOAD:begin file_select<={1'b0,slot};file_start<=1;bmp_start<=1;parser_ended<=0;source_ended<=0;loading_w<=0;loading_h<=0;file_ended<=0;state<=START_BMP;end
    START_BMP:state<=READ_BMP;
    READ_BMP:begin
     if(bmp_header)begin loading_w<=bmp_w;loading_h<=bmp_h;end
     if(source_done)source_ended<=1;
     if(bmp_done)parser_ended<=1;
     if(bmp_error)stop_load(8);
     else if(scale_overrun)stop_load(22);
     else if(file_ended && count==0)begin
      if((source_ended || source_done) && (parser_ended || bmp_done))begin flush_start<=1;state<=FENCE_BMP;end
      else if(!(source_ended || source_done) && bmp_ready)stop_load(15);
     end
    end
    FENCE_BMP:if(flush_done)begin photo_w[slot]<=loading_w;photo_h[slot]<=loading_h;loaded_mask[slot]<=1;if(slot==3)state<=INITIAL;else begin slot<=slot+1'b1;loading_w<=0;loading_h<=0;state<=LOAD;end end
    INITIAL:if(vblank_start)begin ready_flag<=1;state<=WAIT_MOVIE;end
    WAIT_MOVIE:if(video_mode_request)state<=OPEN_MOVIE;
    WAIT_NEXT:if(video_mode_request)state<=START_JPEG;
    OPEN_MOVIE:begin file_select<=4;file_start<=1;file_ended<=0;state<=START_MOVIE_FILE;end
    START_MOVIE_FILE:state<=START_JPEG;
    START_JPEG:begin jpeg_start<=1;state<=READ_JPEG;end
    READ_JPEG:begin
     if(jpeg_error)stop_load(20);
     else if(jpeg_done)begin flush_start<=1;state<=FENCE_JPEG;end
     else if(file_ended && count==0 && jpeg_ready)stop_load(21);
    end
    FENCE_JPEG:if(flush_done)state<=PUBLISH;
    PUBLISH:if(vblank_start)begin
     video_front<=video_back;video_back<=video_back==4 ? 5 : 4;video_available<=1;video_frames<=video_frames+1'b1;
     if(file_ended && count==0)state<=WAIT_MOVIE;else state<=WAIT_NEXT;
    end
    VIDEO_ERROR:begin end
    ERROR:begin end
   endcase
  end
 end
 reg de_d,hs_d,vs_d,sof_d,eol_d,ready_d;
 wire [8:0] visible_gain=video_mode ? 9'd256 : gain;
 wire [16:0] fade_r=fb_rdata[23:16]*visible_gain,fade_g=fb_rdata[15:8]*visible_gain,fade_b=fb_rdata[7:0]*visible_gain;
 always @(posedge pix_clk)begin
  if(!rst_n)begin de_d<=0;hs_d<=1;vs_d<=1;sof_d<=0;eol_d<=0;ready_d<=0;
   red<=0;green<=0;blue<=0;video_de<=0;video_hs<=1;video_vs<=1;video_sof<=0;video_eol<=0;end
  else begin
   de_d<=de;hs_d<=hs;vs_d<=vs;sof_d<=frame_start;eol_d<=de && x==639;ready_d<=image_ready && line_available;
   video_de<=de_d;video_hs<=hs_d;video_vs<=vs_d;video_sof<=sof_d;video_eol<=eol_d;
   red<=de_d && ready_d ? fade_r[15:8] : 0;
   green<=de_d && ready_d ? fade_g[15:8] : 0;
   blue<=de_d && ready_d ? fade_b[15:8] : 0;
  end
 end
 reg audio_meta,audio_sync;
 always @(posedge pix_clk)begin if(!rst_n)begin audio_meta<=0;audio_sync<=0;end else begin audio_meta<=audio_enable;audio_sync<=audio_meta;end end
 tone tone(.pix_clk(pix_clk),.rst_n(rst_n),.enable(audio_sync),.sample_valid(audio_valid),.pcm_left(pcm_left),.pcm_right(pcm_right));
endmodule
