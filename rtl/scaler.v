module scaler #(
    parameter integer MAXW = 1024      // max source width (line RAM depth), must be a power of two
) (
    input  wire        clk, rst_n,
    input  wire        start,                 // 1-cycle pulse at the beginning of a load
    // from bmp24
    input  wire        hdr_valid,
    input  wire [11:0] src_w, src_h,
    input  wire        px_valid,
    input  wire [23:0] px_data,
    output wire        in_ready,              // AND this into fat32.byte_ready
    // to frame (pixel clock domain)
    input  wire        write_ready,
    output wire        wr_valid,
    output wire [18:0] wr_addr,
    output wire [23:0] wr_data,
    output reg         busy, done,            // done: 1-cycle pulse, all 307200 pixels queued
    output reg         overrun                // sticky: pixel arrived while input was stalled
);
    localparam integer AW = $clog2(MAXW);
    localparam [3:0]
        S_IDLE=0, S_DIM=1, S_DIVX=2, S_DIVXW=3, S_OFF=4, S_INIT=5, S_INIT2=6,
        S_ROW=7, S_WAITROW=8, S_PIX=9, S_RD1=10, S_MAC=11, S_OUT=12, S_WRITE=13, S_DONE=14;

    reg [3:0]  state;
    reg [11:0] sw, sh;
    reg        wide_r;
    reg [31:0] step, pos_x, pos_y, x_off, y_off;
    reg [9:0]  X, Y;
    reg [18:0] row_base;
    reg [11:0] rows_cnt, wr_x, b_target, need_b, xi0_r;
    reg        allow_all, run_en;
    reg [AW-1:0] rd_addr;
    reg [39:0] wxp, wyp;        // 4 signed 10-bit weights each, tap k at [10k +: 10]
    reg [7:0]  bufs;            // line RAM number of vertical tap k at [2k +: 2]
    reg [1:0]  j;               // horizontal tap (column) 0..3
    reg [2:0]  m;               // 0..3 vertical MACs, 4 horizontal MAC
    reg [23:0] out_r;

    wire [11:0] swm1 = sw - 12'd1;
    wire [11:0] shm1 = sh - 12'd1;
    wire header_ok=src_w!=0 && src_h!=0 && src_w<=MAXW && src_h<=2048 &&
                   ({2'd0,src_w}*14'd3)=={src_h,2'b00};

    // ------------------------------------------------------------ divider
    reg         div_start;
    reg  [31:0] div_num;
    reg  [15:0] div_den;
    wire        div_done;
    wire [31:0] div_quo;
    scl_div divider (.clk(clk), .rst_n(rst_n), .start(div_start), .num(div_num),
                     .den(div_den), .done(div_done), .quo(div_quo));

    // ------------------------------------------------------------ 2 line RAMs (ping-pong by source-row parity)
    wire [47:0] qbus;
    wire stall_row;
    genvar g;
    generate
        for (g = 0; g < 2; g = g + 1) begin : lbk
            reg [23:0] mem [0:MAXW-1];
            reg [23:0] q;
            always @(posedge clk) begin
                if (px_valid && run_en && !stall_row && rows_cnt<sh && rows_cnt[0] == g)
                    mem[wr_x[AW-1:0]] <= px_data;
                q <= mem[rd_addr];
            end
            assign qbus[24*g +: 24] = q;
        end
    endgenerate

    // ------------------------------------------------------------ input flow control
    assign stall_row = !allow_all && (rows_cnt > b_target) && (rows_cnt < sh);
    assign in_ready = (state == S_IDLE) ? !hdr_valid :
                      (state == S_DONE) ? 1'b1 : (run_en && !stall_row);

    // ------------------------------------------------------------ geometry helpers
    wire [13:0] w3 = {sw, 1'b0} + sw;               // sw*3
    wire [13:0] h4 = {sh, 2'b0};                    // sh*4   (sw*480 >= sh*640  <=>  3*sw >= 4*sh)
    wire        wide = (w3 >= h4);                  // wider than 4:3 -> height limits the scale

    // 479*step = 512*step - 32*step - step   (row 479 is the first one produced)
    wire [31:0] step479   = (step << 9) - (step << 5) - step;
    wire [31:0] ypos_init = step479 + {1'b0, step[31:1]} - 32'd32768 + y_off;

    // vertical map for the current output row (from pos_y)
    wire [31:0] py_c    = pos_y[31] ? 32'd0 : pos_y;
    wire [12:0] y_i0    = py_c[28:16];
    wire        y_clamp = (y_i0 >= {1'b0, shm1});
    wire [11:0] y0_c    = y_clamp ? shm1 : y_i0[11:0];
    wire [7:0]  fy_c    = y_clamp ? 8'd0 : py_c[15:8];
    wire [11:0] y_m1    = (y0_c == 12'd0) ? 12'd0 : (y0_c - 12'd1);
    wire [11:0] y_p1    = (y0_c >= shm1) ? y0_c : (y0_c + 12'd1);
    wire [11:0] y_p2    = ((y0_c + 12'd2) > shm1) ? shm1 : (y0_c + 12'd2);
    wire [11:0] bmax_c  = shm1 - y0_c;              // latest file row needed by the two active taps
    // Effective bilinear vertical taps are m=1 (y0) and m=2 (y0+1).
    // File-row index is (source_height-1-y), and only its parity is needed.
    wire [11:0] file_y0 = shm1 - y0_c;
    wire [11:0] file_y1 = shm1 - y_p1;
    wire [7:0]  bufs_c  = {2'b00, 1'b0, file_y1[0], 1'b0, file_y0[0], 2'b00};

    // horizontal map for the current output pixel (from pos_x)
    wire [31:0] px_c    = pos_x[31] ? 32'd0 : pos_x;
    wire [12:0] x_i0    = px_c[28:16];
    wire        x_clamp = (x_i0 >= {1'b0, swm1});
    wire [11:0] xi0_c   = x_clamp ? swm1 : x_i0[11:0];
    wire [7:0]  fx_c    = x_clamp ? 8'd0 : px_c[15:8];

    // column address of horizontal tap jj: clamp(i0 + jj - 1, 0, sw-1)
    function [AW-1:0] col_addr;
        input [11:0] i0;
        input [1:0]  jj;
        input [11:0] lim;
        reg   [12:0] t;
        begin
            t = {1'b0, i0} + {11'd0, jj};
            if (t == 13'd0) col_addr = {AW{1'b0}};
            else begin
                t = t - 13'd1;
                col_addr = (t > {1'b0, lim}) ? lim[AW-1:0] : t[AW-1:0];
            end
        end
    endfunction

    // ------------------------------------------------------------ kernel ROM (shared)
    wire [7:0]  kf = (state == S_PIX) ? fx_c : fy_c;
    wire [39:0] kern_p;
    scl_kernel kernel (.f(kf), .p(kern_p));

    // ------------------------------------------------------------ MAC datapath: 1 multiplier / channel
    wire [1:0]  tap_buf = bufs[{m[1:0], 1'b0} +: 2];
    wire [23:0] qsel    = tap_buf[0] ? qbus[47:24] : qbus[23:0];
    wire signed [9:0] wy_sel = $signed(wyp[{m[1:0], 3'b0} + {m[1:0], 1'b0} +: 10]);   // 10*m
    wire signed [9:0] wx_sel = $signed(wxp[{j, 3'b0} + {j, 1'b0} +: 10]);             // 10*j
    wire is_h = (m == 3'd4);
    wire [23:0] res_bus;
    generate
        for (g = 0; g < 3; g = g + 1) begin : ch
            reg signed [17:0] accv;
            reg signed [27:0] acch;
            wire signed [17:0] a_op = is_h ? accv : $signed({10'd0, qsel[8*g +: 8]});
            wire signed [9:0]  b_op = is_h ? wx_sel : wy_sel;
            wire signed [27:0] prod = a_op * b_op;
            wire signed [27:0] rnd  = acch + 28'sd32768;
            wire [7:0] res8 = rnd[27] ? 8'd0 : (rnd[26:24] != 3'd0) ? 8'd255 : rnd[23:16];
            always @(posedge clk) begin
                if (state == S_MAC) begin
                    if (!is_h) accv <= ((m == 3'd0) ? 18'sd0 : accv) + prod[17:0];
                    else       acch <= ((j == 2'd0) ? 28'sd0 : acch) + prod;
                end
            end
            assign res_bus[8*g +: 8] = res8;
        end
    endgenerate

    // ------------------------------------------------------------ output
    assign wr_valid = (state == S_WRITE) && write_ready;
    assign wr_addr  = row_base + {9'd0, X};
    assign wr_data  = out_r;

    // ------------------------------------------------------------ main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; sw <= 0; sh <= 0; wide_r <= 0;
            step <= 0; pos_x <= 0; pos_y <= 0; x_off <= 0; y_off <= 0;
            X <= 0; Y <= 0; row_base <= 0; rows_cnt <= 0; wr_x <= 0;
            b_target <= 0; need_b <= 0; xi0_r <= 0; allow_all <= 0; run_en <= 0;
            rd_addr <= 0; wxp <= 0; wyp <= 0; bufs <= 0; j <= 0; m <= 0; out_r <= 0;
            div_start <= 0; div_num <= 0; div_den <= 1;
            busy <= 0; done <= 0; overrun <= 0;
        end else begin
            done <= 0; div_start <= 0;

            // ---- input side (line RAM writes happen in the RAM blocks above)
            if (px_valid) begin
                if (!in_ready || !run_en || rows_cnt>=sh) overrun <= 1;
                else if (wr_x == swm1) begin
                    wr_x <= 0; rows_cnt <= rows_cnt + 1'b1;
                end else wr_x <= wr_x + 1'b1;
            end

            // ---- control
            if (start) begin
                state <= S_IDLE; busy <= 1; rows_cnt <= 0; wr_x <= 0;
                allow_all <= 0; run_en <= 0; overrun <= 0; X <= 0;
            end else case (state)
                S_IDLE: if (hdr_valid) begin
                    if(!header_ok)begin overrun<=1;busy<=0;state<=S_DONE;end
                    else begin sw <= src_w; sh <= src_h;state <= S_DIM;end
                end
                S_DIM: begin
                    wide_r <= wide;                    // which axis limits the scale
                    state <= S_DIVX;
                end
                S_DIVX: begin                          // one uniform step: limiting axis / its output size
                    div_num <= {4'd0, (wide_r ? sh : sw), 16'd0};
                    div_den <= wide_r ? 16'd480 : 16'd640;
                    div_start <= 1; state <= S_DIVXW;
                end
                S_DIVXW: if (div_done) begin
                    step <= div_quo; state <= S_OFF;
                end
                S_OFF: begin                            // exact 4:3: full source, no crop/no offset
                    x_off <= 0;
                    y_off <= 0;
                    state <= S_INIT;
                end
                S_INIT: begin
                    pos_y <= ypos_init; Y <= 10'd479; X <= 0;
                    row_base <= 19'd306560;            // 479*640
                    state <= S_INIT2;
                end
                S_INIT2: begin
                    b_target <= bmax_c; run_en <= 1;   // input may now start
                    state <= S_ROW;
                end
                S_ROW: begin
                    pos_x <= {1'b0, step[31:1]} - 32'd32768 + x_off;
                    need_b <= bmax_c; b_target <= bmax_c;
                    bufs <= bufs_c; wyp <= kern_p;
                    state <= S_WAITROW;
                end
                S_WAITROW: if (rows_cnt > need_b) state <= S_PIX;
                S_PIX: begin
                    rd_addr <= col_addr(xi0_c, 2'd0, swm1);
                    xi0_r <= xi0_c; wxp <= kern_p;
                    j <= 2'd0; m <= 3'd0;
                    state <= S_RD1;
                end
                S_RD1: state <= S_MAC;                 // line RAM output settles
                S_MAC: begin
                    // next column's address is issued at m==2: its data appears at m==4, while
                    // the last vertical MAC (m==3) still sees the old data.
                    if (m == 3'd2 && j != 2'd3) rd_addr <= col_addr(xi0_r, j + 2'd1, swm1);
                    if (m == 3'd4) begin
                        m <= 3'd0;
                        if (j == 2'd3) state <= S_OUT;
                        else j <= j + 2'd1;
                    end else m <= m + 3'd1;
                end
                S_OUT: begin out_r <= res_bus; state <= S_WRITE; end
                S_WRITE: if (write_ready) begin
                    pos_x <= pos_x + step;
                    if (X == 10'd639) begin
                        X <= 0;
                        pos_y <= pos_y - step;
                        if (Y == 10'd0) begin
                            allow_all <= 1; busy <= 0; done <= 1; state <= S_DONE;
                        end else begin
                            Y <= Y - 1'b1; row_base <= row_base - 19'd640; state <= S_ROW;
                        end
                    end else begin
                        X <= X + 1'b1; state <= S_PIX;
                    end
                end
                S_DONE: begin end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

// Sequential restoring divider: quo = num / den (den >= 1), 32 cycles.
module scl_div (
    input  wire        clk, rst_n, start,
    input  wire [31:0] num,
    input  wire [15:0] den,
    output reg         done,
    output wire [31:0] quo
);
    reg [31:0] q, nn;
    reg [16:0] r;
    reg [5:0]  cnt;
    reg        busy;
    wire [16:0] r_sh = {r[15:0], nn[31]};
    wire        ge   = (r_sh >= {1'b0, den});
    assign quo = q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= 0; nn <= 0; r <= 0; cnt <= 0; busy <= 0; done <= 0;
        end else begin
            done <= 0;
            if (start) begin
                q <= 0; r <= 0; nn <= num; cnt <= 6'd32; busy <= 1;
            end else if (busy) begin
                r  <= ge ? (r_sh - {1'b0, den}) : r_sh;
                q  <= {q[30:0], ge};
                nn <= {nn[30:0], 1'b0};
                cnt <= cnt - 1'b1;
                if (cnt == 6'd1) begin busy <= 0; done <= 1; end
            end
        end
    end
endmodule

// Bilinear coefficients, Q8. Packed as {w3,w2,w1,w0}; only taps 1 and 2 are active.
// w1=256-f, w2=f. This replaces the 256x40-bit bicubic coefficient ROM.
module scl_kernel (input wire [7:0] f, output wire [39:0] p);
    wire [9:0] w0 = 10'd0;
    wire [9:0] w1 = 10'd256 - {2'b00, f};
    wire [9:0] w2 = {2'b00, f};
    wire [9:0] w3 = 10'd0;
    assign p = {w3,w2,w1,w0};
endmodule
