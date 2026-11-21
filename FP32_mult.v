//32位浮点数乘法，
//31位为符号	[30:23]位为指数移码	[22:0]位为尾数 1:8:23

/*
1、符号位，0正1负采用逻辑异或，且计算时不用考虑Float的类型
2、规范化的处理:右归和左归
3、溢出：上溢下溢
4、舍入：就近舍入，偶数方向舍入
5、quiet NAN的类型:0 1111-1111 100-0000-0000-0000-0000-0000
6、结果是非规则化的2的-126时侯，需要对于尾数乘法的移位进行考虑
*/
`timescale 1ns/1ps

module fp32_mult(
clk,
rst,
mult_1,
mult_2,
mult_out,
valid_out
);
input clk;
input rst;

input [31:0] mult_1;
input [31:0] mult_2;

output [31:0] mult_out;
output valid_out;

//always中赋值采用的是reg型变量
reg [31:0] mult_in1;
reg [31:0] mult_in2;
reg mult_in1_zero;
reg mult_in2_zero;
reg mult_in1_infinite;
reg mult_in2_infinite;
reg mult_in1_NaN;
reg mult_in2_NaN;
reg mult_in1_abnormal;
reg mult_in2_abnormal;
//step1、划分mult1和mult2的类型
always@(*)begin
	//0
	if(mult_in1[30:23]==8'b00000000&&mult_in1[22:0]==23'b0)
		mult_in1_zero=1;
	else
		mult_in1_zero=0;
	if(mult_in2[30:23]==8'b00000000&&mult_in2[22:0]==23'b0)
		mult_in2_zero=1;
	else
		mult_in2_zero=0;
	//无穷
	if(mult_in1[30:23]==8'b11111111&&mult_in1[22:0]==23'b0)
		mult_in1_infinite=1;
	else
		mult_in1_infinite=0;
	if(mult_in2[30:23]==8'b11111111&&mult_in2[22:0]==23'b0)
		mult_in2_infinite=1;
	else
		mult_in2_infinite=0;
	//NaN
	if(mult_in1[30:23]==8'b11111111&&mult_in1[22:0]!=23'b0)
		mult_in1_NaN=1;
	else
		mult_in1_NaN=0;
	if(mult_in2[30:23]==8'b11111111&&mult_in2[22:0]!=23'b0)
		mult_in2_NaN=1;
	else
		mult_in2_NaN=0;
	//非规格化数
	if(mult_in1[30:23]==8'b00000000&&mult_in1[22:0]!=23'b0)
		mult_in1_abnormal=1;
	else
		mult_in1_abnormal=0;
	if(mult_in2[30:23]==8'b00000000&&mult_in2[22:0]!=23'b0)
		mult_in2_abnormal=1;
	else
		mult_in2_abnormal=0;
end







//step2、计算暂时的阶码 尾数之后再规则化

//1、计算符号位
wire temp_sign;//暂存符号结果
assign temp_sign=mult_in1[31]^mult_in2[31];


//2、计算阶码
wire signed [9:0] temp_exp;//阶码暂存结果，带符号10位
reg signed [9:0] temp_exp_1;
reg signed [9:0] temp_exp_2;

always@(*)begin
if(mult_in1_abnormal)//非规格化数定位2的-126次方
	temp_exp_1=10'b0000000001;
else
	temp_exp_1=$signed({2'b00,mult_in1[30:23]});
if(mult_in2_abnormal)
	temp_exp_2=10'b0000000001;
else
	temp_exp_2=$signed({2'b00,mult_in2[30:23]});
end
assign temp_exp=temp_exp_1+temp_exp_2-10'sd127;


//3、计算尾数
wire [23:0] temp_f_1;
wire [23:0] temp_f_2;
wire [47:0] temp_f;
assign temp_f_1=mult_in1_abnormal?{1'b0,mult_in1[22:0]}:{1'b1,mult_in1[22:0]};
assign temp_f_2=mult_in2_abnormal?{1'b0,mult_in2[22:0]}:{1'b1,mult_in2[22:0]};
//assign temp_f=(mult_in1_abnormal?{1'b0,mult_in1[22:0]}:{1'b1,mult_in1[22:0]})*(mult_in2_abnormal?{1'b0,mult_in2[22:0]}:{1'b1,mult_in2[22:0]});

reg [47:0] temp_f_1_shift;
reg [23:0] temp_f_2_shift;
reg [47:0] temp_f_acc;
reg [5:0] f_i;

always@(*)begin
	f_i=0;
	temp_f_1_shift={24'b0,temp_f_1};
	temp_f_2_shift=temp_f_2;
	temp_f_acc=48'b0;
	for(f_i=0;f_i<24;f_i=f_i+1)begin
		if(temp_f_2_shift[0])	temp_f_acc=temp_f_acc+temp_f_1_shift;
		temp_f_1_shift=temp_f_1_shift<<1;
		temp_f_2_shift=temp_f_2_shift>>1;
	end
end

assign temp_f=temp_f_acc;


//step3、对数据进行规范化上下溢出、舍入处理
reg signed [9:0] exp;//exp有符号
reg [23:0] f;//24位
reg [47:0] f_normal;//规范化移位后的尾数
reg [24:0] f_reject;//舍入后的数据，25位
reg [5:0] i;
reg [8:0] shift;
reg G;//保，舍，粘
reg R;
reg S;

always@(*) begin
	exp=temp_exp;
	shift=9'b0;
	i=0;
	G=0;
	R=0;
	S=0;
	
	//右归、左归
	f_normal=temp_f;
	if(temp_f[47])begin
		exp=exp+10'sb0000000001;
		f_normal={1'b0,f_normal[47:2],(f_normal[1]|f_normal[0])};
	end
	else begin
		for(i=0;i<46;i=i+1)begin//47和46为01的时候不运行这个if else规则化
			if(f_normal[46]==0&&f_normal!=48'b0)begin
				f_normal=f_normal<<1;
				exp=exp-10'sb0000000001;
			end
		end
	end
	
	
	//规范化处理之后的浮点数是1.xxxxxx * 2^(exp-127)
	
	//溢出
	//1、exp<0时说明下溢出，看看是否在非规则化数的范围中，阶码朝向1移动
	//2、exp=0时说明此时为1.xxx *2^-127次方，改成0.xxxxxx*2-126次方的非规范化数
	//3、255>exp>0说明正常
	//4、exp>=255说明上溢出，定义为无穷
	
	if(exp<10'sb0000000000)begin
		shift=1-exp;//要移动到阶码为1上的距离
		if(shift>=48)begin//表示尾数无法表示
			exp=10'sb0000000000;
			if(f_normal!=48'b0)
			f_normal={47'b0,1'b1};//用于之后判定舍入
			else
			f_normal=48'b0;
		end
		else begin
			exp=10'sb0000000000;
			for(i=0;i<shift;i=i+1)begin
				f_normal={1'b0,f_normal[47:2],(f_normal[1]|f_normal[0])};//右移shift位的非规则化数
			end
		end
	end
	
	else if(exp==10'sb0000000000)begin
		shift=1;
		f_normal={1'b0,f_normal[47:2],(f_normal[1]|f_normal[0])};
	end

	else if(exp>=10'sb0011111111)begin//超出表示范围用无穷表示
		exp=10'sb0011111111;
		f_normal=48'b0;
	end	
	
	//舍入
	//eg:GRS=100看是否满足前一个数为1，为1则进位，即达到1半
	f_reject={1'b0,f_normal[46:23]};
	G=f_normal[22];
	R=f_normal[21];
	if(f_normal[20:0]!=21'b0) S=1;
	
	if(G)begin
		if(S||R) f_reject=f_reject+1;
		else begin
			if(f_normal[23]) f_reject=f_reject+1;//判断是否到达了一半
		end
	end
	
	//舍入后的规格化
	f=f_reject[23:0];
	if(exp!=10'sb0000000000)begin
	//规格化数舍入后产生进位，再次右规格化
		if(f_reject[24])begin
			exp=exp+10'sb0000000001;
			f=f_reject[24:1];
		end	
	end
	else begin
	//非规格化数舍入后达到最小规格化数
		if(f_reject[23])begin
			exp=10'sb0000000001;
			f=f_reject[23:0];
		end
	end
end


//step4、结果处理
reg [31:0] mult_out;
reg valid_mult;//进行乘法
reg valid_out;//还未有结果
reg mult_out_zero;
reg mult_out_infinite;
reg mult_out_NaN;
reg mult_out_abnormal;

always @(posedge clk or negedge rst)begin

	if(~rst)begin
		mult_in1<=0;
		mult_in2<=0;
		mult_out<=0;
		valid_mult<=0;
		valid_out<=0;
		mult_out_zero<=0;
		mult_out_infinite<=0;
		mult_out_NaN<=0;
		mult_out_abnormal<=0;
	end
	
	else begin
		mult_in1<=mult_1;
		mult_in2<=mult_2;
		valid_mult<=1;
		//得出求值结果
		if(valid_mult)begin
			if(mult_in1_NaN||mult_in2_NaN)begin//nan*any=nan
				mult_out[31]<=temp_sign;
				mult_out[30:23]<=8'b11111111;
				mult_out[22:0]<=23'b10000000000000000000000;
			end
			else if((mult_in1_zero&&mult_in2_infinite)||(mult_in2_zero&&mult_in1_infinite))begin//0*无穷=NAN
				mult_out[31]<=1'b0;
				mult_out[30:23]<=8'b11111111;
				mult_out[22:0]<=23'b10000000000000000000000;
			end
			
			else if(mult_in1_zero||mult_in2_zero)begin//0*any=0
				mult_out[31]<=temp_sign;
				mult_out[30:0]<=31'b0;
			end
			else if(mult_in1_infinite||mult_in2_infinite)begin//无穷*非规格化数或规格为无穷
				mult_out[31]<=temp_sign;
				mult_out[30:23]<=8'b11111111;
				mult_out[22:0]<=23'b0;
			end
			else if(exp>=10'sb0011111111)begin
				mult_out[31]<=temp_sign;
				mult_out[30:23]<=8'b11111111;
				mult_out[22:0]<=23'b0;
			end
			else begin
				mult_out[31]<=temp_sign;
				mult_out[30:23]<=exp[7:0];
				mult_out[22:0]<=f[22:0];
			end
		end	
		else begin
			mult_out<=0;
		end
		valid_out<=valid_mult;	
		//判定mult_out的类型
		if(mult_out[30:23]==8'b00000000)begin
			if(mult_out[22:0]==23'b0)begin
				mult_out_zero<=1;
				mult_out_abnormal<=0;
				mult_out_infinite<=0;
				mult_out_NaN<=0;
			end
			else begin
				mult_out_zero<=0;
				mult_out_abnormal<=1;
				mult_out_infinite<=0;
				mult_out_NaN<=0;
			end
		end
		else if(mult_out[30:23]==8'b11111111)begin
			if(mult_out[22:0]==23'b0)begin
				mult_out_zero<=0;
				mult_out_abnormal<=0;
				mult_out_infinite<=1;
				mult_out_NaN<=0;
			end
			else begin
				mult_out_zero<=0;
				mult_out_abnormal<=0;
				mult_out_infinite<=0;
				mult_out_NaN<=1;
			end
		end
		else begin
				mult_out_zero<=0;
				mult_out_abnormal<=0;
				mult_out_infinite<=0;
				mult_out_NaN<=0;
		end
	end
end
endmodule




//testbench
module fp32_mult_tb;
reg clk,rst;
reg [31:0] mult_1;
reg [31:0] mult_2;
wire [31:0] mult_out;
wire valid_out;
reg[9:0] i;
reg [31:0] mult_out_expect;
fp32_mult fp32_mult(
	.clk(clk),
	.rst(rst),
	.mult_1(mult_1),
	.mult_2(mult_2),
	.mult_out(mult_out),
	.valid_out(valid_out)
);

initial begin
	clk<=0;
	rst<=0;
	mult_1<=32'b0_00000000_00000000000000000000000;
	mult_2<=32'b0_00000000_00000000000000000000000;
	mult_out_expect<=32'b0_00000000_00000000000000000000000;
	#17 rst<=1;
	#13
	//+0*+0
	mult_1<=32'b0_00000000_00000000000000000000000;
	mult_2<=32'b0_00000000_00000000000000000000000;
	mult_out_expect<=32'b0_00000000_00000000000000000000000;
	#30
	//+0*1
	mult_1<=32'b0_00000000_00000000000000000000000;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b0_00000000_00000000000000000000000;
	#30
	//-0*1
	mult_1<=32'b1_00000000_00000000000000000000000;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b1_00000000_00000000000000000000000;
	#30
	//正无穷大*(-1.0)
	mult_1<=32'b0_11111111_00000000000000000000000;
	mult_2<=32'b1_01111111_00000000000000000000000;
	mult_out_expect<=32'b1_11111111_00000000000000000000000;
	#30
	//NaN*1.0
	mult_1<=32'b0_11111111_10000000000000000000000;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b0_11111111_10000000000000000000000;
	#30
	//1.0*1.0
	mult_1<=32'b0_01111111_00000000000000000000000;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b0_01111111_00000000000000000000000;
	#30
	//(-1.0)*2.0
	mult_1<=32'b1_01111111_00000000000000000000000;
	mult_2<=32'b0_10000000_00000000000000000000000;
	mult_out_expect<=32'b1_10000000_00000000000000000000000;
	#30
	//1.5*1.5右规
	mult_1<=32'b0_01111111_10000000000000000000000;
	mult_2<=32'b0_01111111_10000000000000000000000;
	mult_out_expect<=32'b0_10000000_00100000000000000000000;
	#30
	//最大正数*1.0是否误判
	mult_1<=32'b0_11111110_11111111111111111111111;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b0_11111110_11111111111111111111111;
	#30
	//最大正数*2.0上溢
	mult_1<=32'b0_11111110_11111111111111111111111;
	mult_2<=32'b0_10000000_00000000000000000000000;
	mult_out_expect<=32'b0_11111111_00000000000000000000000;
	#30
	//最小规格化数*1.0
	mult_1<=32'b0_00000001_00000000000000000000000;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b0_00000001_00000000000000000000000;
	#30
	//最小规格化数*0.5规格化数转成非规格化数,下溢
	mult_1<=32'b0_00000001_00000000000000000000000;
	mult_2<=32'b0_01111110_00000000000000000000000;
	mult_out_expect<=32'b0_00000000_10000000000000000000000;
	#30
	//最大非规格化数*1.0
	mult_1<=32'b0_00000000_11111111111111111111111;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b0_00000000_11111111111111111111111;
	#30
	//最大非规格化数*(1+2^-23)*2^0舍入后由非规格化数变成最小规格化数
	mult_1<=32'b0_00000000_11111111111111111111111;
	mult_2<=32'b0_01111111_00000000000000000000001;
	mult_out_expect<=32'b0_00000001_00000000000000000000000;
	#30
	//最小非规格化数*1.0
	mult_1<=32'b0_00000000_00000000000000000000001;
	mult_2<=32'b0_01111111_00000000000000000000000;
	mult_out_expect<=32'b0_00000000_00000000000000000000001;
	#30
	//最小非规格化数*0.5 偶数而不进位
	mult_1<=32'b0_00000000_00000000000000000000001;
	mult_2<=32'b0_01111110_00000000000000000000000;
	mult_out_expect<=32'b0_00000000_00000000000000000000000;
	#30
	//最小非规格化数*1.5 取偶数并进位
	mult_1<=32'b0_00000000_00000000000000000000001;
	mult_2<=32'b0_01111111_10000000000000000000000;
	mult_out_expect<=32'b0_00000000_00000000000000000000010;
	#30
	//最小非规格化数*最小非规格化数，极小结果舍入为正零，shift>=48
	mult_1<=32'b0_00000000_00000000000000000000001;
	mult_2<=32'b0_00000000_00000000000000000000001;
	mult_out_expect<=32'b0_00000000_00000000000000000000000;
	#30
	//2.0*3.0
	mult_1<=32'b0_10000000_00000000000000000000000;
	mult_2<=32'b0_10000000_10000000000000000000000;
	mult_out_expect<=32'b0_10000001_10000000000000000000000;
	#30
	//3.5*2.0
	mult_1<=32'b0_10000000_11000000000000000000000;
	mult_2<=32'b0_10000000_00000000000000000000000;
	mult_out_expect<=32'b0_10000001_11000000000000000000000;
	#30
	//1.25*2.5
	mult_1<=32'b0_01111111_01000000000000000000000;
	mult_2<=32'b0_10000000_01000000000000000000000;
	mult_out_expect<=32'b0_10000000_10010000000000000000000;
	#30
	//(-2.5)*4.0
	mult_1<=32'b1_10000000_01000000000000000000000;
	mult_2<=32'b0_10000001_00000000000000000000000;
	mult_out_expect<=32'b1_10000010_01000000000000000000000;
	#30
	//(-3.0)*(-2.5)
	mult_1<=32'b1_10000000_10000000000000000000000;
	mult_2<=32'b1_10000000_01000000000000000000000;
	mult_out_expect<=32'b0_10000001_11100000000000000000000;
	#30
	//0.75*0.5
	mult_1<=32'b0_01111110_10000000000000000000000;
	mult_2<=32'b0_01111110_00000000000000000000000;
	mult_out_expect<=32'b0_01111101_10000000000000000000000;
	#30
	//10.0*1.5
	mult_1<=32'b0_10000010_01000000000000000000000;
	mult_2<=32'b0_01111111_10000000000000000000000;
	mult_out_expect<=32'b0_10000010_11100000000000000000000;
	#30
	//6.25*1.5
	mult_1<=32'b0_10000001_10010000000000000000000;
	mult_2<=32'b0_01111111_10000000000000000000000;
	mult_out_expect<=32'b0_10000010_00101100000000000000000;
	#30
	//2.25*3.5
	mult_1<=32'b0_10000000_00100000000000000000000;
	mult_2<=32'b0_10000000_11000000000000000000000;
	mult_out_expect<=32'b0_10000001_11111000000000000000000;
	#30
	//(-1.75)*0.25
	mult_1<=32'b1_01111111_11000000000000000000000;
	mult_2<=32'b0_01111101_00000000000000000000000;
	mult_out_expect<=32'b1_01111101_11000000000000000000000;
	#30
	//12.5*0.125
	mult_1<=32'b0_10000010_10010000000000000000000;
	mult_2<=32'b0_01111100_00000000000000000000000;
	mult_out_expect<=32'b0_01111111_10010000000000000000000;
	//随机数*随机数
	for(i=0;i<1000;i=i+1)begin
		#30
		mult_1<=$random;
		mult_2<=$random;
		mult_out_expect<=32'b0;
	end
	#30 $stop;
end

always #5 clk<=~clk;

endmodule