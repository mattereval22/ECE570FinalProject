module rgb_bicubic
#(
    parameter C_SRC_IMG_WIDTH  = 12'd640,
    parameter C_SRC_IMG_HEIGHT = 12'd480
)
(
    input  wire                 clk_in1,
    input  wire                 clk_in2,
    input  wire                 rst_n,
    input  wire        [1:0]     out_model,
    
    //  输入图像数据
    input  wire                     per_img_vsync,
    input  wire                     per_img_href,
    input  wire     [ 7:0]          per_img_red,
    input  wire     [ 7:0]          per_img_green,
    input  wire     [ 7:0]          per_img_blue,
    input  wire     [11:0]          c_dst_img_width,     
    input  wire     [11:0]          c_dst_img_height,  
    input  wire     [ 8:0]          bi_a,
    
    //  输出图像数据
    output reg                  post_img_vsync,
    output reg                  post_img_href,
    output reg      [31:0]      post_img_data // 32位输出
);

// 内部信号
wire [7:0] post_red, post_green, post_blue;
wire red_vsync, red_href, green_vsync, green_href, blue_vsync, blue_href;

wire [16:0]  x_fra_c1,y_fra_c1,inv_x_fra_c1,inv_y_fra_c1;
wire [16:0]  bi_y0,bi_y1,bi_y2,bi_y3,bi_x0,bi_x1,bi_x2,bi_x3;

reg [33:0]    frac_00_c2, frac_01_c2, frac_10_c2, frac_11_c2;
reg [33:0] coeff00_c11, coeff01_c11, coeff02_c11, coeff03_c11;//(34,32)
reg [33:0] coeff10_c11, coeff11_c11, coeff12_c11, coeff13_c11;
reg [33:0] coeff20_c11, coeff21_c11, coeff22_c11, coeff23_c11;
reg [33:0] coeff30_c11, coeff31_c11, coeff32_c11, coeff33_c11;

reg         [16:0]              C_X_RATIO;
reg         [16:0]              C_Y_RATIO;
reg         [11:0]              C_DST_IMG_WIDTH;
reg         [11:0]              C_DST_IMG_HEIGHT;

// 实例化三个双线性插值模块
bicubic_interpolation #(
    .C_SRC_IMG_WIDTH(C_SRC_IMG_WIDTH),
    .C_SRC_IMG_HEIGHT(C_SRC_IMG_HEIGHT)
) red_interp (
    .clk_in1(clk_in1),
    .clk_in2(clk_in2),
    .rst_n(rst_n),
    .out_model(out_model),
    .per_img_vsync(per_img_vsync),
    .per_img_href(per_img_href),
    .per_img_gray(per_img_red),
    .post_img_vsync(red_vsync),
    .post_img_href(red_href),
    .post_img_gray(post_red),
    .C_X_RATIO(C_X_RATIO),
    .C_Y_RATIO(C_Y_RATIO),
    .C_DST_IMG_HEIGHT(C_DST_IMG_HEIGHT),
    .C_DST_IMG_WIDTH(C_DST_IMG_WIDTH),

    .coeff00_c11(coeff00_c11),
    .coeff01_c11(coeff01_c11),
    .coeff02_c11(coeff02_c11),
    .coeff03_c11(coeff03_c11),
    .coeff10_c11(coeff10_c11),
    .coeff11_c11(coeff11_c11),
    .coeff12_c11(coeff12_c11),
    .coeff13_c11(coeff13_c11),
    .coeff20_c11(coeff20_c11),
    .coeff21_c11(coeff21_c11),
    .coeff22_c11(coeff22_c11),
    .coeff23_c11(coeff23_c11),
    .coeff30_c11(coeff30_c11),
    .coeff31_c11(coeff31_c11),
    .coeff32_c11(coeff32_c11),
    .coeff33_c11(coeff33_c11),

    .frac_00_c2(frac_00_c2),
    .frac_01_c2(frac_01_c2),
    .frac_10_c2(frac_10_c2),
    .frac_11_c2(frac_11_c2),
    .x_fra_c1(x_fra_c1),
    .y_fra_c1(y_fra_c1),
    .inv_x_fra_c1(inv_x_fra_c1),
    .inv_y_fra_c1(inv_y_fra_c1)
);

