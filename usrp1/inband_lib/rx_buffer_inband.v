// rx_buffer_inband
// 
// This is the "pull" design, where packets are assembled as
// they are read out of the usbdata bus by the FX2.
//
// Header information such as timestamp is saved in a seperate
// FIFO that runs parallel to the channel data FIFO.
// (see rx_channel_buffer.v)
//
// Note: the max input rate is master_clock/2 since the interleaving is
// currently done on the front end.  The data FIFOs could be widened
// and interleaved by the packet builder to reach master_clock rates)
// However, unless sampling relatively short bursts,this would eventually 
// overrun the FIFOs as the FX2 interface wouldn't be able to keep up.
//
//            +---------+            |\
// ch0_hdr  ->| Channel |-> header ->| \
//            | Buffer  |            |  \
// ch0_data ->|         |-> data --->|   \  +---------+
//            +---------+            | M |->| Packet  |
//                                   | U |  | Builder |-> FX2
//            +---------+            | X |->|         |
// ch1_hdr  ->| Channel |-> header ->|   |  +---------+
//            | Buffer  |            |  / 
// ch1_data ->|         |-> data --->| /
//            +---------+            |/ 
//                                        
//
// The control channel in this module is logically channel 0, where
// it's packet channel ID is 0x1F.  The logical data chans are chan+1.
// This simplifies the generation logic with a parameterized number 
// of channels.  (And priority)
//
// Dependencies:
//		inband_packet_defs.v
//		rx_channel_buffer.v
//		packet_builder.v
//
// TODO: latch underrun and dropped to that each signal is guaranteed to be sent once
// TODO: handle single channel in dual chan config (channels input)
// TODO: Refactor.  This interface was kept from the original version.

`include "inband_packet_defs.v"

`define BUFFER_DROP_FLAG	1
	
