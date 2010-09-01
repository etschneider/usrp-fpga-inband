// Generic FIFO module
// Based on Altera megafunction dcfifo

// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module dcfifo_generic 
#(
	parameter WIDTH			= 16,
	parameter NUM_WORDS		= 1024,
	parameter ADDR_WIDTH	= 10,	//log2(NUM_WORDS)
	parameter SHOW_AHEAD	= "OFF"
)
(
	input						aclr,
	input	[WIDTH-1:0]			data,
	input						rdclk,
	input						rdreq,
	input						wrclk,
	input						wrreq,
	output	[WIDTH-1:0]			q,
	output						rdempty,
	output						rdfull,
	output	[ADDR_WIDTH-1:0]	rdusedw,
	output						wrempty,
	output						wrfull,
	output	[ADDR_WIDTH-1:0]	wrusedw
);

	dcfifo	dcfifo_component (
				.wrclk (wrclk),
				.rdreq (rdreq),
				.aclr (aclr),
				.rdclk (rdclk),
				.wrreq (wrreq),
				.data (data),
				.rdfull (rdfull),
				.rdempty (rdempty),
				.wrusedw (wrusedw),
				.wrfull (wrfull),
				.wrempty (wrempty),
				.q (q),
				.rdusedw (rdusedw));
	defparam
		dcfifo_component.add_ram_output_register = "OFF",
		dcfifo_component.clocks_are_synchronized = "FALSE",
		dcfifo_component.intended_device_family = "Cyclone",
		dcfifo_component.lpm_numwords = NUM_WORDS,
		dcfifo_component.lpm_showahead = SHOW_AHEAD,
		dcfifo_component.lpm_type = "dcfifo",
		dcfifo_component.lpm_width = WIDTH,
		dcfifo_component.lpm_widthu = ADDR_WIDTH,
		dcfifo_component.overflow_checking = "ON",
		dcfifo_component.underflow_checking = "ON",
		dcfifo_component.use_eab = "ON";


endmodule
