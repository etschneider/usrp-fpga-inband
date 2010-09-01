// rx_channel_buffer 
// This module encapsulates the buffering for a single channel,
// including timestamp/header sampling and variable payload
// length packet generation.
//
// The actual logic is encapsulated in rx_packetizer, this
// module simply joins that logic to the fifos.
//
// Header information such as timestamp is saved in a seperate
// FIFO that runs parallel to the channel data FIFO.
//
// Header information is captured with the first sample of a
// packet, but is pushed to the FIFO after the packet's chan data.
// This permits such things as variable size packets without having
// to know the size at the time of the first sample.  This is
// used for the control channel and in overrun conditions.
//
// NOTE: Both FIFOS used are dual clock WITH look ahead, so 
// rd_req is asserted AFTER the read (it is an ACK).  
//
// Dependencies:
//		rx_packetizer_[a/b].v
//		inband_packet_defs.v
//		dcfifo_generic.v

module rx_channel_buffer 
#(
    parameter PH_FIFO_SIZE	= 128,	//Depth of header fifo
    parameter PH_FIFO_SZ_L2	= 7,	//log2(SIZE)
    parameter CD_FIFO_SIZE	= 1024,	//Depth of channel data fifo
    parameter CD_FIFO_SZ_L2	= 10
)(
	input			reset,
	
	//Input control
	input			wrclk,
	input			wren,
	input			interleaved,	//IQ or not
	input			flush_packet,	//will send non-full packet
	
	//Input
	input [63:0]	i_header_data,
	input [15:0]	i_chan_data_i,
	input [15:0]	i_chan_data_q,
	
	//Output control
	input			rdclk,		//negedge
	input			rd_data_en,
	input			rd_header_en,	
	
	//Status
	output [6:0]	num_packets,	//Number of packets ready to go
	output			packet_rdy,
	output 			overrun,
	
	//Output
	output			header_saved,

	output [15:0]	o_chan_data,
	output [63:0]	o_header_data

	
	//Debug
	,output [7:0]	dbg_sample_counter
	,output [6:0]	dbg_ph_wrusedw
	,output [9:0]	dbg_cd_wrusedw
	,output 		dbg_ph_full
	,output			dbg_cd_full
);
	
	assign packet_rdy = num_packets ? 1'b1 : 1'b0;
	
	// Packet header fifo related
	wire [63:0]	fifo_header;
	wire [15:0]	fifo_chan_data;
	
	wire ph_full;
	wire ph_wren;

	assign header_saved	= ph_wren;
	
	dcfifo_generic  #(
		.WIDTH		( 64	),
		.NUM_WORDS	( PH_FIFO_SIZE	),
		.ADDR_WIDTH	( PH_FIFO_SZ_L2	),	
		.SHOW_AHEAD	( "ON"	)
	)
	ph_fifo (
		.aclr 		( reset			),
//		.data 		( ph_fifo_input	),
		.data 		( fifo_header	),
		.wrclk 		( wrclk			),
		.wrreq 		( ph_wren		),
		.wrfull 	( ph_full		),
		.rdclk 		( rdclk			),
		.rdreq 		( rd_header_en	),
		.rdusedw	( num_packets	),
		.q			( o_header_data	)
		//debug
		,.wrusedw 	( dbg_ph_wrusedw )
	);

	//
	//Channel data fifo related
	wire [CD_FIFO_SZ_L2-1:0] cd_wrusedw;
	wire cd_full;
	wire cd_wren;
	
	dcfifo_generic  #(
		.WIDTH 		( 16			),
		.NUM_WORDS 	( CD_FIFO_SIZE	),
		.ADDR_WIDTH ( CD_FIFO_SZ_L2	),
		.SHOW_AHEAD ( "ON"			)
	)
	cd_fifo (
		.aclr 		( reset 			),
		.data 		( fifo_chan_data 	),
		.wrclk 		( wrclk				),
		.wrreq 		( cd_wren			),
		.wrfull 	( cd_full			),
		.wrusedw	( cd_wrusedw		),
		.rdclk 		( rdclk				),
		.rdreq 		( rd_data_en		),
		.q 			( o_chan_data		)
		//debug
		//,.rdusedw ( cd_rdusedw )	
	);


	rx_packetizer_a
	#(	
		.PH_FIFO_SIZE	( PH_FIFO_SIZE	),
		.PH_FIFO_SZ_L2	( PH_FIFO_SZ_L2	),
		.CD_FIFO_SIZE	( CD_FIFO_SIZE	),
		.CD_FIFO_SZ_L2	( CD_FIFO_SZ_L2	)
	)
	packetizer
	(
		.reset			( reset				),
		.clk			( wrclk				),
		.interleaved	( interleaved		),
		.wren			( wren				),
		.flush_packet	( flush_packet		),
		
		.i_header_data	( i_header_data		),
		.i_chan_data_i	( i_chan_data_i		),
		.i_chan_data_q	( i_chan_data_q		),
		
		//.ph_usedw		( ph_fifo.wrusedw	),
		.ph_full		( ph_full			),

		.cd_usedw		( cd_wrusedw		),
		.cd_full		( cd_full			),
		
		.ph_wren		( ph_wren			),
		.cd_wren		( cd_wren			),
		.overrun		( overrun			),

		.o_header		( fifo_header		),
		.o_chan_data	( fifo_chan_data	)
		
		//Debug
		,.dbg_sample_counter	( dbg_sample_counter	)
	);


	//debug
	//assign dbg_sample_counter = sample_counter;
	assign dbg_ph_full		= ph_full;

	assign dbg_cd_wrusedw	= cd_wrusedw;
	assign dbg_cd_full 		= cd_full;


endmodule
