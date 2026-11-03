module frame #(
    parameter integer SDRAM_POWER_CYCLES=8400
)(
    input wire pix_clk, rst_n, mem_clk, mem_rst_n, sdram_clk,
    input wire load_start, write_valid, display_enable,
    input wire [2:0] front_bank,write_slot,
    input wire [18:0] write_address,
    input wire [23:0] write_data,
    input wire flush_start,
    output reg flush_done,
    input wire [9:0] x,y,
    input wire de,
    output wire [23:0] read_data,
    output wire line_available,
    output wire initialized,
    output wire write_ready,
    output reg overflow, underrun,
    output wire memory_fault
);
    wire fifo_full,fifo_empty,fifo_valid;
    wire [44:0] fifo_data;
    function [20:0] slot_base;
        input [2:0] id;
        begin
            case(id)
                0:slot_base=21'h000000;1:slot_base=21'h050000;
                2:slot_base=21'h0a0000;3:slot_base=21'h0f0000;
                4:slot_base=21'h140000;5:slot_base=21'h190000;
                default:slot_base=21'h1e0000;
            endcase
        end
    endfunction
    wire valid_write_address=write_address<19'd307200 && write_slot<6;
    wire [20:0] pixel_word_address=slot_base(write_slot)+{2'b0,write_address};
    wire controller_initialized,controller_fault;
    reg fifo_pop;
    fifo #(.WIDTH(45)) queue(
        .wclk(pix_clk),.wrst_n(rst_n),.wvalid(write_valid && valid_write_address),
        .wdata({pixel_word_address,write_data}),.full(fifo_full),
        .rclk(mem_clk),.rrst_n(mem_rst_n),.pop(fifo_pop),
        .empty(fifo_empty),.valid(fifo_valid),.data(fifo_data));

    reg line_request,flush_request;
    reg [8:0] requested_y;
    reg [2:0] requested_frame;
    reg requested_cache;
    reg line_ack,flush_ack;
    (* async_reg="true" *) reg line_ack_meta,line_ack_sync;
    (* async_reg="true" *) reg flush_ack_meta,flush_ack_sync;
    (* async_reg="true" *) reg init_meta,init_sync,err_meta,err_sync;
    reg flush_reported;
    reg [1:0] cache_valid;
    reg [8:0] cache_y0,cache_y1;
    reg [2:0] cache_frame0,cache_frame1;
    reg acknowledged;
    wire line_inflight=line_request!=line_ack_sync;
    wire cache_match=y[0] ? cache_valid[1] && cache_y1==y[8:0] && cache_frame1==front_bank :
                           cache_valid[0] && cache_y0==y[8:0] && cache_frame0==front_bank;
    assign line_available=cache_match;
    assign initialized=init_sync;
    assign write_ready=!fifo_full;
    assign memory_fault=err_sync;
    always @(posedge pix_clk or negedge rst_n) begin
        if(!rst_n) begin
            line_request<=0;flush_request<=0;requested_y<=0;
            requested_frame<=0;requested_cache<=0;
            line_ack_meta<=0;line_ack_sync<=0;flush_ack_meta<=0;flush_ack_sync<=0;
            init_meta<=0;init_sync<=0;err_meta<=0;err_sync<=0;
            flush_done<=0;flush_reported<=1;cache_valid<=0;
            cache_y0<=0;cache_y1<=0;cache_frame0<=0;cache_frame1<=0;
            acknowledged<=0;overflow<=0;underrun<=0;
        end else begin
            line_ack_meta<=line_ack;line_ack_sync<=line_ack_meta;
            flush_ack_meta<=flush_ack;flush_ack_sync<=flush_ack_meta;
            init_meta<=controller_initialized;init_sync<=init_meta;
            err_meta<=controller_fault;err_sync<=err_meta;
            flush_done<=0;
            if(flush_start) begin flush_request<=~flush_request;flush_reported<=0;end
            else if(!flush_reported && flush_ack_sync==flush_request) begin
                flush_done<=1;flush_reported<=1;
            end
            if(line_ack_sync!=acknowledged) begin
                acknowledged<=line_ack_sync;
                cache_valid[requested_cache]<=1;
                if(requested_cache) begin cache_y1<=requested_y;cache_frame1<=requested_frame;end
                else begin cache_y0<=requested_y;cache_frame0<=requested_frame;end
            end
            // Row 0 is prefetched late in vertical blank, after the swap at row 480.
            if(display_enable && init_sync && !line_inflight &&
               ((x==0 && y==520) || (de && x==0 && y<479))) begin
                requested_y<=y==520 ? 9'd0 : y[8:0]+1'b1;
                requested_cache<=y==520 ? 1'b0 : ~y[0];
                requested_frame<=front_bank;line_request<=~line_request;
                cache_valid[y==520 ? 1'b0 : ~y[0]]<=0;
            end
            if(!display_enable) cache_valid<=0;
            if(load_start) begin overflow<=0;underrun<=0;end
            else begin
                if(write_valid && (fifo_full || !valid_write_address)) overflow<=1;
                if(display_enable && de && x==0 && !cache_match) underrun<=1;
            end
        end
    end

    (* async_reg="true" *) reg line_req_meta,line_req_sync;
    (* async_reg="true" *) reg flush_req_meta,flush_req_sync;
    reg [2:0] service_state;
    localparam [2:0] IDLE=0,POP_WAIT=1,WRITE_REQ=2,WRITE_WAIT=3,
        READ_REQ=4,READ_WAIT=5;
    reg [44:0] saved_pixel;
    reg [20:0] line_base;
    reg [2:0] saved_frame;
    reg saved_cache;
    reg [2:0] chunk;
    reg [9:0] line_index;
    wire controller_accept,controller_done,controller_read_valid;
    wire [23:0] controller_data;
    wire controller_request=service_state==WRITE_REQ || service_state==READ_REQ;
    wire [20:0] controller_address=service_state==WRITE_REQ ?
        saved_pixel[44:24] : line_base+{11'd0,chunk,7'd0};
    // The request payload remains stable until the memory-side acknowledgment.
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if(!mem_rst_n) begin
            line_req_meta<=0;line_req_sync<=0;flush_req_meta<=0;flush_req_sync<=0;
            service_state<=IDLE;fifo_pop<=0;saved_pixel<=0;
            line_base<=0;saved_frame<=0;saved_cache<=0;chunk<=0;line_index<=0;
            line_ack<=0;flush_ack<=0;
        end else begin
            line_req_meta<=line_request;line_req_sync<=line_req_meta;
            flush_req_meta<=flush_request;flush_req_sync<=flush_req_meta;
            fifo_pop<=0;
            case(service_state)
                IDLE: if(controller_initialized) begin
                    if(line_req_sync!=line_ack) begin
                        line_base<=slot_base(requested_frame)+
                            ({12'd0,requested_y}<<9)+({12'd0,requested_y}<<7);
                        saved_frame<=requested_frame;saved_cache<=requested_cache;
                        chunk<=0;line_index<=0;service_state<=READ_REQ;
                    end else if(!fifo_empty) begin fifo_pop<=1;service_state<=POP_WAIT;end
                    else if(controller_accept) flush_ack<=flush_req_sync;
                end
                POP_WAIT: if(fifo_valid) begin saved_pixel<=fifo_data;service_state<=WRITE_REQ;end
                WRITE_REQ: if(controller_accept) service_state<=WRITE_WAIT;
                WRITE_WAIT: if(controller_done) service_state<=IDLE;
                READ_REQ: if(controller_accept) service_state<=READ_WAIT;
                READ_WAIT: begin
                    if(controller_read_valid) line_index<=line_index+1'b1;
                    if(controller_done) begin
                        if(chunk==4) begin line_ack<=line_req_sync;service_state<=IDLE;end
                        else begin chunk<=chunk+1'b1;service_state<=READ_REQ;end
                    end
                end
                default:service_state<=IDLE;
            endcase
        end
    end
    reg [23:0] line0[0:639],line1[0:639];
    reg [23:0] data0,data1;
    reg read_cache;
    always @(posedge mem_clk) begin
        if(service_state==READ_WAIT && controller_read_valid && line_index<640) begin
            if(saved_cache) line1[line_index]<=controller_data;
            else line0[line_index]<=controller_data;
        end
    end
    always @(posedge pix_clk) begin
        if(x<640) begin data0<=line0[x];data1<=line1[x];end
        read_cache<=y[0];
    end
    assign read_data=read_cache ? data1 : data0;
    wire sd_clk,sd_cke,sd_cs_n,sd_ras_n,sd_cas_n,sd_we_n;
    wire [10:0] sd_addr;
    wire [1:0] sd_ba;
    wire [3:0] sd_dm;
    wire [31:0] sd_dq;
    sdram #(.POWER_CYCLES(SDRAM_POWER_CYCLES)) controller(
        .clk(mem_clk),.rst_n(mem_rst_n),.sdram_clk(sdram_clk),
        .request(controller_request),.write_request(service_state==WRITE_REQ),
        .address(controller_address),.write_data(saved_pixel[23:0]),
        .accept(controller_accept),.initialized(controller_initialized),
        .done(controller_done),.read_valid(controller_read_valid),.read_data(controller_data),
        .refresh_fault(controller_fault),.sd_clk(sd_clk),.sd_cke(sd_cke),.sd_cs_n(sd_cs_n),
        .sd_ras_n(sd_ras_n),.sd_cas_n(sd_cas_n),.sd_we_n(sd_we_n),
        .sd_addr(sd_addr),.sd_ba(sd_ba),.sd_dm(sd_dm),.sd_dq(sd_dq));
    // The installed TD primitive uses four dm ports; the older PDF shows a dm bus.
    EG_PHY_SDRAM_2M_32 memory(
        .clk(sd_clk),.cke(sd_cke),.cs_n(sd_cs_n),.ras_n(sd_ras_n),.cas_n(sd_cas_n),
        .we_n(sd_we_n),.addr(sd_addr),.ba(sd_ba),.dq(sd_dq),
        .dm0(sd_dm[0]),.dm1(sd_dm[1]),.dm2(sd_dm[2]),.dm3(sd_dm[3]));
endmodule
