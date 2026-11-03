module jpeg #(
 parameter integer REQUIRED_W=640,REQUIRED_H=480
)(
 input wire clk,rst_n,start,
 input wire in_valid,input wire [7:0] in_data,output wire in_ready,
 output reg busy,done,error,
 output reg [9:0] width,height,
 output wire pixel_valid,input wire pixel_ready,
 output wire [18:0] pixel_address,output wire [23:0] pixel_rgb
);
 localparam IDLE=0,SOI0=1,SOI1=2,MARK0=3,MARK1=4,LEN0=5,LEN1=6,SEG=7,CHECK=8,
 CLEAR=9,HUFF=10,SYMBOL=11,AMP=12,PUT=13,TRANSFORM=14,WAIT_IDCT=15,EMIT=16,EOI0=17,EOI1=18;
 reg [4:0] state;
 reg [7:0] marker;
 reg [15:0] length,left,index;
 reg [7:0] header[0:15];
 reg [7:0] quant[0:127],counts[0:63],symbols[0:1023];
 reg [1:0] qvalid;
 reg [3:0] hvalid;
 reg sof_seen;
 reg [1:0] table_id;
 reg [6:0] qi;
 reg [4:0] hi;
 reg [8:0] symbol_total,symbol_pos;
 wire [5:0] quant_offset=qi-1'b1;
 wire [3:0] count_offset=hi-1'b1;
 reg [1:0] comp;
 reg qsel[0:2],dcsel[0:2],acsel[0:2];
 reg signed [15:0] predictor[0:2];
 reg [6:0] bx,by;
 reg [6:0] coeff_index;
 reg [5:0] clear_index;
 reg ac;
 reg [15:0] code,first_code;
 reg [8:0] symbol_base;
 reg [3:0] code_length;
 reg [7:0] symbol;
 reg [3:0] amplitude_left,amplitude_size;
 reg [15:0] amplitude;
 reg signed [23:0] value;
 reg [7:0] bit_byte;
 reg [3:0] bits_left;
 reg stuffed;
 wire bit_needed=state==HUFF || state==AMP;
 assign in_ready=busy && (state==SOI0 || state==SOI1 || state==MARK0 || state==MARK1 ||
  state==LEN0 || state==LEN1 || state==SEG || state==EOI0 || state==EOI1 || (bit_needed && bits_left==0));
 wire take=in_valid && in_ready;
 wire [1:0] htable={ac,ac ? acsel[comp] : dcsel[comp]};
 wire [7:0] hcount=counts[{htable,code_length}];
 wire [16:0] next_code={code,bit_byte[7]};
 wire [16:0] limit_code={1'b0,first_code}+{9'd0,hcount};
 reg [9:0] symbol_address;
 function [5:0] zigzag;
 input [5:0] n;
 begin case(n)
 0:zigzag=0;1:zigzag=1;2:zigzag=8;3:zigzag=16;4:zigzag=9;5:zigzag=2;6:zigzag=3;7:zigzag=10;
 8:zigzag=17;9:zigzag=24;10:zigzag=32;11:zigzag=25;12:zigzag=18;13:zigzag=11;14:zigzag=4;15:zigzag=5;
 16:zigzag=12;17:zigzag=19;18:zigzag=26;19:zigzag=33;20:zigzag=40;21:zigzag=48;22:zigzag=41;23:zigzag=34;
 24:zigzag=27;25:zigzag=20;26:zigzag=13;27:zigzag=6;28:zigzag=7;29:zigzag=14;30:zigzag=21;31:zigzag=28;
 32:zigzag=35;33:zigzag=42;34:zigzag=49;35:zigzag=56;36:zigzag=57;37:zigzag=50;38:zigzag=43;39:zigzag=36;
 40:zigzag=29;41:zigzag=22;42:zigzag=15;43:zigzag=23;44:zigzag=30;45:zigzag=37;46:zigzag=44;47:zigzag=51;
 48:zigzag=58;49:zigzag=59;50:zigzag=52;51:zigzag=45;52:zigzag=38;53:zigzag=31;54:zigzag=39;55:zigzag=46;
 56:zigzag=53;57:zigzag=60;58:zigzag=61;59:zigzag=54;60:zigzag=47;61:zigzag=55;62:zigzag=62;default:zigzag=63;
 endcase end endfunction
 task fail;begin error<=1;busy<=0;state<=IDLE;end endtask
 task begin_huff;begin code<=0;first_code<=0;symbol_base<=0;code_length<=0;state<=HUFF;end endtask
 wire idct_valid,idct_done;
 wire [5:0] idct_index;
 wire [7:0] idct_sample;
 wire signed [31:0] dequant=value*$signed({1'b0,quant[{qsel[comp],coeff_index[5:0]}]});
 jidct transform(.clk(clk),.rst_n(rst_n),.clear(state==CLEAR),.we(state==PUT),
 .addr(zigzag(coeff_index[5:0])),
 .coefficient(dequant[23:0]),.start(state==TRANSFORM),
 .busy(),.valid(idct_valid),.done(idct_done),.pixel_index(idct_index),.sample(idct_sample));
 reg [7:0] block_y[0:63],block_cb[0:63],block_cr[0:63];
 reg [5:0] emit_index;
 wire [23:0] converted_rgb;
 jcolor colors(.y(block_y[emit_index]),.cb(block_cb[emit_index]),.cr(block_cr[emit_index]),.rgb(converted_rgb));
 assign pixel_valid=state==EMIT;
 wire [9:0] py={by,3'b000}+{7'd0,emit_index[5:3]};
 assign pixel_address=({9'd0,py}<<9)+({9'd0,py}<<7)+{9'd0,bx,3'b000}+{16'd0,emit_index[2:0]};
 assign pixel_rgb=converted_rgb;
 wire [15:0] amp_next={amplitude[14:0],bit_byte[7]};
 wire signed [23:0] extended=amp_next < (16'd1<<(amplitude_size-1)) ?
  $signed({8'd0,amp_next})+24'sd1-$signed(24'd1<<amplitude_size) : $signed({8'd0,amp_next});
 integer c;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;error<=0;width<=0;height<=0;bits_left<=0;stuffed<=0;
   qvalid<=0;hvalid<=0;sof_seen<=0;comp<=0;bx<=0;by<=0;coeff_index<=0;clear_index<=0;
   marker<=0;length<=0;left<=0;index<=0;table_id<=0;qi<=0;hi<=0;symbol_total<=0;symbol_pos<=0;
   ac<=0;code<=0;first_code<=0;symbol_base<=0;code_length<=0;symbol<=0;symbol_address<=0;
   amplitude<=0;amplitude_left<=0;amplitude_size<=0;value<=0;bit_byte<=0;emit_index<=0;
   for(c=0;c<3;c=c+1)begin predictor[c]<=0;qsel[c]<=0;dcsel[c]<=0;acsel[c]<=0;end
  end else begin
   done<=0;
   if(start && !busy)begin
    state<=SOI0;busy<=1;error<=0;qvalid<=0;hvalid<=0;sof_seen<=0;bits_left<=0;stuffed<=0;
    comp<=0;bx<=0;by<=0;for(c=0;c<3;c=c+1)predictor[c]<=0;
   end else begin
    if(bit_needed && bits_left==0 && take)begin
     if(stuffed)begin if(in_data!=0)fail();else begin bit_byte<=255;bits_left<=8;stuffed<=0;end end
     else if(in_data==255)stuffed<=1;
     else begin bit_byte<=in_data;bits_left<=8;end
    end
    case(state)
     SOI0:if(take)begin if(in_data==255)state<=SOI1;else fail();end
     SOI1:if(take)begin if(in_data==216)state<=MARK0;else fail();end
     MARK0:if(take)begin if(in_data==255)state<=MARK1;else fail();end
     MARK1:if(take && in_data!=255)begin
      marker<=in_data;
      if(in_data==192 || in_data==196 || in_data==219 || in_data==218 || in_data==254 || in_data[7:4]==14)state<=LEN0;
      else fail();
     end
     LEN0:if(take)begin length[15:8]<=in_data;state<=LEN1;end
     LEN1:if(take)begin
      length[7:0]<=in_data;left<={length[15:8],in_data}-16'd2;index<=0;qi<=0;hi<=0;symbol_total<=0;symbol_pos<=0;
      if({length[15:8],in_data}<2)fail();else if({length[15:8],in_data}==2)state<=CHECK;else state<=SEG;
     end
     SEG:if(take)begin
      left<=left-1'b1;index<=index+1'b1;
      if(marker==219)begin
       if(qi==0)begin
        if(in_data[7:1]!=0)fail();
        table_id<={1'b0,in_data[0]};qi<=1;
       end else begin
        if(in_data==0)fail();
        quant[{table_id[0],quant_offset}]<=in_data;
        if(qi==64)begin qvalid[table_id[0]]<=1;qi<=0;end else qi<=qi+1'b1;
       end
      end else if(marker==196)begin
       if(hi==0)begin
        if((in_data & 8'hee)!=0)fail();
        table_id<={in_data[4],in_data[0]};hi<=1;symbol_total<=0;symbol_pos<=0;
       end else if(hi<=16)begin
        counts[{table_id,count_offset}]<=in_data;symbol_total<=symbol_total+in_data;
        if(symbol_total+{1'b0,in_data}>256)fail();
        if(hi==16 && symbol_total+in_data==0)fail();
        hi<=hi+1'b1;
       end else begin
        symbols[{table_id,symbol_pos[7:0]}]<=in_data;
        if(symbol_pos+1==symbol_total)begin hvalid[table_id]<=1;hi<=0;end
        else symbol_pos<=symbol_pos+1'b1;
       end
      end else if(index<16)header[index[3:0]]<=in_data;
      if(left==1)state<=CHECK;
     end
     CHECK:begin
      state<=MARK0;
      if(marker==219)begin if(qi!=0)fail();end
      else if(marker==196)begin if(hi!=0)fail();end
      else if(marker==192)begin
       width<={header[3][1:0],header[4]};height<={header[1][1:0],header[2]};sof_seen<=1;
       for(c=0;c<3;c=c+1)qsel[c]<=header[8+c*3][0];
       if(length!=17 || header[0]!=8 || header[5]!=3 || header[6]!=1 || header[9]!=2 || header[12]!=3 ||
        header[7]!=17 || header[10]!=17 || header[13]!=17 ||
        header[8]>1 || header[11]>1 || header[14]>1 ||
        {header[3],header[4]}==0 || {header[3],header[4]}>640 || header[4][2:0]!=0 ||
        {header[1],header[2]}==0 || {header[1],header[2]}>480 || header[2][2:0]!=0 ||
        (REQUIRED_W!=0 && {header[3],header[4]}!=REQUIRED_W) ||
        (REQUIRED_H!=0 && {header[1],header[2]}!=REQUIRED_H))fail();
      end else if(marker==218)begin
       for(c=0;c<3;c=c+1)begin dcsel[c]<=header[2+c*2][4];acsel[c]<=header[2+c*2][0];end
       if(!sof_seen || length!=12 || header[0]!=3 || header[1]!=1 || header[3]!=2 || header[5]!=3 ||
        (header[2]&8'hee)!=0 || (header[4]&8'hee)!=0 || (header[6]&8'hee)!=0 ||
        header[7]!=0 || header[8]!=63 || header[9]!=0 ||
        !qvalid[qsel[0]] || !qvalid[qsel[1]] || !qvalid[qsel[2]] ||
        !hvalid[{1'b0,header[2][4]}] || !hvalid[{1'b1,header[2][0]}] ||
        !hvalid[{1'b0,header[4][4]}] || !hvalid[{1'b1,header[4][0]}] ||
        !hvalid[{1'b0,header[6][4]}] || !hvalid[{1'b1,header[6][0]}])fail();
       else begin state<=CLEAR;clear_index<=0;coeff_index<=0;ac<=0;end
      end
     end
     CLEAR:begin_huff();
     HUFF:if(bits_left!=0)begin
      bit_byte<=bit_byte<<1;bits_left<=bits_left-1'b1;
      if(next_code>=first_code && next_code<limit_code)begin
       if(symbol_base+next_code-first_code>=256)fail();
       else begin symbol_address<={htable,8'd0}+symbol_base+next_code-first_code;state<=SYMBOL;end
      end else if(code_length==15)fail();
      else begin code<=next_code[15:0];first_code<=limit_code<<1;symbol_base<=symbol_base+hcount;code_length<=code_length+1'b1;end
     end
     SYMBOL:begin
      symbol<=symbols[symbol_address];amplitude<=0;
      amplitude_size<=symbols[symbol_address][3:0];amplitude_left<=symbols[symbol_address][3:0];
      if(!ac)begin
       if(symbols[symbol_address]>11)fail();
       else if(symbols[symbol_address]==0)begin value<=predictor[comp];state<=PUT;end
       else state<=AMP;
      end else if(symbols[symbol_address]==0)state<=TRANSFORM;
      else if(symbols[symbol_address]==240)begin
       if(coeff_index+16>64)fail();
       else if(coeff_index+16==64)state<=TRANSFORM;
       else begin coeff_index<=coeff_index+16;begin_huff();end
      end else if(symbols[symbol_address][3:0]==0 || symbols[symbol_address][3:0]>10 ||
        coeff_index+{3'd0,symbols[symbol_address][7:4]}>=64)fail();
      else begin coeff_index<=coeff_index+{3'd0,symbols[symbol_address][7:4]};state<=AMP;end
     end
     AMP:if(bits_left!=0)begin
      bit_byte<=bit_byte<<1;bits_left<=bits_left-1'b1;amplitude<=amp_next;amplitude_left<=amplitude_left-1'b1;
      if(amplitude_left==1)begin
       if(ac)value<=extended;
       else begin value<=predictor[comp]+extended;predictor[comp]<=predictor[comp]+extended;end
       state<=PUT;
      end
     end
     PUT:begin
      if(coeff_index==63)state<=TRANSFORM;
      else begin coeff_index<=coeff_index+1'b1;ac<=1;begin_huff();end
     end
     TRANSFORM:state<=WAIT_IDCT;
     WAIT_IDCT:begin
      if(idct_valid)begin
       case(comp)0:block_y[idct_index]<=idct_sample;1:block_cb[idct_index]<=idct_sample;2:block_cr[idct_index]<=idct_sample;endcase
      end
      if(idct_done)begin
       if(comp==2)begin state<=EMIT;emit_index<=0;end
       else begin comp<=comp+1'b1;state<=CLEAR;clear_index<=0;coeff_index<=0;ac<=0;end
      end
     end
     EMIT:if(pixel_ready)begin
      if(emit_index==63)begin
       comp<=0;clear_index<=0;coeff_index<=0;ac<=0;
       if(bx+1==(width>>3))begin bx<=0;if(by+1==(height>>3))begin state<=EOI0;bits_left<=0;stuffed<=0;end
        else begin by<=by+1'b1;state<=CLEAR;end end
       else begin bx<=bx+1'b1;state<=CLEAR;end
      end else emit_index<=emit_index+1'b1;
     end
     EOI0:if(take)begin if(in_data==255)state<=EOI1;else fail();end
     EOI1:if(take)begin if(in_data==217)begin done<=1;busy<=0;state<=IDLE;end else if(in_data!=255)fail();end
     default:begin end
    endcase
   end
  end
 end
endmodule
