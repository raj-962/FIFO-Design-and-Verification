//-------------------- transaction --------------------
class transaction;
  rand  bit       wr_en;
  rand  bit       rd_en;
  randc bit [7:0] buf_in;
        bit [7:0] buf_out;
        bit       buf_empty, buf_full;
        bit [5:0] fifo_counter;

  // If you want to allow simultaneous wr/rd, comment this out
  constraint wr_rd { wr_en != rd_en; }
  constraint wr    { wr_en dist {0:=50, 1:=50}; }
  constraint rd    { rd_en dist {0:=50, 1:=50}; }

  function void display();
    $display(" Wr_en:%0d  Rd_en:%0d  buf_in:%0d  empty:%0d  full:%0d  count:%0d  buf_out:%0d @%0t",
             wr_en, rd_en, buf_in, buf_empty, buf_full, fifo_counter, buf_out, $time);
  endfunction

  function transaction copy();
     copy = new();
    copy.wr_en        = this.wr_en;
    copy.rd_en        = this.rd_en;
    copy.buf_in       = this.buf_in;
    copy.buf_out      = this.buf_out;
    copy.buf_empty    = this.buf_empty;
    copy.buf_full     = this.buf_full;
    copy.fifo_counter = this.fifo_counter;
    return copy;
  endfunction
endclass

//-------------------- interface --------------------
interface fif_if;
  logic clk, rst, wr_en, rd_en;
  logic [7:0] buf_in, buf_out;
  logic buf_empty, buf_full;
  logic [5:0] fifo_counter;
endinterface

//-------------------- generator --------------------
class generator;
  mailbox #(transaction) mbx_drv; // to driver

  function new(mailbox #(transaction) mbx_drv);
    this.mbx_drv = mbx_drv;
  endfunction

  // Drive for entire sim window: one item every 10 ns
  task run();
    transaction tr;
    forever begin
      tr = new();
      assert(tr.randomize()) else $display("Randomize failed");
      mbx_drv.put(tr.copy());
      // tr.display(); // optional
      #10;
    end
  endtask
endclass

//-------------------- driver --------------------
class driver;
  virtual fif_if fii;
  mailbox #(transaction) mbx_drv;

  function new(mailbox #(transaction) mbx_drv);
    this.mbx_drv = mbx_drv;
  endfunction

  task run();
    transaction t2;
    // defaults
    fii.wr_en  <= 0;
    fii.rd_en  <= 0;
    fii.buf_in <= '0;

    forever begin
      mbx_drv.get(t2);       // block until a new item arrives
      @(posedge fii.clk);
      // drive for one cycle (simple hand-to-mouth driver)
      fii.wr_en  <= t2.wr_en;
      fii.rd_en  <= t2.rd_en;
      fii.buf_in <= t2.buf_in;
      // $display("[DRV] drove item"); t2.display();

      @(posedge fii.clk);
      // return to idle so edges are visible
      fii.wr_en  <= 0;
      fii.rd_en  <= 0;
      // buf_in can stay; FIFO samples on wr_en anyway
    end
  endtask
endclass

//-------------------- monitor --------------------
class monitor;
  virtual fif_if fii;
  mailbox #(transaction) mbx_sb; // to scoreboard

  function new(mailbox #(transaction) mbx_sb);
    this.mbx_sb = mbx_sb;
  endfunction

  task run();
    transaction t3;
    forever begin
      @(posedge fii.clk);

      t3 = new();
      t3.wr_en        = fii.wr_en;
      t3.rd_en        = fii.rd_en;
      t3.buf_in       = fii.buf_in;
      t3.buf_out      = fii.buf_out;
      t3.buf_empty    = fii.buf_empty;
      t3.buf_full     = fii.buf_full;
      t3.fifo_counter = fii.fifo_counter;

      // delay only for scoreboard sync
       mbx_sb.put(t3);

      $display("[MON]\n Wr_en:%0d  Rd_en:%0d  buf_in:%0d  empty:%0d  full:%0d  count:%0d  buf_out:%0d @%0t", 
                t3.wr_en, t3.rd_en, t3.buf_in, t3.buf_empty, t3.buf_full, t3.fifo_counter, t3.buf_out, $time);
    end
  endtask
endclass



//-------------------- scoreboard --------------------
class scoreboard;
  mailbox #(transaction) mbx_sb;
  bit [7:0] ref_fifo[$]; // reference queue
  bit [7:0] pending;
  bit       pending_valid;

  function new(mailbox #(transaction) mbx_sb);
    this.mbx_sb = mbx_sb;
    pending_valid = 0;
  endfunction

  task run();
    transaction t4;
    forever begin
      mbx_sb.get(t4);

      // check previous cycle read
      if (pending_valid) begin
        if (t4.buf_out !== pending)
          $error("[SB] MISMATCH: exp=%0d got=%0d @%0t", pending, t4.buf_out, $time);
        else
          $display("[SB] MATCH: %0d @%0t", pending, $time);
        pending_valid = 0;
      end

      // model enqueue
      if (t4.wr_en && !t4.buf_full)
        ref_fifo.push_back(t4.buf_in);

      // model dequeue: capture expected for next cycle
      if (t4.rd_en && !t4.buf_empty) begin
        if (ref_fifo.size() > 0) begin
          pending        = ref_fifo.pop_front();
          pending_valid  = 1;
        end else
          $display("[SB] Underflow attempt @%0t", $time);
      end

      if (t4.wr_en && t4.buf_full)
        $display("[SB] Overflow attempt @%0t", $time);
    end
  endtask
endclass


//-------------------- top tb --------------------
module tb;
  fif_if fii();
  driver     drv;
  generator  gen;
  monitor    mon;
  scoreboard sco;

  // split mailboxes
  mailbox #(transaction) mbx_drv; // gen -> drv
  mailbox #(transaction) mbx_sb;  // mon -> sb

  // DUT (your fifo module; keep as-is)
  fifo dut (
    .clk(fii.clk), .rst(fii.rst),
    .wr_en(fii.wr_en), .rd_en(fii.rd_en),
    .buf_in(fii.buf_in), .buf_out(fii.buf_out),
    .buf_empty(fii.buf_empty), .buf_full(fii.buf_full),
    .fifo_counter(fii.fifo_counter)
  );

  // clock
  initial fii.clk = 0;
  always  #20 fii.clk = ~fii.clk;

  // reset (sync release)
  initial begin
    fii.rst = 1;
    repeat(2) @(posedge fii.clk);
    fii.rst = 0;
  end

  // build/connect
  initial begin
    mbx_drv = new();
    mbx_sb  = new();

    gen = new(mbx_drv);
    drv = new(mbx_drv);
    mon = new(mbx_sb);
    sco = new(mbx_sb);

    drv.fii = fii;
    mon.fii = fii;
  end

  // run for 1000ns (variation the whole time)
  initial begin
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_none
    #1000 $finish;
  end

  // waves
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);
  end
endmodule
