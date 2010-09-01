//channel_selector
//Schedule and select available channels

module rx_channel_selector #(parameter NUM_CHAN=3)
(
	input					clk,
	input					reset,
	input					reading,		//will not switch until clear

	input [NUM_CHAN-1:0]	chans_ready,	//set bits for ready channels

	//channel outputs
	output reg [NUM_CHAN-1:0]	chan_en,	//channel enable signals
	output reg [4:0]			chan_num

);
	
	//map data outputs
	//assign mux_header_data = o_header_data[chan_sel];
	//assign mux_chan_data = o_chan_data[chan_sel];				
			
	// Handle channel mux selection on clk.
	// Only change when when no packet is being sent.
	// Use next_chan logic to select the next available
	// channel from the last channel we sent.
	integer i,next;
	reg [4:0] sel_next_chan_num[NUM_CHAN-1:0];
	reg [4:0]	last_chan_num;
	
//	always @ (posedge clk)
	always @*
	begin
		if (reset) begin
			chan_num = NUM_CHAN-1;	//force first channel to be next after reset
			last_chan_num <= 5'd0;
			chan_en = 0;
		end
		else begin
			//logic to get the next available channel number
			//TODO: maybe better to just work on chans_ready w/o index?
			for (i=0; i < NUM_CHAN; i=i+1) begin
				next = ( i == NUM_CHAN-1 ) ? 0 : i+1;
				sel_next_chan_num[i] = chans_ready ? (chans_ready[next] ? next : sel_next_chan_num[next]) : 5'd0;
			end
			
			if (!reading) begin
				chan_num = sel_next_chan_num[last_chan_num];

				//update enable lines
				for (i=0; i < NUM_CHAN; i=i+1) begin
					chan_en[i] = (i == chan_num) ? 1'b1 : 1'b0;
				end
				
			end
			else last_chan_num <= chan_num;
		end
	end

endmodule
	