module rx_buffer_inband 
#(
	parameter NUM_CHAN 			= 2,
	parameter CMND_FIFO_SIZE	= 256,
	parameter CMND_FIFO_SZ_L2	= 8,
	parameter CHAN_FIFO_SIZE	= 2048,
	parameter CHAN_FIFO_SZ_L2	= 11
)( 
	//control	
	input rxclk,	//master clock
	input reset,  // DSP side reset (used here), do not reset registers
	input reset_regs, //Only reset registers

	//Channel inputs
	input 				rxstrobe,
	input [31:0]		timestamp,
	input [3:0]			channels,	//number of channels (unused)
	input [15:0]		ch_0,
	input [15:0]		ch_1,
	input [15:0]		ch_2,
	input [15:0]		ch_3,
	input [15:0]		ch_4,
	input [15:0]		ch_5,
	input [15:0]		ch_6,
	input [15:0]		ch_7,
	input wire [31:0]	rssi_0, 
	input wire [31:0]	rssi_1,
	input wire [31:0]	rssi_2, 
	input wire [31:0]	rssi_3,
	
	//FX2/USB interface
	input				usbclk,
	input				bus_reset,
	input				RD,
	input				clear_status,
	output [15:0]		usbdata,
	output 				have_pkt_rdy,
	output reg			rx_overrun,
	
	//Serial / Command Bus			//Unused?
	input				serial_strobe,
	input [6:0]			serial_addr, 
	input [31:0]		serial_data, 

	//Connection with tx_inband
	input				rx_WR,
	input				rx_WR_done,
	input [15:0]		rx_databus,
	input [1:0] 		tx_underrun,
	input		 		tx_dropped_packet,
    input [3:0]			tx_tag,

	output 				rx_WR_enabled

	/////////////////////
	//Debug
	,output [15:0]			debugbus
	
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

	,output [7:0]			dbg_sample_counter_2
	,output [6:0]			dbg_num_pkt_2
	,output 				dbg_ph_full_2
	,output [10:0]			dbg_cd_wrusedw_2
	,output 				dbg_cd_full_2

	//Chan Selector
	,output [NUM_CHAN:0]	dbg_chans_ready
	,output [3:0]			dbg_chan_num
	,output [NUM_CHAN:0]	dbg_chan_en

	,output [63:0] 			dbg_mux_header_data
	,output [15:0] 			dbg_mux_chan_data

	//Packet Builder
	,output [7:0]			dbg_read_count
	,output					dbg_pkt_complete	
	,output 				dbg_header_ack
	,output 				dbg_chan_rd
);

	//parameter TOTAL_CHANS = NUM_CHAN + 1; //including command channel

	parameter LCHAN_CONTROL = 0;	//Logical Channel number of control chan
		
	wire usbclk_inv;
	assign usbclk_inv = ~usbclk;  //invert so all logic is posedge

	/////////////////////////////////////////////////////////////////////////
	// FX2 overrun signal
	wire [NUM_CHAN:0] overrun;
	
	always @ (posedge usbclk_inv) begin
		if (reset) rx_overrun <= 1'b0;
		else begin 
			if (overrun) rx_overrun <= 1'b1;
			else if (clear_status) rx_overrun <= 1'b0;
		end
	end

	/////////////////////////////////////////////////////////////////////////
	// TX / cmd_reader interface
	// We need to work with the rx_WR/rx_WR_done signals to make them
	// compatible with rx_channel_buffer.
	reg cmd_flush,have_wr;
	
	always @ (posedge rxclk)
	begin
		if (reset) cmd_flush <= 1'b0;
		else begin
			if (rx_WR) have_wr <= 1'b1;
			
			if (rx_WR_done & have_wr) begin
				cmd_flush <= 1'b1;
				have_wr <= 1'b0;
			end
			else cmd_flush <= 1'b0;
		end
	end
	
		//misc control channel
	assign rx_WR_enabled = !overrun[LCHAN_CONTROL];
	

	/////////////////////////////////////////////////////////////////////////
	// Generate the data channel buffers

	// select the data inputs for each channel
	wire [15:0] i_chan_data_i[4:0];
	wire [15:0] i_chan_data_q[4:0];
	
	assign i_chan_data_i[0] = rx_databus; 	//control data
	assign i_chan_data_q[0] = 16'h0000;
	assign i_chan_data_i[1] = ch_0;
	assign i_chan_data_q[1] = ch_1;
	assign i_chan_data_i[2] = ch_2;
	assign i_chan_data_q[2] = ch_3;
	assign i_chan_data_i[3] = ch_4;
	assign i_chan_data_q[3] = ch_5;
	assign i_chan_data_i[4] = ch_6;
	assign i_chan_data_q[4] = ch_7;

	
	wire [5:0] i_rssi[4:0];
	assign i_rssi[0] = rssi_0[5:0];
	assign i_rssi[1] = rssi_1[5:0];
	assign i_rssi[2] = rssi_2[5:0];
	assign i_rssi[3] = rssi_3[5:0];


	//Control signals
	wire [4:0] chan_num;	//the selected channel
	wire [NUM_CHAN:0] chan_en;

	wire [63:0] mux_header_data;
	wire [15:0] mux_chan_data;

	wire header_ack;
	wire chan_rd;

	//declare nets to be assigned by generate below
	wire [6:0] num_pkt[NUM_CHAN:0];

	wire [63:0] i_header_data[NUM_CHAN:0];	

	//wire header_ack[0:NUM_CHAN];
	//wire data_rd[0:NUM_CHAN];
	
	wire [63:0] o_header_data[NUM_CHAN:0];
	wire [15:0] o_chan_data[NUM_CHAN:0];

	//channel ready sigs
	wire [NUM_CHAN:0] chans_ready;

	// Debug channel connections
	wire [6:0]	dbg_ph_wrusedw[NUM_CHAN:0];
	wire [9:0]	dbg_cd_wrusedw[NUM_CHAN:0];
	wire		dbg_ph_full[NUM_CHAN:0];
	wire		dbg_cd_full[NUM_CHAN:0];
	wire		dbg_save_header[NUM_CHAN:0];
	wire [7:0]	dbg_sample_counter[NUM_CHAN:0];

	genvar i;
	generate for (i=1; i <= NUM_CHAN; i=i+1)
	begin : cb

		wire header_saved;
		
		assign i_header_data[i][`CB_CHAN] = i-1;
		assign i_header_data[i][`CB_RSSI] = i_rssi[i-1];
		assign i_header_data[i][`CB_UNDERRUN] = tx_underrun[i-1];
				
		assign i_header_data[i][`CB_OVERRUN] = 1'b0; //generated in channel_buffer
		assign i_header_data[i][`CB_PAYLOAD_LEN] = 9'd0; //not currently an input (auto-generated)
			
		assign i_header_data[i][`CB_TAG] = tx_tag;
		assign i_header_data[i][`CB_TIMESTAMP] = timestamp;
		
		assign i_header_data[i][`CB_NON_INPUTS] = 0;


		`ifdef BUFFER_DROP_FLAG
		/////////////////////////////////////////////////////////////////////////
		// Set dropped flag on all channels if (any are) set.  This is required
		// because channels may not be semetrical.  e.g. We want to know if
		// a command is dropped, but don't expect any data returned from the
		// command channel.
		//
		// Latch tx_dropped_packet flag when set, (re)set only after the header
		// has been saved to ensure that the flag gets sent (once).
		reg tx_dropped_latch;
		
		always @ ( posedge rxclk )
			if ( tx_dropped_packet || header_saved )
				tx_dropped_latch <= tx_dropped_packet;

		assign i_header_data[i][`CB_DROPPED] = tx_dropped_latch;

		`endif

		rx_channel_buffer  
		#(
			.CD_FIFO_SIZE	( CHAN_FIFO_SIZE	),
			.CD_FIFO_SZ_L2	( CHAN_FIFO_SZ_L2	)
		)
		chan_buf
		(
			.reset			( reset						),
			
			.wrclk			( rxclk						),
			.interleaved	( 1'b1						),
			.wren			( rxstrobe					),
			.flush_packet	( 1'b0						),
			
			.rdclk			( usbclk_inv				),
			.rd_data_en		( chan_en[i] & chan_rd		),
			.rd_header_en	( chan_en[i] & header_ack	),
			.num_packets	( num_pkt[i]				),
			.packet_rdy		( chans_ready[i]			),
			.overrun		( overrun[i]				),
			
			.i_chan_data_i	( i_chan_data_i[i]			),
			.i_chan_data_q	( i_chan_data_q[i]			),
			.i_header_data	( i_header_data[i]			),
			.o_chan_data	( o_chan_data[i]			),
			.o_header_data	( o_header_data[i]			),

			.header_saved		( header_saved 	)
			
			//debug
			,.dbg_ph_wrusedw		( dbg_ph_wrusedw[i]		)
			,.dbg_cd_wrusedw		( dbg_cd_wrusedw[i]		)
			,.dbg_ph_full			( dbg_ph_full[i]		)
			,.dbg_cd_full			( dbg_cd_full[i]		)
			,.dbg_sample_counter	( dbg_sample_counter[i]	)
		);

		//Debug
		assign dbg_save_header[i] = header_saved;
	end
	endgenerate


	/////////////////////////////////////////////////////////////////////////
	// Command Channel Buffer

		assign i_header_data[0][`CB_CHAN] = 5'h1f;
		assign i_header_data[0][`CB_RSSI] = 6'd0;
		assign i_header_data[0][`CB_UNDERRUN] = 1'b0;

		assign i_header_data[0][`CB_OVERRUN] = 1'b0; //generated in channel_buffer
		assign i_header_data[0][`CB_PAYLOAD_LEN] = 9'd0; //not currently an input (auto-generated)
		assign i_header_data[0][`CB_TIMESTAMP] = timestamp;
		
		assign i_header_data[0][`CB_NON_INPUTS] = 0;

		rx_channel_buffer  
		#(
			.CD_FIFO_SIZE	( CMND_FIFO_SIZE	),
			.CD_FIFO_SZ_L2	( CMND_FIFO_SZ_L2	)
		)
		chan_buf_ctl
		(
			.reset			( reset						),
			
			.wrclk			( rxclk						),
			.interleaved	( 1'b0						),
			.wren			( rx_WR						),
			.flush_packet	( cmd_flush					),
			
			.rdclk			( usbclk_inv				),
			.rd_data_en		( chan_en[0] & chan_rd		),
			.rd_header_en	( chan_en[0] & header_ack	),
			.num_packets	( num_pkt[0]				),
			.packet_rdy		( chans_ready[0]			),
			.overrun		( overrun[0]				),
			
			.i_chan_data_i	( i_chan_data_i[0]			),
			.i_chan_data_q	( i_chan_data_q[0]			),
			.i_header_data	( i_header_data[0]			),
			.o_chan_data	( o_chan_data[0]			),
			.o_header_data	( o_header_data[0]			)
			
			//debug
			,.header_saved			( dbg_save_header[0]	)
			,.dbg_ph_wrusedw		( dbg_ph_wrusedw[0]		)
			,.dbg_cd_wrusedw		( dbg_cd_wrusedw[0]		)
			,.dbg_ph_full			( dbg_ph_full[0]		)
			,.dbg_cd_full			( dbg_cd_full[0]		)
			,.dbg_sample_counter	( dbg_sample_counter[0]	)
		);

	/////////////////////////////////////////////////////////////////////////
	// Channel Selector
	wire pkt_complete;
		
	rx_channel_selector
	#(
		.NUM_CHAN	( NUM_CHAN+1 )
	) 
	chan_selector 
	(
		.clk			( usbclk_inv			),
		.reset			( reset					),
		.reading		( RD && !pkt_complete	),
		.chans_ready	( chans_ready			),
		.chan_en		( chan_en				),
		.chan_num		( chan_num				)
	);

	//map header/channel fifo data outputs for packet builder
	assign mux_header_data = o_header_data[chan_num];
	assign mux_chan_data = o_chan_data[chan_num];				

	`ifndef BUFFER_DROP_FLAG
	/////////////////////////////////////////////////////////////////////////
	// Set dropped flag on all channels if (any are) set.  This is required
	// because channels may not be semetrical.  e.g. We want to know if
	// a command is dropped, but don't expect any data returned from the
	// command channel.
	//
	// Latch tx_dropped_packet flag when set, (re)set only after packet builder
	// has read to ensure that the flag gets sent (once).
	reg	tx_dropped_latch;
	
	always @ (posedge rxclk or posedge header_ack)
		if ( header_ack )
			tx_dropped_latch <= tx_dropped_packet;
		else if ( rxclk )
			tx_dropped_latch <= tx_dropped_packet | tx_dropped_packet;
	`endif
	
	/////////////////////////////////////////////////////////////////////////
	// Packet Builder / FX2 interface

	packet_builder pb (
		.clk				( usbclk_inv						),
		.rden				( RD								),

		.header_ack			( header_ack						),
		.overrun			( mux_header_data[`CB_OVERRUN]		),
		.underrun			( mux_header_data[`CB_UNDERRUN]		),
`ifdef BUFFER_DROP_FLAG
		.dropped_packet 	( mux_header_data[`CB_DROPPED]		),
