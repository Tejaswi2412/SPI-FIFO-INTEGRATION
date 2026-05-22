`timescale 1ns/1ps

module spi_fifo_tb ;

reg clk, wr_en  , reset ;
reg [7:0]data_in ;
wire MOSI , sclk , cs , done;
reg MISO;

spi_fifo_top  uut(.clk(clk),.wr_en(wr_en),.data_in(data_in),.reset(reset), .MOSI(MOSI),.sclk(sclk) ,.cs(cs) ,.done(done),.MISO(1'b0));

initial clk=0;
always #10 clk=~clk;

initial begin
    reset =1;
     wr_en = 0;
    data_in = 0;
   #25 reset =0;

   @(posedge clk); #1 ;wr_en=1 ; data_in= 8'hAA;
   @(posedge clk); #1; wr_en=1; data_in=8'hBB;
   @(posedge clk); #1; wr_en=1; data_in=8'hCC;
   @(posedge clk); #1; wr_en=0;
   @(posedge clk);

#10000 $display("Time=%0t cs=%b done=%b empty=%b", $time, cs, done, uut.empty);
#10000 $display("Time=%0t cs=%b done=%b empty=%b", $time, cs, done, uut.empty);
#10000 $display("Time=%0t cs=%b done=%b empty=%b", $time, cs, done, uut.empty);

   #500000 $finish;

end

initial begin
    forever begin
        @(negedge cs);
        $display("--- Transfer start ---");
        repeat(8) begin
            @(posedge sclk);
            #1;
            $display("MOSI=%b", MOSI);
        end
    end
end

initial begin

    $dumpfile("spi_fifo_tb.vcd");
    $dumpvars(0, spi_fifo_tb);

end
endmodule
