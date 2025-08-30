module fifo(
  input clk,rst,wr_en,rd_en,
  input [7:0] buf_in, 
  output reg [7:0]buf_out,
  output reg buf_empty,buf_full,
  output reg [5:0] fifo_counter
);
  
 // internal reg
  
  reg [5:0] wr_ptr,rd_ptr;
  reg [7:0] buf_mem[63:0];
  
  // status flag
  always@(fifo_counter)begin
    buf_empty=(fifo_counter==0);
    buf_full=(fifo_counter==64);
  end
  
  //counter logic
  
  always@(posedge clk or posedge rst)begin
    if(rst) 
      fifo_counter<=0; 
    
    else if(!buf_full && wr_en && !buf_empty && rd_en)
      fifo_counter<=fifo_counter;
   
      else if(!buf_full && wr_en)
        fifo_counter<= fifo_counter +1;
     
      else if(!buf_empty && rd_en)
        fifo_counter<= fifo_counter -1;
      
      else 
        fifo_counter<=fifo_counter;
      
    end

  
  // output logic
  
  always@(posedge clk or posedge rst)begin
    if(rst)begin
      buf_out<=0;
    end
    else if(!buf_empty && rd_en)begin
      buf_out<=buf_mem[rd_ptr];
    end
    else begin
      buf_out<=buf_out;
    end
  end
  // inpurt logic
  always@(posedge clk)begin
    if(!buf_full && wr_en)begin
      buf_mem[wr_ptr]<=buf_in;
    end
    else begin
      buf_mem[wr_ptr]<= buf_mem[wr_ptr];
    end
  end
  
  //pointer logic
  
  always@(posedge clk or posedge rst) begin
    if(rst)begin
      wr_ptr<=0;
      rd_ptr<=0;
    end
    else begin
      if(!buf_full && wr_en)begin
        wr_ptr<= wr_ptr +1;
      end
        else begin
          wr_ptr<= wr_ptr;
        end
      if(!buf_empty && rd_en) begin
        rd_ptr <= rd_ptr +1;
      end
      else begin
        rd_ptr<= rd_ptr;
      end
  end
  end
  
    endmodule
  
  
