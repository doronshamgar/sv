/////////////////////////////////////
//  file_parser is a system-verilog component for writing simple tests. 
//	file_parser will parse a given file and in turn will executes a predfeined (virtual) sequence on a predefined (virtual) sequencer.
//  this methodology is quick since the tests doesn't need to be re-compiled. just change the input file and you're good to go.  
//
//	sample input file:
//	read 0x1000              //(should execute a read form address 0x1000)
//	write 0x1000 0x1234 	 //(should execute a write to address 0x1000 of 0x1234 data)
//	read 0x1004 0x1 0x1      //(should execute a read from address 0x1004 and expect a value of 0x1 while using 0x1 mask)
//  poll 0x10008 0x1         //(should poll from address 0x10008 until the value equals to 0x1)
//
//  notes:
//  - use the parse_and_execute() task to start parsing a given file_name (up-until a certain line if needed, max_line).
//
////////////////////////////////////
typedef enum {RAW_PARSER} parse_type_e;

class file_parser#(
  type VSQR = uvm_sequencer,
  type SEQ = uvm_sequence 
) extends uvm_component;

  `uvm_component_param_utils(file_parser#(VSQR,SEQ))
  
  VSQR h_vsqr;
  SEQ seq;

  parse_type_e m_parse_type;

	extern function new(string name, uvm_component parent);
  extern function void build_phase(uvm_phase phase);

  //optional max_line parameter, defualt reading all file
  extern task parse_and_execute(string file_name, int max_line = 'h7FFF_FFFF);
  
  extern task raw_parser(string line, int line_num);

endclass: file_parser

function file_parser::new(string name, uvm_component parent);
  super.new(name, parent);
  m_parse_type = RAW_PARSER;
endfunction: new

function void file_parser::build_phase(uvm_phase phase);
  super.build_phase(phase);
endfunction: build_phase  

task file_parser::parse_and_execute(string file_name, int max_line = 'h7FFF_FFFF);
  //file descriptor
  int fd;     
  string line;
  int i = 1;

  fd = $fopen (file_name, "r");   
  if (fd) begin
    `uvm_info(get_name(), $sformatf("File was opened successfully (using %s)",m_parse_type), UVM_LOW)
  end else begin
    `uvm_fatal(get_name(), $sformatf("File %s could NOT be opened for reading",file_name))
  end
 
  while (!$feof(fd)) begin
    if ($fgets(line, fd) != 0) begin
      if (m_parse_type == RAW_PARSER) begin
        `uvm_info(get_name(), line, UVM_LOW)
        raw_parser(line,i);
      end
      i++;
      if (i > max_line) break;
    end 
  end
 
  // Close this file handle
  $fclose(fd);

endtask: parse_and_execute


/////////////////////////////////////////////////////////////////
///////////////////////RAW PARSER////////////////////////////////
/////////////////////////////////////////////////////////////////

task file_parser::raw_parser(string line, int line_num);
  int code;
  string command, re;
  bit [31:0] address, data, mask;

  string cmd_format[string] = '{
                                "write"   :"write %x %x",
                                "read"    :"read %x %x %x",
                                "poll"    :"poll %x %x"                                
                                };


  string ignore_format[] = '{"\n"," ","--","#","//"};

  //ignoring lines 
  foreach (ignore_format[i]) begin
    re = $sformatf("/^%s/",ignore_format[i]);
    if (!uvm_pkg::uvm_re_match(re,line)) begin
     `uvm_info(get_name(), $sformatf("ignoring line[%0d]: %s",line_num,line), UVM_LOW)    
      return;
    end
  end
 
 `uvm_info(get_name(), line, UVM_LOW)

  code = $sscanf(line,"%s",command);
  if (cmd_format.exists(command)) begin
    code = $sscanf(line,cmd_format[command],address, data, mask);
    `uvm_info(get_name(), $sformatf("executing line[%0d]: %s with addr=%x data=%x mask=%x",line_num,command,address, data, mask), UVM_LOW)

    seq = SEQ::type_id::create("seq");
    seq.command = command;
    seq.address = address;
    seq.data = data;
    seq.mask = mask;

    //sscanf will return values of 0's in data and mask even if there is no match in the string.
    //here we forward that information.
    if (command == "read") begin
      if (code == 2) begin
        seq.read_no_mask = 1;
      end
      if (code == 1) begin
        seq.read_no_val = 1;
      end
    end
    
    seq.start(h_vsqr);

  end else begin
    `uvm_fatal(get_name(), $sformatf("parsing line[%0d] failed: %s",line_num,line))
  end
endtask: raw_parser

/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////

