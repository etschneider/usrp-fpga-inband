// rx_packetizer_b.v

// NOTE: This is not currently functional

// This version try to totally fill the fifo before signaling an overrun.

// Sampling and overrun logic
// Keep track of how many samples we have saved so we can save header 
// info at the right time.
//
// Overrun behavior is to fill the data fifo until full, at which
// time sampling stops and the header is pushed with the current payload size
// and the ovverrun bit set.  Sampling is suspended until there is room for 
// a complete packet.  
// If the header fifo is full (unlikely, and which would happen after 
// completing a packet) sampling is suspended.  The saved header is pushed
// when there is room.
// In any case, all samples in a packet should be contiguous.
	

module rx_packetizer_b 
#(
    parameter PH_FIFO_SIZE	= 128,	//Depth of header fifo
    parameter PH_FIFO_SZ_L2	= 7,	//log2(SIZE)
    parameter CD_FIFO_SIZE	= 1024,	//Depth of channel data fifo
    parameter CD_FIFO_SZ_L2	= 10
)(
	input						reset,
	input						wrclk,
	input						interleaved,
	input						wren,
	input						flush_packet,	//will send non-full packet
	
	input [63:0]				i_header_data,
	input [15:0]				i_chan_data_i,
	input [15:0]				i_chan_data_q,
	
	input [PH_FIFO_SZ_L2-1:0]	ph_usedw,
	input						ph_full,

	input [CD_FIFO_SZ_L2-1:0]	cd_usedw,
	input						cd_full,
	
	output reg					ph_wren,	//packet header fifo enable
	output reg					cd_wren,	//channel data fifo enable
	output reg					overrun,

	output reg [63:0]			temp_header,
	output reg [15:0]			temp_data
	
	//Debug
	,output [7:0]				dbg_sample_counter
);
	
    parameter SAMP_PER_PKT = 252;	//16 bit samples

	 
	reg [7:0]	sample_counter;
	reg 		save_header;	//flag to set ph_wren when available
	
	always @ ( posedge wrclk ) begin
		if (reset) begin
			sample_counter <= 8'd0;
			overrun = 1'b0;
			save_header = 1'b0;
			ph_wren <= 1'b0;
			cd_wren = 1'b1;	//enable by default
		end
		else begin 
			//Check cd fifo for overrun
			if (cd_full) begin
				//only save header once 
				if (!overrun) 
					save_header = 1'b1;

				overrun = 1'b1;
				cd_wren = 1'b0;
			end
			
			if ( flush_packet || (sample_counter == SAMP_PER_PKT) )
				save_header = 1'b1;
			
			if (save_header) begin
				//Header fifo full?
				if (ph_full) begin
					overrun = 1'b1;
					cd_wren = 1'b0;	//No more data if ph_fifo is full
					ph_wren <= 1'b0;
				end
				else begin
					//Save the header
					temp_header[`CB_PAYLOAD_LEN] = (sample_counter<<1);	//actual payload length (x2 bytes)
					sample_counter <= 8'd0;	//start counting new packet
					ph_wren <= 1'b1; //enable the fifo
					save_header = 1'b0;	//it has been done
				end
			end
			else 
				ph_wren <= 1'b0;
			
			
			//Can we resume saving channel data?
			if (!ph_full && (cd_usedw < (CD_FIFO_SIZE - SAMP_PER_PKT)))
				cd_wren = 1'b1;

			
			//If we are saving chan data...
			if (wren && cd_wren) begin
				//if this is first sample, save the temp header info (timestamp, etc)
				if (!sample_counter) begin
					temp_header = i_header_data;
					temp_header[`CB_OVERRUN] = overrun;
					overrun = 1'b0;  //only clear overrun once we have sent the packet
				end
				sample_counter <= sample_counter + 8'd1;
			end

		end //else
	end //always


	//debug
	assign dbg_sample_counter = sample_counter;

endmodule
