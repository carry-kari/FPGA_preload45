module sdram #(
    parameter integer POWER_CYCLES=8400,
    parameter integer REFRESH_CYCLES=320
)(
    input wire clk, rst_n, sdram_clk,
    input wire request, write_request,
    input wire [20:0] address,
    input wire [23:0] write_data,
    output wire accept,
    output reg initialized, done, read_valid,
    output reg [23:0] read_data,
    output reg refresh_fault,
    output wire sd_clk,
    output reg sd_cke,
    output wire sd_cs_n,
    output wire sd_ras_n, sd_cas_n, sd_we_n,
    output reg [10:0] sd_addr,
    output reg [1:0] sd_ba,
    output wire [3:0] sd_dm,
    inout wire [31:0] sd_dq
);
    localparam [3:0] POWER=0, INIT_PRE=1, INIT_REF=2, MODE=3, IDLE=4,
        ACTIVATE=5, ACCESS=6, READ=7, DRAIN=8, WRITE=9, PRECHARGE=10,
        COMPLETE=11, REFRESH=12, WAIT=13;
    localparam [2:0] NOP=3'b111, PRE=3'b010, REF=3'b001,
        MRS=3'b000, ACT=3'b011, RD=3'b101, WR=3'b100;
    reg [3:0] state, after_wait;
    reg [14:0] power_count;
    reg [9:0] refresh_count;
    reg [3:0] wait_count;
    reg init_second;
    reg [2:0] command;
    reg [20:0] saved_address;
    reg [23:0] saved_data;
    reg saved_write;
    reg [7:0] column;
    reg [6:0] read_count;
    reg [3:0] read_pipe;
    reg dq_enable;
    reg [31:0] dq_data;
    assign sd_clk=sdram_clk;
    assign sd_cs_n=1'b0;
    assign {sd_ras_n,sd_cas_n,sd_we_n}=command;
    assign sd_dm=initialized ? 4'b0000 : 4'b1111;
    assign sd_dq=dq_enable ? dq_data : 32'bz;
    assign accept=initialized && state==IDLE && refresh_count<REFRESH_CYCLES;
    task delay_cycles;
        input [3:0] cycles;
        input [3:0] destination;
        begin wait_count<=cycles-1'b1;after_wait<=destination;state<=WAIT;end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=POWER;after_wait<=IDLE;power_count<=0;refresh_count<=0;
            wait_count<=0;init_second<=0;command<=NOP;sd_cke<=0;
            sd_addr<=0;sd_ba<=0;saved_address<=0;saved_data<=0;
            saved_write<=0;column<=0;read_count<=0;read_pipe<=0;
            dq_enable<=0;dq_data<=0;initialized<=0;done<=0;
            read_valid<=0;read_data<=0;refresh_fault<=0;
        end else begin
            command<=NOP;dq_enable<=0;done<=0;
            read_pipe<={read_pipe[2:0],state==READ};
            read_valid<=read_pipe[3];
            if(read_pipe[3]) read_data<=sd_dq[23:0];
            if(initialized && refresh_count<1023) refresh_count<=refresh_count+1'b1;
            if(initialized && refresh_count>=630) refresh_fault<=1;
            case(state)
                POWER: if(power_count==POWER_CYCLES-1) begin
                    sd_cke<=1;delay_cycles(3,INIT_PRE);
                end else power_count<=power_count+1'b1;
                INIT_PRE: begin command<=PRE;sd_addr<=11'h400;delay_cycles(3,INIT_REF);end
                INIT_REF: begin
                    command<=REF;
                    if(!init_second) begin init_second<=1;delay_cycles(6,INIT_REF);end
                    else delay_cycles(6,MODE);
                end
                MODE: begin command<=MRS;sd_ba<=0;sd_addr<=11'h030;delay_cycles(3,IDLE);end
                IDLE: begin
                    initialized<=1;
                    if(!initialized) refresh_count<=0;
                    else if(refresh_count>=REFRESH_CYCLES) state<=REFRESH;
                    else if(request) begin
                        saved_address<=address;saved_data<=write_data;
                        saved_write<=write_request;state<=ACTIVATE;
                    end
                end
                ACTIVATE: begin
                    command<=ACT;sd_ba<=saved_address[20:19];
                    sd_addr<=saved_address[18:8];column<=saved_address[7:0];
                    delay_cycles(3,ACCESS);
                end
                ACCESS: if(saved_write) state<=WRITE;
                    else begin read_count<=0;state<=READ;end
                READ: begin
                    command<=RD;sd_addr<={3'b000,column};column<=column+1'b1;
                    if(read_count==127) state<=DRAIN;
                    else read_count<=read_count+1'b1;
                end
                DRAIN: if(read_pipe==0) state<=PRECHARGE;
                WRITE: begin
                    command<=WR;sd_addr<={3'b000,column};
                    dq_enable<=1;dq_data<={8'd0,saved_data};
                    delay_cycles(3,PRECHARGE);
                end
                PRECHARGE: begin command<=PRE;sd_addr<=11'h400;delay_cycles(3,COMPLETE);end
                COMPLETE: begin done<=1;state<=IDLE;end
                REFRESH: begin command<=REF;refresh_count<=0;delay_cycles(6,IDLE);end
                WAIT: if(wait_count==0) state<=after_wait;
                    else wait_count<=wait_count-1'b1;
                default: begin state<=POWER;initialized<=0;refresh_fault<=1;end
            endcase
        end
    end
endmodule
