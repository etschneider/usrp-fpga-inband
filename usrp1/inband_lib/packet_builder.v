// packet_builder.v
//
// Create packet outputs for a single channel.  
// 16 bit wide output, suitable for sending to FX2/USB.
// Inputs include all header information and ADC data
 
// It is assumed that the header inputs are valid 
// when rden is set, and during the first 4 clock 
// cycles while the header is being sent.  
// Depending on the architecture, external logic may be 
// required to capture and hold volitile values 
// such as timestamp during this period.  The header_ack
// line will be set when the header values can be released.

// chan_data should be updated on every clock cyle as long
// as chan_rd is set.  It will read payload_length/2
// (rounding up) times.

// Output is limited to 256 reads per rden.  rden must be 
// dropped between packets.  This is mostly a workaround for 
// the FX2 257 RD bug.

// Dependencies:
//		inband_packet_defs.v
 
module packet_builder (
	// Control / Status
	input				clk,
	input				rden,  //read enable, resets state when clear

	// Header inputs
	output reg   		header_ack,		//header_data read signal

	input				overrun,
	input				underrun,
	input				dropped_packet,
	input				start_burst,
	input				end_burst,
	input [5:0]			rssi,
	input [4:0]			chan_number,
	input [3:0]			tag,
	input [8:0]			payload_length,
	input [31:0]		timestamp,

	// Signal/Channel data
	output reg   		chan_rd,		//chan_data read signal
	input [15:0] 		chan_data,

	// Packet output
	output reg [15:0]	packet_data,
	output reg			packet_complete,	//raised on last output

	//main state var, our line position (16b wide) in the packet
	output reg [7:0] 			read_count
);

	parameter	RD_HEADER1		= 0, 
				RD_HEADER2		= 1, 
				RD_TIMESTAMP1	= 2, 
				RD_TIMESTAMP2	= 3, 
				RD_PAYLOAD1		= 4, 
				RD_LAST			= 255;
				
	parameter PAD_VALUE = 16'hDEAD;
	
	/////////////////////////////////////////////////////////////////////////
	//read_count logic
	//We want the default postion to be RD_HEADER1
	//The FX2 will already be reading data when rden
	//is set, so make sure it is there waiting...
	always @(posedge clk) begin
		if ( rden && !packet_complete )
			read_count <= read_count + 8'd1;
		else
			read_count <= RD_HEADER1;			
	end

	/////////////////////////////////////////////////////////////////////////
	//We also need to be sure to set packet complete on the last read, 
	//as the channel selector needs it.
	//We stay set until rden is cleared
	always @(posedge clk) begin
		if ( read_count == ( RD_LAST ) )
			packet_complete <= 1'b1;
		else if (!rden)	
			packet_complete <= 1'b0;
	end
	
	/////////////////////////////////////////////////////////////////////////
	//Header and data fifo signals

	reg [7:0] padding_pos;	//read_count where padding starts
	
	always @(posedge clk) begin
		//Calculate (and save) when we should start sending padding
		//since payload is specified in bytes, and data out is 16b,
		//we need to round up odd values
		//FIXME: should we force a valid paylod size here?  We assume =< max
		if ( read_count == RD_HEADER1 )
			padding_pos <= ( payload_length >> 1 ) + ( payload_length[0] ? RD_PAYLOAD1 - 1 : RD_PAYLOAD1 - 2 );		

		//ack the header fifo when we are done w/ it
		//header_ack <= ( read_count == (RD_TIMESTAMP2 - 1) ) ? 1'd1 : 1'd0; //On last header read
		header_ack <= ( read_count == (RD_PAYLOAD1 - 1) ) ? 1'd1 : 1'd0;		//Delay until payload

		//and the chan fifo
		chan_rd <= ((read_count >= (RD_PAYLOAD1 - 1)) && (read_count <= padding_pos)) ? 1'd1 : 1'd0;

	end

	/////////////////////////////////////////////////////////////////////////
	//Select the proper output based on the read counter
	//NOTE: This will not mask the spare byte on odd payload sizes.
	//      It is assumed that it is not worth the trouble (no harm done).
	//		Really, the specifed pad value probably isn't required either...

	reg [15:0] h1,h2,ts1,ts2; //header,timestamp,channel data
	
	always @* begin
//	always @(posedge clk) begin

/*
		//Just for testing...
		case ( read_count )
			RD_HEADER1:		packet_data <= 16'h1111; //h1;
			RD_HEADER2:		packet_data <= 16'h2222; //h2;
			RD_TIMESTAMP1:	packet_data <= 16'h3333; //ts1;
			RD_TIMESTAMP2:	packet_data <= 16'h4444; //ts2;
			default:		packet_data <= chan_rd ? 16'h5555 : 16'h6666; //chan_rd ? chan_data : PAD_VALUE;
		endcase	
*/
		//Wire up inputs to mux the possible packet_data outputs
		h1[`PAYLOAD_LEN]	= payload_length;
		h1[`TAG]			= tag;
		h1[`MBZ]			= 0;

		h2[`CHAN]			= chan_number;
		h2[`RSSI]			= rssi;
		h2[`BURST_START]	= start_burst;
		h2[`BURST_END]		= end_burst;
		h2[`DROPPED]		= dropped_packet;
		h2[`UNDERRUN]		= underrun;
		h2[`OVERRUN]		= overrun;

		ts1					= timestamp[15:0];
		ts2					= timestamp[31:16];

		//Select the proper value for output
		case ( read_count )
			RD_HEADER1:		packet_data <= h1;
			RD_HEADER2:		packet_data <= h2;
			RD_TIMESTAMP1:	packet_data <= ts1;
			RD_TIMESTAMP2:	packet_data <= ts2;
			default:		packet_data <= chan_rd ? chan_data : PAD_VALUE;
			//debug: payload data
			//default:		
			//	if (read_count[0]) packet_data <= chan_data;
			//	else packet_data <= {chan_data[7:0],read_count};
		endcase  

	end

	
endmodule
