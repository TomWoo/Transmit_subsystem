`timescale 1ns/10ps
`define CLK_PHY 40
`define CLK_SYS 20

module testbench_short_lo;

// signals
reg clk_sys, clk_phy, rst;
integer i, j, num_packets, packet_length, priority;

initial begin
	// parameters
	packet_length = 64; // also modify packet length in control block!!!
	num_packets = 64;
	priority = 0;

	clk_sys = 1'b1;
	clk_phy = 1'b1;
	rst = 1'b1;
	#(6*`CLK_SYS);
	rst = 1'b0;
end

always begin
	clk_sys <= !clk_sys;
	#(`CLK_SYS/2);
end

always begin
	clk_phy = !clk_phy;
	#(`CLK_PHY/2);
end

// Input signals
reg [ 7:0] 	data_in;
reg [23:0] 	ctrl_block_in;
reg 		data_valid;
reg			ctrl_block_valid;
reg			hi_priority_en;

// Output signals
wire [3:0] 	frame_seq_out;
wire		phy_tx_out;
wire		discard_en;

// UUT
xmitTop topLevel(
	.f_hi_priority(hi_priority_en),
	.f_rec_data_valid(data_valid),
	.f_rec_frame_valid(ctrl_block_valid),
	.f_data_in(data_in),
	.f_ctrl_in(ctrl_block_in),
	.clk_sys(clk_sys),
	.clk_phy(clk_phy),
	.reset(rst),
	.phy_data_out(frame_seq_out),
	.phy_tx_en(phy_tx_out),
	.m_discard_en(discard_en)
);

initial begin // assigning value of data, data valid, and priority
	data_in = 8'h00;
	data_valid = 1'b0;
	hi_priority_en = 1'b1;
	#(6*`CLK_SYS);

	for (i=0; i < num_packets; i=i+1) begin
		// xFF for first four cycles
		data_in = 8'hFF;
		data_valid = 1'b1;
		hi_priority_en = priority;
		#(4*`CLK_SYS);

		// x00 for intermediate 56 cycles
		data_in = 8'h00;
		data_valid = 1'b1;
		hi_priority_en = priority;
		#(56*`CLK_SYS);

		// xFF again for last four cycles
		data_in = 8'hFF;
		data_valid = 1'b1;
		hi_priority_en = priority;
		#(4*`CLK_SYS);

		#(10*`CLK_SYS);
	end
end

initial begin // assigning value of ctrl, ctrl valid
	ctrl_block_in = 24'hFFF;
	ctrl_block_valid = 1'b0;
	#(6*`CLK_SYS);

	for (j=0; j < num_packets; j=j+1) begin
		// turn on control block for first cycle
		ctrl_block_in = 24'h040040;
		ctrl_block_valid = 1'b1;
		#(`CLK_SYS);

		// turn off control block again
		ctrl_block_in = 24'h000000;
		ctrl_block_valid = 1'b0;
		#((packet_length-1)*`CLK_SYS);

		#(10*`CLK_SYS);
	end
end

endmodule