bicubic_interpolation #(
    .C_SRC_IMG_WIDTH(C_SRC_IMG_WIDTH),
    .C_SRC_IMG_HEIGHT(C_SRC_IMG_HEIGHT)
) green_interp (
    .clk_in1(clk_in1),
    .clk_in2(clk_in2),
    .rst_n(rst_n),
    .out_model(out_model),
    .per_img_vsync(per_img_vsync),
    .per_img_href(per_img_href),
    .per_img_gray(per_img_green),
    .post_img_vsync(green_vsync),
    .post_img_href(green_href),
    .post_img_gray(post_green),
    .C_X_RATIO(C_X_RATIO),
    .C_Y_RATIO(C_Y_RATIO),
    .C_DST_IMG_HEIGHT(C_DST_IMG_HEIGHT),
    .C_DST_IMG_WIDTH(C_DST_IMG_WIDTH),

    .coeff00_c11(coeff00_c11),
    .coeff01_c11(coeff01_c11),
    .coeff02_c11(coeff02_c11),
    .coeff03_c11(coeff03_c11),
    .coeff10_c11(coeff10_c11),
    .coeff11_c11(coeff11_c11),
    .coeff12_c11(coeff12_c11),
    .coeff13_c11(coeff13_c11),
    .coeff20_c11(coeff20_c11),
    .coeff21_c11(coeff21_c11),
    .coeff22_c11(coeff22_c11),
    .coeff23_c11(coeff23_c11),
    .coeff30_c11(coeff30_c11),
    .coeff31_c11(coeff31_c11),
    .coeff32_c11(coeff32_c11),
    .coeff33_c11(coeff33_c11),
    
    .frac_00_c2(frac_00_c2),
    .frac_01_c2(frac_01_c2),
    .frac_10_c2(frac_10_c2),
    .frac_11_c2(frac_11_c2),
    .x_fra_c1(),
    .y_fra_c1(),
    .inv_x_fra_c1(),
    .inv_y_fra_c1()
);

bicubic_interpolation #(
    .C_SRC_IMG_WIDTH(C_SRC_IMG_WIDTH),
    .C_SRC_IMG_HEIGHT(C_SRC_IMG_HEIGHT)
) blue_interp (
    .clk_in1(clk_in1),
    .clk_in2(clk_in2),
    .rst_n(rst_n),
    .out_model(out_model),
    .per_img_vsync(per_img_vsync),
    .per_img_href(per_img_href),
    .per_img_gray(per_img_blue),
    .post_img_vsync(blue_vsync),
    .post_img_href(blue_href),
    .post_img_gray(post_blue),
    .C_X_RATIO(C_X_RATIO),
    .C_Y_RATIO(C_Y_RATIO),
    .C_DST_IMG_HEIGHT(C_DST_IMG_HEIGHT),
    .C_DST_IMG_WIDTH(C_DST_IMG_WIDTH),

    .coeff00_c11(coeff00_c11),
    .coeff01_c11(coeff01_c11),
    .coeff02_c11(coeff02_c11),
    .coeff03_c11(coeff03_c11),
    .coeff10_c11(coeff10_c11),
    .coeff11_c11(coeff11_c11),
    .coeff12_c11(coeff12_c11),
    .coeff13_c11(coeff13_c11),
    .coeff20_c11(coeff20_c11),
    .coeff21_c11(coeff21_c11),
    .coeff22_c11(coeff22_c11),
    .coeff23_c11(coeff23_c11),
    .coeff30_c11(coeff30_c11),
    .coeff31_c11(coeff31_c11),
    .coeff32_c11(coeff32_c11),
    .coeff33_c11(coeff33_c11),

    .frac_00_c2(frac_00_c2),
    .frac_01_c2(frac_01_c2),
    .frac_10_c2(frac_10_c2),
    .frac_11_c2(frac_11_c2),
    .x_fra_c1(),
    .y_fra_c1(),
    .inv_x_fra_c1(),
    .inv_y_fra_c1()
);

