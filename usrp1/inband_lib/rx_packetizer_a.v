// rx_packetizer_a.v

// This version will block and signal an overrun if there is not room
// for a complete packet.

// Sampling and overrun logic
// Keep track of how many samples we have saved so we can save header 
// info at the right time.

// In any case, all samples in a packet should be contiguous.

// TODO: handle flush when full	

module rx_packetizer_a
#(
    parameter PH_FIFO_SIZE	= 128,	//Depth of header fifo
    parameter PH_FIFO_SZ_L2	= 7,	//log2(SIZE)
    parameter CD_FIFO_SIZE	= 1024,	//Depth of channel data fifo
    parameter CD_FIFO_SZ_L2	= 10
)(
	input						reset,
	input						clk,
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

	output reg [63:0]			o_header,
	output reg [15:0]			o_chan_data
	
	//Debug
	,output [7:0]				dbg_sample_counter
);
	
    parameter SAMP_PER_PKT = 252;	//16 bit samples
		
	reg [7:0]	sample_counter;
	reg			pause;
	reg			wr_header;	//internal signal to save header to fifo
	reg			wr_data;	//internal signal to save data to fifo

	//for interleaving
	reg [15:0]	temp_i,temp_q;
	
	always @ ( posedge clk ) begin
		if (reset) begin
			sample_counter = 0;
			overrun 	= 0;
			pause		= 0;
			wr_header	= 0;
			ph_wren 	= 0;
			wr_data		= 0;
			cd_wren 	= 0;
		end
		else begin
			//defaults, override later
			//we need to make sure these are only set for 1 clk, 
			//not wren cycle
			ph_wren = 0;	
			cd_wren = 0;
							
			if (wren) begin
				//Before starting a packet...
				if (sample_counter == 0 ) begin
					//check for overrun
					if ( ph_full || ((CD_FIFO_SIZE - cd_usedw) < SAMP_PER_PKT ) ) begin
						pause	= 1;
						overrun = 1;
					end
					else begin
						//good to go
						pause = 0;

						//save the temp header info (timestamp, etc)
						o_header = i_header_data;
					end
				end
				
				//Sample on wren
				if (!pause) begin
					//debug: payload data
					//temp_i = sample_counter;
					//temp_q = i_header_data[`CB_TIMESTAMP];

					temp_i = i_chan_data_i;
					temp_q = i_chan_data_q;
					
					wr_data = 1;
				end
				
			end // if wren

			//ouput data to fifo and handling interleaving
			//this is outside of wren condition for interleaving
			if (wr_data) begin

				if (interleaved) begin
					if (sample_counter[0])	begin	//Q on odd samples
						o_chan_data = temp_q;
						wr_data = 0;
					end
					else
						o_chan_data = temp_i;
						//keep wr_data, still need q
				end
				else begin //not interleaved
					o_chan_data = temp_i;
					wr_data = 0;
				end

				sample_counter = sample_counter + 1;				
				cd_wren = 1;
				
			end
			
			//check for a forced flush (command channel used this)
			if (flush_packet)
				wr_header = 1;

			//time to save the header?
			//we don't need to wait for wren to push the header
			if ( wr_header || (sample_counter == SAMP_PER_PKT ) ) begin
				o_header[`CB_PAYLOAD_LEN] = (sample_counter<<1);	//actual payload length (x2 bytes)
				o_header[`CB_OVERRUN] = overrun;
				overrun = 0;  //clear overrun once we have saved the header
				sample_counter = 0; 
				ph_wren = 1; //enable the ph fifo
				wr_header = 0; //did it
			end
		
		end	// else reset
	end //always

	//debug
	assign dbg_sample_counter = sample_counter;

endmodule
