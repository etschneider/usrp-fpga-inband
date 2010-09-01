//Compare times taking in account for wrap around
//time is assumed invalid if the difference is grater than
//half the range (which will be true if the time is past)

module time_comparator  
#(parameter BITS = 32)
(
	input [BITS-1:0]	clock,
	input [BITS-1:0]	timestamp,
	output reg			match,
	output reg			valid
);


	reg [BITS-1:0] half_range;
	reg [BITS-1:0] delta;
	
	always @*
	begin
		//FIXME: this should be based on BITS
		half_range = 32'h7fffffff;	
		
		delta = timestamp - clock;  //this may wrap around here, which is ok.	

		if ( delta > half_range ) begin  //out of range
			valid <= 0;
			match <= 0;
		end
		else if (delta == 0) begin
			valid <= 1;
			match <= 1;
		end
		else begin
			valid <= 1;
			match <= 0;
		end
	end

endmodule
