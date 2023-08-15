interface intf(input bit pclk,presetn);

    logic pwrite;
    logic penable,psel,transfer;
    logic [31:0] paddr,pwrdata;
    logic pready,pslverr;
    logic [31:0]prdata;

endinterface

class transaction;

  typedef enum bit [1:0] {write=0, read=1} oper_type;
    rand oper_type   oper;
         bit   pwrite;
         bit   penable,psel,transfer;
    rand bit   [31:0] paddr,pwrdata;
         bit    pready,pslverr;
         bit   [31:0]prdata;
  
  constraint cn1{paddr inside{[0:7]}; }
  constraint cn2 {pwrdata inside {[1:100]};}
  constraint cn3 {oper dist{1:=35, 0:=35};}

    function void display(string s);    
      $display("%s\t\tOPER=%0s PADDR=(%0d) PWRITE=(%0d) PWRDATA=%0d @%0d",s,oper.name(),paddr,pwrite,pwrdata,$time);
    endfunction

endclass
//--------------------------------------------------------------------------------------------------------------------------------------------------
class generator;
  mailbox #(transaction) gen2driv;
  mailbox gen2cov;
    int repeat_no;
    event drivnext;
    event scbnext;
    event ended;
    int i;

  function new(mailbox #(transaction) gen2driv, mailbox gen2cov);
        this.gen2driv=gen2driv;
        this.gen2cov=gen2cov;
    endfunction

    task main();
        transaction t;
        t=new();
        i=1;
        repeat(repeat_no) begin
            
            if(!t.randomize)
              $fatal("RANDOMIZATION FAILED");
            else begin
              $display("\nTRANSECTION NUMBER = %0d",i);
              t.display("GENERATOR ");
            end
          gen2driv.put(t);
          gen2cov.put(t);
          i++;
          @(scbnext);
        end
        ->ended;
    endtask
endclass
//--------------------------------------------------------------------------------------------------------------------------------------------------
class driver;
  mailbox #(transaction)gen2driv;
    mailbox #(bit [7:0]) driv2scb;
    event drivnext;
    int no_trans=0;
    virtual intf intf_h;
    int i=1;
    bit[7:0] din;
transaction t;
  function new(mailbox #(transaction) gen2driv, mailbox #(bit [7:0]) driv2scb,virtual intf intf_h);
        this.gen2driv=gen2driv;
        this.driv2scb=driv2scb;
        this.intf_h=intf_h;
    t=new();
    endfunction

    task reset();
        $display("\nRESET STARTED");
      wait(intf_h.presetn==1);
        intf_h.psel<=0;
        intf_h.paddr<=1'b1;
        intf_h.pwrite<=0;
        intf_h.penable<=0;
        intf_h.pwrdata<=0;
        intf_h.transfer<=0;
      wait(intf_h.presetn==0);
      $display("RESET FINISHED");
    endtask

    task main();
        
      
        forever begin
		  
        gen2driv.get(t);
        @(posedge intf_h.pclk); 
        
        if(t.oper==2'b00)begin 
        					       //write transfer
        intf_h.paddr=t.paddr;  
        intf_h.pwrdata=t.pwrdata; 
        intf_h.pwrite=1;               
        intf_h.penable=0;
        intf_h.psel=1;
        intf_h.transfer=1;       //setup state
        @(posedge intf_h.pclk);      
     
        $display("DRIVER    \t\tTRANSMITTED DATA IS %0d   \t@%0d",t.pwrdata,$time);
        intf_h.penable=1;  //acess state 
         i++; 
        end
           
        if(t.oper==2'b01)begin
         						   //readtransfer
        intf_h.paddr=t.paddr;  
        intf_h.pwrdata=t.pwrdata; 
        intf_h.pwrite=0;               
        intf_h.penable=0;
        intf_h.psel=1;
        intf_h.transfer=1;       //setup state
        @(posedge intf_h.pclk);      

        intf_h.penable=1;  
         i++; //acess state 
         $display("DRIVER    \t\tDATA READ REQUESTED @%0d ADDR LOCATON \t@%0d",t.paddr,$time);
        end
          
         
    end
    endtask


endclass
//--------------------------------------------------------------------------------------------------------------------------------------------------
class monitor;
    mailbox #(transaction) mon2scb;
    bit [7:0]dscb;
    int no_trans;
    virtual intf intf_h;
    int i;
    transaction t;

     function new(mailbox #(transaction) mon2scb,virtual intf intf_h);
        this.mon2scb=mon2scb;
        this.intf_h=intf_h;
        t=new();
    endfunction

    task main();
      forever begin     
       repeat(2) @(posedge intf_h.pclk);
        
        if(intf_h.pwrite==1) begin
           t.pwrdata=intf_h.pwrdata;
           t.paddr=intf_h.paddr; 
           t.oper=0;
            @(posedge intf_h.pclk); 
          
        end
        else if(intf_h.pwrite==0) begin
           t.paddr=intf_h.paddr;
           t.oper=1;
          @(posedge intf_h.pclk); 
           t.prdata=intf_h.prdata;
        end
        mon2scb.put(t);
      end
       
    endtask

endclass
//--------------------------------------------------------------------------------------------------------------------------------------------------
class coverage;
    transaction t;
    mailbox gen2cov;
    covergroup cg;
      c1: coverpoint  t.oper;  
      c2: coverpoint  t.paddr{bins b0={32'd0}; bins b1={32'd1};
                              bins b2={32'd2}; bins b3={32'd3};
                              bins b4={32'd4}; bins b5={32'd5};
                              bins b6={32'd6}; bins b7={32'd7};}
      c3: coverpoint  t.pwrdata;
      c4: cross c1,c2,c3;
        
    endgroup

  function new(mailbox gen2cov);
    	this.gen2cov=gen2cov; 
        t=new();
   	 	cg=new();
    endfunction

    task main();
      forever begin
       gen2cov.get(t);
       cg.sample(); 
      end
    endtask

    task display();
      $display("COVERAGE=%f",cg.get_coverage());
    endtask

endclass
//--------------------------------------------------------------------------------------------------------------------------------------------------
class scoreboard;
    mailbox #(transaction)mon2scb;
    mailbox #(bit [7:0])driv2scb;
    event scbnext;
    int no_trans;
    bit [31:0]rdata;
    bit [31:0]pwrdata[8]='{default:'0};
  int q[$];
  int i=1;
  transaction t;

  function new(mailbox #(transaction) mon2scb, mailbox #(bit [7:0]) driv2scb);
        this.driv2scb=driv2scb;
        this.mon2scb=mon2scb;
        t=new();
    endfunction

    task main();
        forever begin

                mon2scb.get(t);
          
				 
          if(t.oper==0) begin
                    pwrdata[t.paddr]=t.pwrdata;
                  $display("SCOREBOARD\t\t DATA WRITTEN ON MEMORY @%0d LOCATION IS %0d",t.paddr,t.pwrdata);
                end
          
          
          if(t.oper==1) begin
                  
                  rdata=pwrdata[t.paddr];
            $display("SCOREBOARD\t\tDATA READ ON MEMORY @%0d LOCATION IS %0d",t.paddr,t.prdata);
                  
                  if(rdata==t.prdata)
                   	 $display("           \t\tDATA MATCHED");
                  
                   else begin
                      $display("          \t\t DATA MISMATCHED ACTUAL DATA =%0d",rdata);
                      q.push_front(i);
                      
                    end         
                  
          end
          i++;
            ->scbnext;
            
        end
    endtask
  
  task report_g;
     transaction t;
      int i;
      int temp;
      
      if(q.size()) begin
        $display("The  Failed Transections Numbers are ");
          foreach (q[i]) begin
            $display("%0d",q[i]);
          end
      end
      else
        $display("Passed all testcases");
    endtask
  
endclass
//--------------------------------------------------------------------------------------------------------------------------------------------------

class environment;
    mailbox #(transaction) gen2driv;
    mailbox # (bit[7:0]) driv2scb;
    mailbox # (transaction) mon2scb;
  	mailbox gen2cov;

    event nextgd;
    event nextgs;
    generator g;
    driver d;
    monitor m;
    scoreboard s;
  	coverage c;
    virtual intf intf_h;

    function new(virtual intf intf_h);
        this.intf_h=intf_h;
        gen2driv=new();
        driv2scb=new();
        mon2scb=new();
      	gen2cov=new();

      g=new(gen2driv,gen2cov);
        d=new(gen2driv,driv2scb,intf_h);
        m=new(mon2scb,intf_h);
        s=new(mon2scb,driv2scb);
      c=new(gen2cov);

        g.drivnext=nextgd;
        d.drivnext=nextgd;
        g.scbnext=nextgs;
        s.scbnext=nextgs;
    endfunction

    task pre_test();
        d.reset();
    endtask

    task test();
        fork
            g.main();
            d.main();
            m.main();
           s.main();
           c.main();
        join_any
    endtask

    task post_test();
        wait(g.ended.triggered);
         $display("-------------------------------------------------------------------------------");
        s.report_g();
       $display("-------------------------------------------------------------------------------");
        c.display();
      $display("-------------------------------------------------------------------------------");
        $finish();
         
    endtask

    task run();
         pre_test();
         test();
         post_test();
    endtask

endclass
//--------------------------------------------------------------------------------------------------------------------------------------------------
program test(intf intf_h);
    environment e;
    initial begin
        e=new(intf_h);
        e.g.repeat_no=400;
      e.run();

    end
endprogram
//--------------------------------------------------------------------------------------------------------------------------------------------------
module tb;
    
    bit clk,rst;

    initial begin
        clk=0;
        forever #5 clk=~clk;
    end

    initial begin
        rst=1;
      repeat(2) @(posedge clk);
      rst=0;
    end
  
	initial begin
      $dumpfile("dump.vcd");
      $dumpvars;
    end
  
  intf a(clk,rst);
  test t(a);

  apb_slave dut (a.pclk,a.presetn,a.transfer,a.psel,a.penable,a.paddr,a.pwrite,a.pready,a.pwrdata,a.pslverr,a.prdata);
     
   

endmodule
