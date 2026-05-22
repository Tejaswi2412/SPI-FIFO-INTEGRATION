//INTEGRATING SPI AND FIFO 
`timescale 1ns/1ps

module spi_fifo_top(input clk, wr_en  , reset , MISO , input [7:0]data_in , output wire MOSI , sclk , cs , done);

reg rd_en;
wire[7:0] data_out;
wire [2:0]wr_addr , rd_addr;
wire full, empty ,wr_en_mem , rd_en_mem ;
reg start ;
wire[7:0]rx_data;

fifo_ctrl  instant1(.clk(clk) , .wr_en(wr_en), .rd_en(rd_en) , .reset(reset) ,.full(full) ,.empty(empty) ,.rd_addr(rd_addr),.wr_addr(wr_addr) ,.wr_en_mem(wr_en_mem),.rd_en_mem(rd_en_mem));
fifo_mem instant2(.clk(clk), .wr_en(wr_en_mem), .rd_en(rd_en_mem), .wr_addr(wr_addr),.rd_addr(rd_addr), .data_in(data_in), .data_out(data_out));

spi_master instant3(.clk(clk), .MOSI(MOSI),.sclk(sclk),.cs(cs) ,.tx_data(data_out),.start(start),.done(done),.rx_data(rx_data),.MISO(MISO));


reg[2:0]state;

localparam idle = 3'd0 ;
localparam read = 3'd1;
localparam wait1 =3'd2;
localparam load = 3'd3;
localparam Wait = 3'd4;
localparam sending=3'd5;

initial begin
    state = idle;
    rd_en = 0;
    start = 0;
end

always@(posedge clk)begin

rd_en<=0;
start <=0;

if(reset)begin
    state<=idle;
end
else begin

case(state)

idle: if(!empty && cs ) 
        state<= read;

read:  begin 
          rd_en<=1; 
          state<= wait1;
       end

wait1: begin
            
            state<=load;
end

load:  begin 
           start<=1;
           state <= Wait;
       end

Wait: if(!cs)
        state <= sending;

sending: if(cs)
            state<=idle;
          

endcase
end
end
endmodule