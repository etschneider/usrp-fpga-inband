// rx_buffer_inband_tb

// This "test bench" is actually run in quartus as a top-level module
// Basically just to reduce the pin-count from rx_buffer_inband for the fitter.

module rx_buffer_inband_tb 
#( parameter NUM_CHAN = 2)
(
	//General
	input clk,
	input reset,
	input reset_regs,
	
	output reg [31:0] timestamp,
	
	//Channel inputs
	output 				rxstrobe,
	output wire [15:0]	chan_data_0,
	//output wire [15:0]	chan_data_1,
	//output wire [15:0]	chan_data_2,
	//output wire [15:0]	chan_data_3,

	//tx_buffer interconnection
	output reg			rx_WR,
	output reg 			rx_WR_done,
	output wire 		rx_WR_enabled,
	output reg [15:0]	rx_databus,
	output [1:0]		tx_underrun,
	
	//FX2 interface
	input wire usbclk,
	output wire usb_reset,
	output reg usb_rd,
	output wire usb_pkt_rdy,
	output wire rx_overrun,
	output wire [15:0] usb_data,

	output reg [8:0] usb_counter
		
	/////////////////////
	//Debug

	//,output [15:0]			debugbus
	
	//IQ interleaving
	,output					dbg_rx_wren
	,output					dbg_iq

	//chan buffer
	,output [7:0]			dbg_sample_counter_0
	,output [6:0]			dbg_num_pkt_0
	,output 				dbg_ph_full_0
	,output [6:0]			dbg_cd_wrusedw_0
	,output 				dbg_cd_full_0

	,output [7:0]			dbg_sample_counter_1
	,output [6:0]			dbg_num_pkt_1
	,output 				dbg_ph_full_1
	,output [10:0]			dbg_cd_wrusedw_1
	,output 				dbg_cd_full_1
/*
	,output [7:0]			dbg_sample_counter_2
	,output [6:0]			dbg_num_pkt_2
	,output 				dbg_ph_full_2
	,output [10:0]			dbg_cd_wrusedw_2
	,output 				dbg_cd_full_2
*/
	//Chan Selector
	,output [NUM_CHAN:0]	dbg_chans_ready
	,output [3:0]			dbg_chan_num
	,output [NUM_CHAN:0]	dbg_chan_en
	//,output [63:0] 			dbg_mux_header_data
	,output [15:0] 			dbg_mux_chan_data


	//Packet Builder
	,output [7:0]			dbg_read_count
	,output					dbg_pkt_complete	
	,output 				dbg_header_rd
	,output 				dbg_chan_rd
	
	,output reg [15:0]		usb_data_read

);

//parameter CHAN_END_AT	= 32'h000003f0;
parameter CHAN_END_AT	= 32'hffffffff;

parameter FX2_BEGIN_AT	= 32'h00000000;
//parameter FX2_BEGIN_AT	= 32'h00001500