// 合并输出
always @(posedge clk_in2) begin
    if (rst_n==0) begin
        post_img_vsync <= 0;
        post_img_href <= 0;
        post_img_data <= 32'h0;
    end else begin
        // 确保行场信号同步
        post_img_vsync <= red_vsync ;
        post_img_href <= red_href ;

        // 输出数据
        post_img_data <= {8'h0, post_red, post_green, post_blue};
    end
end


//----------------------caulacute  parameters in 7 pai--------begin in 2 get in 8-----------

localparam COFFEEONE = { 1'b1, {8{1'b0}}};
localparam COFFEEHALF ={2'b01, {7{1'b0}}}; //uesless

BiCubic u_BiCubic (
	.clk       (clk_in2),
	.rst_n     (rst_n),
	.coeffOne  (COFFEEONE),
	.coeffHalf (COFFEEHALF),
	.yBlend    (y_fra_c1[16:8]),
	.bi_a      (bi_a),
	.xBlend    (x_fra_c1[16:8]),
	.bi_y0     (bi_y0),
	.bi_y1     (bi_y1),
	.bi_y2     (bi_y2),
	.bi_y3     (bi_y3),
	.bi_x0     (bi_x0),
	.bi_x1     (bi_x1),
	.bi_x2     (bi_x2),
	.bi_x3     (bi_x3)
);

//------------------------------------------------------
//c8
reg [16:0] bi_y0_c10, bi_y1_c10, bi_y2_c10, bi_y3_c10, bi_x0_c10, bi_x1_c10, bi_x2_c10, bi_x3_c10;

always  @(posedge clk_in2)
begin
    bi_y0_c10 <= bi_y0;
    bi_y1_c10 <= bi_y1;
    bi_y2_c10 <= bi_y2;
    bi_y3_c10 <= bi_y3;
    bi_x0_c10 <= bi_x0;
    bi_x1_c10 <= bi_x1;
    bi_x2_c10 <= bi_x2;
    bi_x3_c10 <= bi_x3;
end

//------------------------------------------------------
//c9

always @(posedge clk_in2)
begin
    coeff00_c11 <=bi_y0_c10 *bi_x0_c10;
    coeff01_c11 <=bi_y0_c10 *bi_x1_c10;
    coeff02_c11 <=bi_y0_c10 *bi_x2_c10;
    coeff03_c11 <=bi_y0_c10 *bi_x3_c10;

    coeff10_c11 <=bi_y1_c10 *bi_x0_c10;
    coeff11_c11 <=bi_y1_c10 *bi_x1_c10;
    coeff12_c11 <=bi_y1_c10 *bi_x2_c10;
    coeff13_c11 <=bi_y1_c10 *bi_x3_c10;

    coeff20_c11 <=bi_y2_c10 *bi_x0_c10;
    coeff21_c11 <=bi_y2_c10 *bi_x1_c10;
    coeff22_c11 <=bi_y2_c10 *bi_x2_c10;
    coeff23_c11 <=bi_y2_c10 *bi_x3_c10;

    coeff30_c11 <=bi_y3_c10 *bi_x0_c10;
    coeff31_c11 <=bi_y3_c10 *bi_x1_c10;
    coeff32_c11 <=bi_y3_c10 *bi_x2_c10;
    coeff33_c11 <=bi_y3_c10 *bi_x3_c10;
end


always @(posedge clk_in2) begin
    frac_00_c2   <= inv_x_fra_c1 * inv_y_fra_c1;
    frac_01_c2   <= x_fra_c1 * inv_y_fra_c1;
    frac_10_c2   <= inv_x_fra_c1 * y_fra_c1;
    frac_11_c2   <= x_fra_c1 * y_fra_c1;
end


//--------------------------------begin divider my own--------------------------------------

