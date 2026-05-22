//SERIAL PERIPHERAL INTERFACE (SPI ) ---> SYNCHRONOUS , 4 SIGNALS 
//DESIGN OF MASTER USING MODE 0

`timescale 1ns/1ps

module spi_master ( input [7:0] tx_data ,
                    input clk ,start ,
                    output reg done,      //when task is completed , done is made high to let the outside world know that job is done perfectly.
                    output reg [7:0] rx_data ,
                    output reg sclk ,
                    output reg MOSI ,      //It is like tx_line in uart . it carries 1 bit at a time hence it is not 8 bits.
                    input MISO,            //since the slave transmits data ,it is input
                    output reg cs
                    
) ;


 parameter  cpol =0;      //we have not used assign as it creates extra hardware . the synthesizer sees assign as wire . but when we use parameter , synthesizer doesnot see it as a hardware . no wire is created , compiler sees it and do the changes if made .
 parameter cpha =0;        //parameter does not use extra memory . it's like #define in c language.
 reg [7:0] shift_reg;
 reg [7:0] rx_shift;
 reg first_edge;
 

 parameter clk_divider = 25;
 reg [4:0] clk_count;
 reg [3:0] bit_count;
 reg [1:0] state;           //i have four states . FSM tells in which state you're in. 4 states are idle,load,shift ,done_sh
 reg sclk_prev;

 localparam idle = 2'd0 ;      //localparam are fixed internally . outside world cannot change it . parameter can be changed by outside world but localparam cannot .
 localparam load = 2'd1 ;
 localparam transfer = 2'd2;
 localparam done_sh = 2'd3;

 initial begin
    state = idle;
    cs=1;
    clk_count =0;
    bit_count =0;
    sclk=0;
    done =0;
    sclk_prev=0;
    MOSI =0;
    first_edge=0;

end

    //CLOCK DIVIDER

 always@(posedge clk) begin

    if(state==transfer)begin
        if(clk_count==clk_divider -1 )begin
            clk_count<=0;
            sclk <= ~sclk;
        end
        else
            clk_count<=clk_count+1;

    end
    else begin
        sclk<=0;
        clk_count<=0;    // this is reset to 0 , otherwise it will start counting from previous value
    end


//FSM --it tells when things happen 

sclk_prev<= sclk;
case(state)
   idle:  begin
        cs<=1;
        done <=0;
        MOSI <=0;
        if (start==1)begin
            state<= load;
        end
   end

   load: begin
        cs<=0;
        bit_count <= 0;
        shift_reg <= tx_data;
        rx_shift <=0;
        first_edge <=1;
        state <= transfer;
   end

   transfer : begin 
    if(sclk_prev==1 && sclk ==0 ) begin

        MOSI <= shift_reg[7];
        shift_reg <= {shift_reg[6:0], 1'b0};
   end
         if(sclk_prev==0 && sclk==1)begin

            if(first_edge)
                first_edge<=0;
            else begin
            rx_shift<= {rx_shift[6:0], MISO };     //MISO is input we cannot assign to it . we read from it .
            bit_count <=bit_count+1;
            $display("Time=%0t bit_count=%0d", $time, bit_count);

            if (bit_count==7) begin          //it should be inside if block .
            state <= done_sh;
            end
            
         end
         end
   end 


   done_sh: begin 
            done<=1;
            cs<=1;
            rx_data <= rx_shift;
            state <= idle;
   end
endcase
 end

endmodule

