module cmd_reader
   (
    //System
    input 				reset, 
    input 				txclk, 
    input [31:0] 		timestamp_clock,
    
    //FX2 Side
    output reg 			skip, 
    output reg 			rdreq, 
    input [31:0] 		fifodata, 
    input 				pkt_waiting,
    
    //Rx side
    input 				rx_WR_enabled, 
    output reg [15:0] 	rx_databus,
    output reg 			rx_WR, 
    output reg 			rx_WR_done,
    output reg			tx_dropped_packet,
    output reg [3:0]	tx_tag,
    
    //register io
    input wire [31:0] 	reg_data_out, 
    output reg [31:0] 	reg_data_in,
    output reg [6:0] 	reg_addr, 
    output reg [1:0] 	reg_io_enable,
    output wire [14:0]	debug, 
    output reg			stop, 
    output reg [15:0] 	stop_time
    );
	
   // States
   parameter IDLE                       =   4'd0;
   parameter HEADER                     =   4'd1;
   parameter TIMESTAMP                  =   4'd2;
   parameter WAIT          	    	    =   4'd3;
   parameter TEST                       =   4'd4;
   parameter SEND                       =   4'd5;
   parameter PING                       =   4'd6;
   parameter WRITE_REG                  =   4'd7;
   parameter WRITE_REG_MASKED           =   4'd8;
   parameter READ_REG                   =   4'd9;
   parameter DELAY                      =   4'd14;		

   `define OP_PING_FIXED                    8'd0
   `define OP_PING_FIXED_REPLY              8'd1
   `define OP_WRITE_REG	                    8'd2
   `define OP_WRITE_REG_MASKED              8'd3
   `define OP_READ_REG                      8'd4
   `define OP_READ_REG_REPLY                8'd5
   `define OP_DELAY                         8'd12
	

   `define JITTER                           5
   `define OP_CODE                          31:24
   `define PAYLOAD                          8:2

   reg [15:0]   header_val;
   wire [6:0] 	payload;
   
   assign payload = header_val[`PAYLOAD];	//7 MSB of length

   reg [6:0]   payload_read;
   reg [3:0]   state;
   reg [15:0]  high;
   reg [15:0]  low;
   reg         pending;
   reg [31:0]  value0;
   reg [31:0]  value1;
   reg [31:0]  value2;
   reg [1:0]   lines_in;
   reg [1:0]   lines_out;
   reg [1:0]   lines_out_total;

   reg [31:0]  time_delta;	//for packet time calculations
   
	wire time_match;
	wire time_valid;
	
	time_comparator	time_check (
		.clock(timestamp_clock),
		.timestamp(value0),
		.match(time_match),
		.valid(time_valid)
	);
	
   wire [7:0] ops;
   assign ops = value0[`OP_CODE];
   assign debug = {state[3:0], lines_out[1:0], pending, rx_WR, rx_WR_enabled, value0[2:0], ops[2:0]};

	//dropped_packet flag logic
	always @(posedge txclk)
	begin
		if (!reset && state == WAIT && !time_valid) 
			tx_dropped_packet <= 1;
		else 
			tx_dropped_packet <= 0;
	end
   
   //General state machine logic   
   always @(posedge txclk)
       if (reset)
         begin
           pending <= 0;
           state <= IDLE;
           skip <= 0;
           rdreq <= 0;
           rx_WR <= 0;
           reg_io_enable <= 0;
           reg_data_in <= 0;
           reg_addr <= 0;
           stop <= 0;
          end
        else case (state)
          IDLE : 
            begin
              payload_read <= 0;
              skip <= 0;
              lines_in <= 0;
              if(pkt_waiting)
                begin
                  state <= HEADER;
                  rdreq <= 1;
                end
             end
          
          HEADER : 
            begin
              header_val <= fifodata;
              state <= TIMESTAMP;
            end
          
          TIMESTAMP : 
            begin
              value0 <= fifodata;
              state <= WAIT;
              rdreq <= 0;
            end
			
          WAIT : 
            begin
				if (time_match || (value0 == 32'hffffffff)) begin
					state <= TEST;
					tx_tag <= header_val[`TAG];  //Echo tag field to rx buffer as feedback of command execution
				end
				else if (!time_valid) begin
					state <= IDLE;
					skip <= 1;
				end
				else
					state <= WAIT; 
			end	
          TEST : 
            begin
              reg_io_enable <= 0;
              rx_WR <= 0;
              rx_WR_done <= 1;
              stop <= 0;
              if (payload_read == payload)
                begin
                  skip <= 1;
                  state <= IDLE;
                  rdreq <= 0;
                end
              else
                begin
                  value0 <= fifodata;
                  lines_in <= 2'd1;
                  rdreq <= 1;
                  payload_read <= payload_read + 7'd1;
                  lines_out <= 0;
                  case (fifodata[`OP_CODE])
                    `OP_PING_FIXED: 
                      begin
                        state <= PING;
                      end
                    `OP_WRITE_REG: 
                      begin
                        state <= WRITE_REG;
                        pending <= 1;
                      end
                    `OP_WRITE_REG_MASKED: 
                      begin
                        state <= WRITE_REG_MASKED;
                        pending <= 1;
                      end
                    `OP_READ_REG: 
                      begin
                        state <= READ_REG;
                      end
                    `OP_DELAY: 
                      begin
                        state <= DELAY;
                      end
                    default: 
                      begin
                      //error, skip this packet
                        skip <= 1;
                        state <= IDLE;
                      end
                  endcase
                end
              end
			
            SEND: 
              begin
                rdreq <= 0;
                rx_WR_done <= 0;
                if (pending)
                  begin
                    rx_WR <= 1;
                    rx_databus <= high;
                    pending <= 0;
                    if (lines_out == lines_out_total)
                        state <= TEST;
                    else case (ops)
                        `OP_READ_REG: 
                          begin
                            state <= READ_REG;
                          end
                         default: 
                           begin
                             state <= TEST;
                           end
                    endcase
                  end
                else
                  begin
                    if (rx_WR_enabled)
                      begin
                        rx_WR <= 1;
                        rx_databus <= low;
                        pending <= 1;
                        lines_out <= lines_out + 2'd1;
                      end
                    else
                        rx_WR <= 0;
                  end
                end
			
            PING: 
              begin
                rx_WR <= 0;
                rdreq <= 0;
                rx_WR_done <= 0;
                lines_out_total <= 2'd1;
                pending <= 0; 
                state <= SEND;
                high <= {`OP_PING_FIXED_REPLY, 8'd2};
                low <= value0[15:0];	
              end
			
            READ_REG: 
              begin
                rx_WR <= 0;
                rx_WR_done <= 0;
                rdreq <= 0;
                lines_out_total <= 2'd2;
                pending <= 0;
                state <= SEND;
                if (lines_out == 0)
                  begin
                    high <= {`OP_READ_REG_REPLY, 8'd6};
                    low <= value0[15:0];
                    reg_io_enable <= 2'd3;
                    reg_addr <= value0[6:0];
                  end
                else
                  begin		
                    high <= reg_data_out[31:16];
                    low <= reg_data_out[15:0];
                  end
             end    
			
            WRITE_REG: 
              begin
                rx_WR <= 0;
                if (pending)
                    pending <= 0;
                else
                  begin
                    if (lines_in == 2'd1)
                      begin
                        payload_read <= payload_read + 7'd1;
                        lines_in <= lines_in + 2'd1;
                        value1 <= fifodata;
                        rdreq <= 0;
                      end
                    else
                      begin
                        reg_io_enable <= 2'd2;
                        reg_data_in <= value1;
                        reg_addr <= value0[6:0];
                        state <= TEST;
                      end
                  end
              end
			
            WRITE_REG_MASKED: 
              begin
                rx_WR <= 0;
                if (pending)
                    pending <= 0;
                else
                  begin
                    if (lines_in == 2'd1)
                      begin
                        rdreq <= 1;
                        payload_read <= payload_read + 7'd1;
                        lines_in <= lines_in + 2'd1;
                        value1 <= fifodata;
                      end
                    else if (lines_in == 2'd2)
                      begin
                        rdreq <= 0;
                        payload_read <= payload_read + 7'd1;
                        lines_in <= lines_in + 2'd1;
                        value2 <= fifodata;
                      end
                    else
                      begin
                        reg_io_enable <= 2'd2;
                        reg_data_in <= (value1 & value2);
                        reg_addr <= value0[6:0];
                        state <= TEST;
                      end
                  end
              end
			
            DELAY : 
              begin
                rdreq <= 0;
                stop <= 1;
                stop_time <= value0[15:0];
                state <= TEST;
              end
			
            default : 
              begin
                //error state handling
                state <= IDLE;
              end
        endcase
endmodule
