module time_comparator_tb;

	reg [31:0] clock;
	reg [31:0] timestamp;

	wire match;
	wire valid;

`define JITTER 4
	
	time_comparator	time_check (
		.clock(clock),
		.timestamp(timestamp),
		.match(match),
		.valid(valid)
	);

	integer i;

	initial begin
		$display("timestamp,clock,match,valid");
		$monitor("%h %h %b %b",timestamp,clock,match,valid);
	
		$display("Normal sequence");
		timestamp = 32'h0000003;
		clock     = 32'h0000000;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		
		#1 $display("Wrap around sequence");
		clock     = 32'hfffffffe;		
		timestamp = 32'h00000001;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;

		#1 $display("Into range");
		clock     = 32'h00000000;
		timestamp = 32'h80000002;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
		#1 clock = clock + 31'h1;
	
	
		#1 $finish;
	end

	
endmodule
	
