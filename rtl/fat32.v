module fat32 #(
    parameter [87:0] NAME0 = "PIC0001 BMP",
    parameter [87:0] NAME1 = "PIC0002 BMP",
    parameter [87:0] NAME2 = "PIC0003 BMP",
    parameter [87:0] NAME3 = "PIC0004 BMP",
    parameter [87:0] NAME4 = "VIDEO   MJP",
    parameter integer MAX_FILE_BYTES = 536870912,
    parameter integer MAX_DIR_CLUSTERS = 128,
    parameter integer IO_TIMEOUT_CYCLES = 25200000
) (
    input wire clk, rst_n,
    input wire start,
    input wire [2:0] file_slot,
    output reg busy, done, error,
    output reg [3:0] error_code,
    output reg mounted,
    output reg [31:0] file_length,
    input wire byte_ready,
    output reg byte_valid,
    output reg [7:0] byte_data,
    input wire sd_initialized, sd_read_done, sd_error,
    input wire [3:0] sd_error_code,
    input wire sd_byte_valid,
    input wire [7:0] sd_byte_data,
    output reg read_start,
    output reg read_abort,
    output reg [31:0] read_lba
);
    localparam [4:0] IDLE=0, IO_REQ=1, IO_WAIT=2, META_BEGIN=3,
        META_WAIT=4, META_BYTE=5, BOOT_CHECK=6, GEOMETRY=7, MOUNT_CHECK=8,
        DIR_BEGIN=9, DIR_WAIT=10, DIR_BYTE=11, DIR_CHECK=12,
        DIR_ADVANCE=13, FAT_REQ=14, FAT_BEGIN=15, FAT_WAIT=16,
        FAT_BYTE=17, FAT_CHECK=18, DATA_BEGIN=19, DATA_WAIT=20,
        DATA_BYTE=21, DATA_ADVANCE=22, FINISH=23;
    reg [4:0] state, io_return;
    reg [7:0] sector_ram [0:511];
    reg [8:0] ram_addr;
    reg [7:0] ram_data;
    reg [9:0] fill_count;
    always @(posedge clk) begin
        if (state==IO_WAIT && sd_byte_valid && fill_count<512)
            sector_ram[fill_count[8:0]] <= sd_byte_data;
        ram_data <= sector_ram[ram_addr];
    end

    reg [87:0] target_name;
    reg boot_at_zero;
    reg [31:0] volume_lba, partition_size;
    reg [15:0] bytes_per_sector, reserved_sectors, root_entries, total16,
               fat16, ext_flags, fs_version, signature;
    reg [7:0] sectors_per_cluster, fat_count, jump_byte;
    reg [31:0] total_sectors, fat_size, root_cluster;
    reg [7:0] partition_type, partition_status;
    reg [31:0] partition_start, partition_length;
    reg partition_found;
    reg [31:0] selected_partition, selected_length;
    reg [6:0] spc_shift;
    reg [31:0] fat_base, data_base, cluster_count;
    wire [32:0] overhead = {17'd0,reserved_sectors} +
        (fat_count==2 ? ({1'b0,fat_size}<<1) : {1'b0,fat_size});
    wire [32:0] volume_end = {1'b0,volume_lba}+{1'b0,total_sectors};
    wire [32:0] active_fat_offset = ext_flags[7] && ext_flags[3:0]==1 ?
                                   {1'b0,fat_size} : 33'd0;
    wire [39:0] fat_capacity = {8'd0,fat_size}<<7;
    wire [3:0] partition_byte = ram_addr[3:0]-4'd14;
    reg [31:0] cluster, chain_anchor;
    reg [31:0] chain_power, chain_span;
    reg [31:0] chain_steps;
    reg [7:0] sector_in_cluster;
    reg chain_file;
    localparam integer IO_W = IO_TIMEOUT_CYCLES>1 ? $clog2(IO_TIMEOUT_CYCLES) : 1;
    reg [IO_W-1:0] io_wait_count;
    reg io_recovering;
    reg [31:0] fat_value, remaining;
    reg [1:0] fat_byte_index;
    reg [9:0] sector_bytes;
    reg [31:0] entry_cluster, entry_size;
    reg [7:0] entry_first, entry_attr;
    reg name_match;
    wire [31:0] cluster_lba = data_base + ((cluster-2)<<spc_shift) +
                              sector_in_cluster;
    wire [31:0] next_cluster = fat_value & 32'h0fffffff;
    wire [31:0] first_cluster = entry_cluster & 32'h0fffffff;

    function [7:0] name_byte;
        input [87:0] name;
        input [3:0] index;
        begin
            case(index)
                0:name_byte=name[87:80]; 1:name_byte=name[79:72];
                2:name_byte=name[71:64]; 3:name_byte=name[63:56];
                4:name_byte=name[55:48]; 5:name_byte=name[47:40];
                6:name_byte=name[39:32]; 7:name_byte=name[31:24];
                8:name_byte=name[23:16]; 9:name_byte=name[15:8];
                default:name_byte=name[7:0];
            endcase
        end
    endfunction
    function [7:0] upper_ascii;
        input [7:0] value;
        begin upper_ascii=(value>=8'h61 && value<=8'h7a) ? value-8'd32 : value; end
    endfunction
    function [6:0] cluster_shift;
        input [7:0] spc;
        begin
            case(spc)
                1:cluster_shift=0; 2:cluster_shift=1; 4:cluster_shift=2;
                8:cluster_shift=3; 16:cluster_shift=4; 32:cluster_shift=5;
                64:cluster_shift=6; 128:cluster_shift=7;
                default:cluster_shift=127;
            endcase
        end
    endfunction
    task fail;
        input [3:0] code;
        begin busy<=0; error<=1; error_code<=code; state<=IDLE; end
    endtask
    task read_sector;
        input [31:0] lba;
        input [4:0] next_state;
        begin read_lba<=lba; io_return<=next_state; state<=IO_REQ; end
    endtask
    task reset_chain;
        input [31:0] first;
        begin
            cluster<=first; chain_anchor<=first; chain_power<=1;
            chain_span<=0; chain_steps<=0; sector_in_cluster<=0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; io_return<=IDLE; busy<=0; done<=0; error<=0;
            error_code<=0; mounted<=0; file_length<=0; byte_valid<=0;
            byte_data<=0; read_start<=0; read_abort<=0; read_lba<=0; fill_count<=0;
            io_wait_count<=0; io_recovering<=0;
            ram_addr<=0; target_name<=NAME0; boot_at_zero<=1;
            volume_lba<=0; partition_size<=0; bytes_per_sector<=0;
            reserved_sectors<=0; root_entries<=0; total16<=0; fat16<=0;
            ext_flags<=0; fs_version<=0; signature<=0; sectors_per_cluster<=0;
            fat_count<=0; jump_byte<=0; total_sectors<=0; fat_size<=0;
            root_cluster<=0; partition_type<=0; partition_status<=0;
            partition_start<=0; partition_length<=0; partition_found<=0;
            selected_partition<=0; selected_length<=0; spc_shift<=0;
            fat_base<=0; data_base<=0; cluster_count<=0; cluster<=0;
            chain_anchor<=0; chain_power<=1; chain_span<=0; chain_steps<=0;
            sector_in_cluster<=0; chain_file<=0;
            fat_value<=0; remaining<=0; fat_byte_index<=0; sector_bytes<=0;
            entry_cluster<=0; entry_size<=0; entry_first<=0; entry_attr<=0;
            name_match<=1;
        end else begin
            read_start<=0; read_abort<=0; done<=0; error<=0; byte_valid<=0;
            if(sd_error) begin
                mounted<=0; fail(sd_error_code);
            end else if(!sd_initialized) begin
                mounted<=0; busy<=0; state<=IDLE; io_recovering<=0;
            end else case(state)
                IDLE: if(start && !io_recovering) begin
                    busy<=1; error_code<=0; file_length<=0;
                    case(file_slot)
                        0:target_name<=NAME0; 1:target_name<=NAME1;
                        2:target_name<=NAME2; 3:target_name<=NAME3;
                        4:target_name<=NAME4;
                        default:target_name<=NAME0;
                    endcase
                    if(mounted) begin
                        reset_chain(root_cluster); chain_file<=0;
                        read_sector(data_base+((root_cluster-2)<<spc_shift),DIR_BEGIN);
                    end else begin
                        boot_at_zero<=1; volume_lba<=0; partition_size<=0;
                        read_sector(0,META_BEGIN);
                    end
                end
                IO_REQ: begin
                    read_start<=1; fill_count<=0; io_wait_count<=0; state<=IO_WAIT;
                end
                IO_WAIT: begin
                    if(sd_byte_valid && fill_count<512) fill_count<=fill_count+1'b1;
                    if(sd_read_done) begin
                        if(fill_count!=512) fail(15);
                        else state<=io_return;
                    end else if(io_wait_count==IO_TIMEOUT_CYCLES-1) begin
                        // Abort the backend before accepting another file request.
                        mounted<=0; io_recovering<=1; read_abort<=1; fail(11);
                    end else io_wait_count<=io_wait_count+1'b1;
                end
                META_BEGIN: begin
                    ram_addr<=0; bytes_per_sector<=0; reserved_sectors<=0;
                    root_entries<=0; total16<=0; fat16<=0; ext_flags<=0;
                    fs_version<=0; signature<=0; sectors_per_cluster<=0;
                    fat_count<=0; total_sectors<=0; fat_size<=0; root_cluster<=0;
                    partition_found<=0; selected_partition<=0; selected_length<=0;
                    partition_start<=0; partition_length<=0; state<=META_WAIT;
                end
                META_WAIT: state<=META_BYTE;
                META_BYTE: begin
                    case(ram_addr)
                        0:jump_byte<=ram_data;
                        11:bytes_per_sector[7:0]<=ram_data;
                        12:bytes_per_sector[15:8]<=ram_data;
                        13:sectors_per_cluster<=ram_data;
                        14:reserved_sectors[7:0]<=ram_data;
                        15:reserved_sectors[15:8]<=ram_data;
                        16:fat_count<=ram_data;
                        17:root_entries[7:0]<=ram_data;
                        18:root_entries[15:8]<=ram_data;
                        19:total16[7:0]<=ram_data;
                        20:total16[15:8]<=ram_data;
                        22:fat16[7:0]<=ram_data;
                        23:fat16[15:8]<=ram_data;
                        32:total_sectors[7:0]<=ram_data;
                        33:total_sectors[15:8]<=ram_data;
                        34:total_sectors[23:16]<=ram_data;
                        35:total_sectors[31:24]<=ram_data;
                        36:fat_size[7:0]<=ram_data;
                        37:fat_size[15:8]<=ram_data;
                        38:fat_size[23:16]<=ram_data;
                        39:fat_size[31:24]<=ram_data;
                        40:ext_flags[7:0]<=ram_data;
                        41:ext_flags[15:8]<=ram_data;
                        42:fs_version[7:0]<=ram_data;
                        43:fs_version[15:8]<=ram_data;
                        44:root_cluster[7:0]<=ram_data;
                        45:root_cluster[15:8]<=ram_data;
                        46:root_cluster[23:16]<=ram_data;
                        47:root_cluster[31:24]<=ram_data;
                        510:signature[7:0]<=ram_data;
                        511:signature[15:8]<=ram_data;
                        default:begin end
                    endcase
                    if(ram_addr>=446 && ram_addr<510) begin
                        case(partition_byte)
                            0:partition_status<=ram_data;
                            4:partition_type<=ram_data;
                            8:partition_start[7:0]<=ram_data;
                            9:partition_start[15:8]<=ram_data;
                            10:partition_start[23:16]<=ram_data;
                            11:partition_start[31:24]<=ram_data;
                            12:partition_length[7:0]<=ram_data;
                            13:partition_length[15:8]<=ram_data;
                            14:partition_length[23:16]<=ram_data;
                            15: if(!partition_found && (partition_type==8'h0b || partition_type==8'h0c) &&
                                   (partition_status==0 || partition_status==8'h80) && partition_start!=0) begin
                                partition_found<=1; selected_partition<=partition_start;
                                selected_length<={ram_data,partition_length[23:0]};
                            end
                        endcase
                    end
                    if(ram_addr==511) state<=BOOT_CHECK;
                    else begin ram_addr<=ram_addr+1'b1; state<=META_WAIT; end
                end
                BOOT_CHECK: begin
                    if(signature!=16'haa55) fail(12);
                    else if(bytes_per_sector==512 && (jump_byte==8'heb || jump_byte==8'he9)) begin
                        if(cluster_shift(sectors_per_cluster)==127 || reserved_sectors==0 ||
                           !(fat_count==1 || fat_count==2) || root_entries!=0 || total16!=0 ||
                           fat16!=0 || fs_version!=0 || fat_size==0 || total_sectors==0 ||
                           (ext_flags[7] && ext_flags[3:0]>=fat_count)) fail(12);
                        else begin spc_shift<=cluster_shift(sectors_per_cluster); state<=GEOMETRY; end
                    end else if(boot_at_zero && partition_found && selected_length!=0) begin
                        volume_lba<=selected_partition; partition_size<=selected_length;
                        boot_at_zero<=0; read_sector(selected_partition,META_BEGIN);
                    end else fail(12);
                end
                GEOMETRY: begin
                    if(overhead>={1'b0,total_sectors} || volume_end>33'h100000000 ||
                       (partition_size!=0 && total_sectors>partition_size)) fail(12);
                    else begin
                        cluster_count<=(total_sectors-overhead[31:0])>>spc_shift;
                        data_base<=volume_lba+overhead[31:0];
                        fat_base<=volume_lba+reserved_sectors+active_fat_offset[31:0];
                        state<=MOUNT_CHECK;
                    end
                end
                MOUNT_CHECK: begin
                    if(cluster_count<65525 || cluster_count>=32'h0ffffff0 ||
                       fat_capacity<({1'b0,cluster_count}+2) ||
                       root_cluster<2 || root_cluster>cluster_count+1) fail(12);
                    else begin
                        mounted<=1; reset_chain(root_cluster); chain_file<=0;
                        read_sector(data_base+((root_cluster-2)<<spc_shift),DIR_BEGIN);
                    end
                end
                DIR_BEGIN: begin
                    ram_addr<=0; name_match<=1; entry_cluster<=0; entry_size<=0;
                    state<=DIR_WAIT;
                end
                DIR_WAIT: state<=DIR_BYTE;
                DIR_BYTE: begin
                    if(ram_addr[4:0]<11 && upper_ascii(ram_data)!=name_byte(target_name,ram_addr[3:0]))
                        name_match<=0;
                    case(ram_addr[4:0])
                        0:entry_first<=ram_data; 11:entry_attr<=ram_data;
                        20:entry_cluster[23:16]<=ram_data;
                        21:entry_cluster[31:24]<=ram_data;
                        26:entry_cluster[7:0]<=ram_data;
                        27:entry_cluster[15:8]<=ram_data;
                        28:entry_size[7:0]<=ram_data; 29:entry_size[15:8]<=ram_data;
                        30:entry_size[23:16]<=ram_data; 31:entry_size[31:24]<=ram_data;
                    endcase
                    if(ram_addr[4:0]==31) state<=DIR_CHECK;
                    else begin ram_addr<=ram_addr+1'b1; state<=DIR_WAIT; end
                end
                DIR_CHECK: begin
                    if(entry_first==0) fail(13);
                    else if(entry_first!=8'he5 && (entry_attr & 8'h18)==0 && name_match) begin
                        if(entry_size>MAX_FILE_BYTES) fail(9);
                        else if(entry_size<54) fail(15);
                        else if(first_cluster<2 || first_cluster>cluster_count+1) fail(14);
                        else begin
                            file_length<=entry_size; remaining<=entry_size;
                            reset_chain(first_cluster); chain_file<=1;
                            read_sector(data_base+((first_cluster-2)<<spc_shift),DATA_BEGIN);
                        end
                    end else if(ram_addr==511) state<=DIR_ADVANCE;
                    else begin
                        ram_addr<=ram_addr+1'b1; name_match<=1;
                        entry_cluster<=0; entry_size<=0; state<=DIR_WAIT;
                    end
                end
                DIR_ADVANCE: begin
                    if(sector_in_cluster+1<sectors_per_cluster) begin
                        sector_in_cluster<=sector_in_cluster+1'b1;
                        read_sector(cluster_lba+1,DIR_BEGIN);
                    end else state<=FAT_REQ;
                end
                FAT_REQ: read_sector(fat_base+(cluster>>7),FAT_BEGIN);
                FAT_BEGIN: begin
                    ram_addr<={cluster[6:0],2'b00}; fat_byte_index<=0;
                    fat_value<=0; state<=FAT_WAIT;
                end
                FAT_WAIT: state<=FAT_BYTE;
                FAT_BYTE: begin
                    case(fat_byte_index)
                        0:fat_value[7:0]<=ram_data; 1:fat_value[15:8]<=ram_data;
                        2:fat_value[23:16]<=ram_data; 3:fat_value[31:24]<=ram_data;
                    endcase
                    if(fat_byte_index==3) state<=FAT_CHECK;
                    else begin
                        fat_byte_index<=fat_byte_index+1'b1; ram_addr<=ram_addr+1'b1;
                        state<=FAT_WAIT;
                    end
                end
                FAT_CHECK: begin
                    if(next_cluster>=32'h0ffffff8) begin
                        fail(chain_file ? 4'd15 : 4'd13);
                    end else if(next_cluster<2 || next_cluster>cluster_count+1 ||
                                next_cluster>=32'h0ffffff0) fail(14);
                    else if(next_cluster==chain_anchor) fail(10);
                    else if(chain_steps>=(chain_file ? ((MAX_FILE_BYTES+511)/512) : MAX_DIR_CLUSTERS)-1)
                        fail(chain_file ? 4'd9 : 4'd13);
                    else begin
                        cluster<=next_cluster; sector_in_cluster<=0; chain_steps<=chain_steps+1'b1;
                        if(chain_span+1==chain_power) begin
                            chain_anchor<=next_cluster; chain_span<=0; chain_power<=chain_power<<1;
                        end else chain_span<=chain_span+1'b1;
                        read_sector(data_base+((next_cluster-2)<<spc_shift),chain_file ? DATA_BEGIN : DIR_BEGIN);
                    end
                end
                DATA_BEGIN: begin
                    ram_addr<=0; sector_bytes<=remaining>=512 ? 10'd512 : remaining[9:0];
                    state<=DATA_WAIT;
                end
                DATA_WAIT: state<=DATA_BYTE;
                DATA_BYTE: if(byte_ready) begin
                    byte_valid<=1; byte_data<=ram_data; remaining<=remaining-1'b1;
                    if({1'b0,ram_addr}+1==sector_bytes) state<=DATA_ADVANCE;
                    else begin ram_addr<=ram_addr+1'b1; state<=DATA_WAIT; end
                end
                DATA_ADVANCE: begin
                    // Directory size defines EOF; allocation may extend past it.
                    if(remaining==0) state<=FINISH;
                    else if(sector_in_cluster+1<sectors_per_cluster) begin
                        sector_in_cluster<=sector_in_cluster+1'b1;
                        read_sector(cluster_lba+1,DATA_BEGIN);
                    end else state<=FAT_REQ;
                end
                FINISH: begin busy<=0; done<=1; state<=IDLE; end
                default:fail(12);
            endcase
        end
    end
endmodule