`else
		.dropped_packet 	( tx_dropped_latch					),
`endif
		.start_burst		( mux_header_data[`CB_BURST_START]	),
		.end_burst			( mux_header_data[`CB_BURST_END]	),
		.rssi				( mux_header_data[`CB_RSSI]			),
		.chan_number		( mux_header_data[`CB_CHAN]			),
		.tag				( mux_header_data[`CB_TAG]			),
		.payload_length 	( mux_header_data[`CB_PAYLOAD_LEN]	),
		.timestamp			( mux_header_data[`CB_TIMESTAMP]	),

		.chan_rd			( chan_rd							),
		.chan_data			( mux_chan_data						),

		.packet_data		( usbdata							),
		.packet_complete	( pkt_complete						)
		
		//debug
		,.read_count		( dbg_read_count					)

	);

	assign have_pkt_rdy = chans_ready ? 1'd1 : 1'd0;


	/////////////////////////////////////////////////////////////////////////
	// Debug assignments

	assign debugbus = 16'h0;
	
	//IQ interleaving
	assign dbg_rx_wren 			= 0;
	assign dbg_iq 				= 0;

	//chan buffer
	assign dbg_sample_counter_0	= dbg_sample_counter[0];
	assign dbg_num_pkt_0		= num_pkt[0];
	assign dbg_ph_full_0		= dbg_ph_full[0];
	assign dbg_cd_wrusedw_0		= dbg_cd_wrusedw[0];
	assign dbg_cd_full_0		= dbg_cd_full[0];

	assign dbg_sample_counter_1	= dbg_sample_counter[1];
	assign dbg_num_pkt_1		= num_pkt[1];
	assign dbg_ph_full_1		= dbg_ph_full[1];
	assign dbg_cd_wrusedw_1		= dbg_cd_wrusedw[1];
	assign dbg_cd_full_1		= dbg_cd_full[1];
/*
	assign dbg_sample_counter_2	= dbg_sample_counter[2];
	assign dbg_num_pkt_2		= num_pkt[2];
	assign dbg_ph_full_2		= dbg_ph_full[2];
	assign dbg_cd_wrusedw_2		= dbg_cd_wrusedw[2];
	assign dbg_cd_full_2		= dbg_cd_full[2];
*/
	//Chan Selector
	assign dbg_chans_ready		= chans_ready;
	assign dbg_chan_num			= chan_num;
	assign dbg_chan_en			= chan_en;
	
	assign dbg_mux_header_data 	= mux_header_data;
	assign dbg_mux_chan_data 	= mux_chan_data;				


	//Packet Builder
	assign dbg_pkt_complete		= pkt_complete;
	assign dbg_header_ack		= header_ack;
	assign dbg_chan_rd			= chan_rd;


endmodule