reg                             post_img_vsync_dly;
wire                            post_img_vsync_neg;
always @(posedge clk_in2)
begin
    if(rst_n == 1'b0)
        post_img_vsync_dly <= 1'b0;
    else
        post_img_vsync_dly <= red_vsync;
end
assign post_img_vsync_neg = post_img_vsync_dly & ~red_vsync;




// c1-----

reg                             post_img_vsync_neg_c1;
always@(posedge clk_in2)
begin
    if(rst_n == 1'b0)begin
        post_img_vsync_neg_c1 =0;
    end
    else begin
        post_img_vsync_neg_c1 <=post_img_vsync_neg;
    end
end

//c1.5
reg                             post_img_vsync_neg_c1_5;
always@(posedge clk_in2)
begin
    if(rst_n == 1'b0)begin
        post_img_vsync_neg_c1_5 =0;
    end
    else begin
        post_img_vsync_neg_c1_5 <=post_img_vsync_neg_c1;
    end
end


// c2-----

reg                             post_img_vsync_neg_c2;
always@(posedge clk_in2)
begin
    if(rst_n == 1'b0)begin
        C_DST_IMG_WIDTH  <= 640;
        C_DST_IMG_HEIGHT <= 480;
    end
    else begin
        if(post_img_vsync_neg_c1_5 == 1) 
        begin
            C_DST_IMG_WIDTH  <= c_dst_img_width;
            C_DST_IMG_HEIGHT <= c_dst_img_height;
            post_img_vsync_neg_c2 <= 1;
        end
        else
        begin
            C_DST_IMG_WIDTH  <= C_DST_IMG_WIDTH;
            C_DST_IMG_HEIGHT <= C_DST_IMG_HEIGHT;
            post_img_vsync_neg_c2 <= 0;
        end
    end
end


//c3-----
reg             [26:0]          multi_tmp1_c2;
reg             [26:0]          multi_tmp2_c2;
reg                             post_img_vsync_neg_c3;

always@(posedge clk_in2)
begin
    if(rst_n == 1'b0)begin
        multi_tmp1_c2  <= 0;
        multi_tmp2_c2  <= 0;
    end
    else begin
        if(post_img_vsync_neg_c2 ==1) begin
            multi_tmp1_c2 <=(C_SRC_IMG_WIDTH <<16) ;// C_DST_IMG_WIDTH ;//  floor(C_SRC_IMG_WIDTH/C_DST_IMG_WIDTH*2^16)
            multi_tmp2_c2 <=(C_SRC_IMG_HEIGHT <<16) ;// C_DST_IMG_HEIGHT ;//  floor(C_SRC_IMG_HEIGHT/C_DST_IMG_HEIGHT*2^16)
            post_img_vsync_neg_c3 <=1;
        end
        else begin
            multi_tmp1_c2 <=multi_tmp1_c2;
            multi_tmp2_c2 <=multi_tmp2_c2;
            post_img_vsync_neg_c3 <=0;
        end
    end
end

//c4-------

reg    divide_clken;
wire    rfd;
wire    rfd1;
wire   [26:0]   c_x_ratio_divide;
wire   [26:0]   c_y_ratio_divide;
always@(posedge clk_in2)
begin
    if(rst_n == 1'b0)begin
        divide_clken  <= 0; 
    end
    else begin
        if(post_img_vsync_neg_c3 ==1 && rfd ==0) begin
            divide_clken <= 1;
        end
        else if(post_img_vsync_neg_c3 ==0 && rfd ==1) begin
            divide_clken <= 0;
        end else
            divide_clken <= divide_clken;
    end
end

divider_ip ux_divider_ip(  
    .numer(multi_tmp1_c2), //  floor(C_SRC_IMG_WIDTH/C_DST_IMG_WIDTH*2^16)
    .denom(C_DST_IMG_WIDTH),
    .clken(divide_clken),
    .clk(clk_in2),
    .reset(1'b0),
    .quotient(c_x_ratio_divide),
    .remain(),
    .rfd(rfd1)

);
divider_ip uy_divider_ip(
    .numer(multi_tmp2_c2),
    .denom(C_DST_IMG_HEIGHT),
    .clken(divide_clken),
    .clk(clk_in2),
    .reset(1'b0),
    .quotient(c_y_ratio_divide),
    .remain(),
    .rfd(rfd)

);
always@(posedge clk_in2)
begin
    if(rst_n == 1'b0)begin
        C_X_RATIO  <= 65536; 
        C_Y_RATIO  <= 65536; 
    end
    else begin
        if (rfd ==1) begin
            C_X_RATIO  <= c_x_ratio_divide; 
            C_Y_RATIO  <= c_y_ratio_divide; 
        end else begin
            C_X_RATIO  <= C_X_RATIO; 
            C_Y_RATIO  <= C_Y_RATIO; 
        end
    end
end


//---------------------------end divider my own---------------------------------------------------

endmodule