parameter FX2_PKT_READS	= 9'd257;


	wire [63:0] 			dbg_mux_header_data;

	//Channel inputs
	wire [3:0]	num_chan;
	assign num_chan = 4'd2;

	wire [15:0]	chan_data_1;
	wire [15:0]	chan_data_2;
	wire [15:0]	chan_data_3;
	
	wire [31:0]	chan_rssi_0;
	wire [31:0]	chan_rssi_1;
	assign chan_rssi_0 = 32'h00000000;
	assign chan_rssi_1 = 32'h00000000;
	//assign chan_rssi_0 = 32'hffffffff;
	//assign chan_rssi_1 = 32'hffffffff;
	
	assign tx_underrun = 2'b00;
	//assign tx_underrun = 2'b11;
	
	//FX2
	//assign usbclk = clk;
	
	//Serial inferface
	reg serial_strobe, clear_status;
	reg [6:0]	serial_addr;
	reg [31:0]	serial_data;
	
	
	rx_buffer_inband 
	#(.NUM_CHAN(NUM_CHAN))
	rx_buffer 
	( 
		//control	
		.rxclk			( clk			),
		.reset			( reset			),
		.reset_regs		( reset_regs	),

		//Channel inputs
		.rxstrobe		( rxstrobe		),
		.timestamp		( timestamp		),
		.channels		( num_chan		),
		.ch_0			( chan_data_0	),
		.ch_1			( chan_data_1	),
		.ch_2			( chan_data_2	),
		.ch_3			( chan_data_3	),

		.rssi_0			( chan_rssi_0	), 
		.rssi_1			( chan_rssi_1	),
		
		//FX2/USB interface
		.usbclk			( usbclk		),
		.bus_reset		( usb_reset		),
		.RD				( usb_rd		),
		.usbdata		( usb_data		),
		.have_pkt_rdy	( usb_pkt_rdy	),
		.rx_overrun		( rx_overrun	),
		.clear_status	( 1'b1			),
		
		//Serial / Command Bus
		.serial_strobe	( serial_strobe	),
		.serial_addr	( serial_addr	), 
		.serial_data	( serial_data	), 

		//Connection with tx_inband
		.rx_WR			( rx_WR			),
		.rx_WR_done		( rx_WR_done	),
		.rx_databus		( rx_databus	),
		.tx_underrun	( tx_underrun	),
		.rx_WR_enabled	( rx_WR_enabled	)

		//Debug
		//,.debugbus			( debugbus				)

		//IQ interleaving
		,.dbg_rx_wren			( dbg_rx_wren			) 
		,.dbg_iq				( dbg_iq				)

		//chan buffer
		,.dbg_sample_counter_0	( dbg_sample_counter_0	)
		,.dbg_num_pkt_0			( dbg_num_pkt_0			)
		,.dbg_ph_full_0			( dbg_ph_full_0			)
		,.dbg_cd_wrusedw_0		( dbg_cd_wrusedw_0		)
		,.dbg_cd_full_0			( dbg_cd_full_0			)

		,.dbg_sample_counter_1	( dbg_sample_counter_1	)
		,.dbg_num_pkt_1			( dbg_num_pkt_1			)
		,.dbg_ph_full_1			( dbg_ph_full_1			)
		,.dbg_cd_wrusedw_1		( dbg_cd_wrusedw_1		)
		,.dbg_cd_full_1			( dbg_cd_full_1			)
/*
		,.dbg_sample_counter_2	( dbg_sample_counter_2	)
		,.dbg_num_pkt_2			( dbg_num_pkt_2			)
		,.dbg_ph_full_2			( dbg_ph_full_2			)
		,.dbg_cd_wrusedw_2		( dbg_cd_wrusedw_2		)
		,.dbg_cd_full_2			( dbg_cd_full_2			)
*/
		//Chan Selector
		,.dbg_chans_ready		( dbg_chans_ready		)
		,.dbg_chan_num			( dbg_chan_num			)
		,.dbg_chan_en			( dbg_chan_en			)
		,.dbg_mux_header_data	( dbg_mux_header_data	)
		,.dbg_mux_chan_data		( dbg_mux_chan_data		)

		//Packet Builder
		,.dbg_read_count		( dbg_read_count		)
		,.dbg_pkt_complete		( dbg_pkt_complete		)
		,.dbg_header_rd			( dbg_header_rd			)
		,.dbg_chan_rd			( dbg_chan_rd			)
	);

	defparam rx_buffer.NUM_CHAN=2;

	/////////////////////////////////////////////
	//generate timestamp
	always @ (posedge clk)
	begin
		if (reset) timestamp <= 32'd0;
		else timestamp <= timestamp + 32'd1;
	end

	/////////////////////////////////////////////
	// Strobe input
	assign rxstrobe = timestamp < CHAN_END_AT ? !reset & timestamp[2] && !timestamp[1:0] : 1'b0;

	/////////////////////////////////////////////
	//generate sawtooth channel input from timestamp
	//assign chan_data_0 = {4'h0,timestamp[11:0]};
	//assign chan_data_1 = {4'h1,timestamp[11:0]};
	//assign chan_data_2 = {4'h2,timestamp[11:0]};
	//assign chan_data_3 = {4'h3,timestamp[11:0]};

	// div to align w/ sample count
	assign chan_data_0 = {4'h0,timestamp[14:3]};
	assign chan_data_1 = {4'h1,timestamp[14:3]};
	assign chan_data_2 = {4'h2,timestamp[14:3]};
	assign chan_data_3 = {4'h3,timestamp[14:3]};

	
	/////////////////////////////////////////////
	// Control channel

	reg [7:0] ctl_cnt;
	reg do_ctl;
	
	always @ (posedge clk)
	begin
		if (reset) begin
			do_ctl <= 1'd0;
			ctl_cnt <= 8'd0;
		end
		
		//when to send control data
		if (timestamp == 32'd20) do_ctl <= 1'd1;
		
		if (do_ctl) begin
			ctl_cnt <= ctl_cnt + 8'd1;
			
			case (ctl_cnt)
			8'd0: begin
				rx_WR <= 1'd1;	
				rx_databus <= 16'h1234;
				end
			8'd1: begin
				rx_WR <= 1'd1;	
				rx_databus <= 16'h5678;
				end
			8'd2: begin
				rx_WR <= 1'd0;	
				rx_WR_done <= 1'd1;
				end
			default: begin
				rx_WR <= 1'd0;
				rx_WR_done <= 1'd0;
				ctl_cnt <= 8'd0;
				do_ctl <= 1'd0;
				end
			endcase
		end
	end
	
	
	
	/////////////////////////////////////////////
	//control FX2 reads
	assign usb_reset = reset;
	
	always @ (negedge usbclk)
	begin
		if (reset) begin
			usb_rd <= 1'd0;
		end
		else begin
			if (!usb_rd && usb_pkt_rdy && (timestamp >= FX2_BEGIN_AT ) ) 
				usb_rd <= 1'd1;
			else if (usb_counter >= (FX2_PKT_READS - 1))	
				usb_rd <= 1'd0;
		
		end
	end
	
	always @ (negedge usbclk)
	begin
		if ( usb_rd && !reset ) begin
			usb_counter <= usb_counter + 9'd1;
			usb_data_read <= usb_data;
		end	
		else begin
			usb_counter <= 9'd0;
			usb_data_read <= 16'hFEFE;
		end
	end
	
endmodule
