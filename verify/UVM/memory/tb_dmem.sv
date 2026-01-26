import uvm_pkg::* ;
`include "uvm_macros.svh"

// INTERFACE 
interface dmem_if ( input logic clk_i );
    logic        rst_i;        
    
    // (Write Port) - From Write Back (WB)
    logic        we_i;    
    logic        req_i;    
    logic [3:0]  be_i;   
    logic [31:0] wdata_i;      
    logic [31:0] addr_i; 
    logic [31:0] rdata_o;   
endinterface



// SEQUENCE ITEM
class dmem_item extends uvm_sequence_item;
	// Input
	rand bit [31:0]	addr_i	;
	rand bit [3:0]	be_i	;
	rand bit 	we_i	;
	rand bit [31:0]	wdata_i	;
	rand int 	delay	;
	rand bit 	req_i	;
	// Output
	bit [31:0] 	rdata_o	;
	
	// This func to print,copy,compare value of variable
	// `uvm_object_utils_begin(dmem_item) :It dmemisters your class with the factory and automates common methods for your variables
	// `uvm_fiel_int([name],flag|flag or empty) :It adds this specific variable to the automation list.
	// Flag :
	// UVM_NOCOMPARE :use for variable not important or alway change(time,)
	// UVM_NOPRINT : use for long name or don`t need watch
	// UVM_NOCOPY : use for variable only use in 1 project 
	// UVM_HEX,UVM_DEC, UVM_BIN, UVM_OCT, UVM_STRING : use type data print
	// FOR INPUT 
	`uvm_object_utils_begin(dmem_item)
	`uvm_field_int(req_i,		UVM_ALL_ON | UVM_BIN)	
	`uvm_field_int(we_i,    	UVM_ALL_ON | UVM_BIN)
	`uvm_field_int(be_i,    	UVM_ALL_ON | UVM_BIN)
	`uvm_field_int(addr_i,    	UVM_ALL_ON | UVM_HEX)
	`uvm_field_int(wdata_i,    	UVM_ALL_ON | UVM_HEX)
	`uvm_field_int(rdata_o,    	UVM_ALL_ON | UVM_HEX)
	`uvm_field_int(delay,    	UVM_ALL_ON | UVM_DEC)
	// FOR OUTPUT
	`uvm_field_int(rdata_o,   	UVM_ALL_ON | UVM_HEX)
	`uvm_object_utils_end
	constraint addr_c {addr_i<4096;}
	constraint delay_c {delay inside {[0:5]};}
	constraint be_valid_c { be_i inside {4'b1111, 4'b0011, 4'b1100, 4'b0001, 4'b0010, 4'b0100, 4'b1000}; }
function new(string name = "dmem_item");
		super.new(name);
	endfunction
endclass

// DRIVER
class dmem_driver extends uvm_driver #(dmem_item);
	`uvm_component_utils(dmem_driver)
	virtual dmem_if vif;
	function new( string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		if (!uvm_config_db#(virtual dmem_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "No Interface Found!")
	endfunction
	task run_phase(uvm_phase phase);
	// 1. Reset Init
        vif.req_i   <= 0;
        vif.we_i    <= 0;
        vif.be_i    <= 0;
        vif.addr_i  <= 0;
        vif.wdata_i <= 0;


	@(posedge vif.rst_i);
        `uvm_info("DRV", "Detected Reset Asserted", UVM_LOW) // <--- Thêm log

        @(negedge vif.rst_i);
        `uvm_info("DRV", "Detected Reset De-asserted. Starting loop...", UVM_LOW) // <--- Thêm log

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("DRV", $sformatf("Driving Item: Addr=%0h", req.addr_i), UVM_HIGH) // <--- Thêm log check item	


			@(posedge vif.clk_i);
		   	vif.rst_i	<= 0; // Đảm bảo không reset khi đang chạy
        		vif.req_i	<= 1;
        		vif.we_i	<= req.we_i;
        		vif.be_i	<= req.be_i;
        		vif.addr_i	<= req.addr_i;
      			vif.wdata_i	<= req.wdata_i;
        
			@(posedge vif.clk_i);
            		vif.req_i   <= 0;          // Tắt Chip Select
            		vif.we_i    <= 0;
            		vif.be_i    <= 0;
			// notice done
			// random delay
			repeat(req.delay) @(posedge vif.clk_i);
			seq_item_port.item_done();
		end
	endtask
endclass
// MONITOR
class dmem_monitor extends uvm_monitor;
	`uvm_component_utils(dmem_monitor)
	virtual dmem_if vif;
	uvm_analysis_port #(dmem_item) mon_port;
	
	function new(string name, uvm_component parent);
		super.new(name,parent);
		mon_port = new("mon_port", this);
	endfunction

	// get interface 
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Lấy virtual interface từ config_db
        if (!uvm_config_db#(virtual dmem_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON", "Không thể lấy vif! Kiểm tra lại lệnh set ở tb_top.")
        end
    endfunction
	task run_phase(uvm_phase phase);
    dmem_item item;
    forever begin
        @(posedge vif.clk_i);
        // Chờ 1 chút (1ns để tín hiệu ổn định rồi mới bắt
	if (vif.req_i) begin 
        
        // Tạo gói tin mới
        item = dmem_item::type_id::create("item");

        // NỐI DÂY NGƯỢC LẠI
        // Bên TRÁI là Class (Dữ liệu) = Bên PHẢI là Interface (Dây cứng)
        
        // Bắt Input (để biết Driver vừa lái cái gì)
        item.req_i	= vif.req_i;
        item.addr_i  	= vif.addr_i;
        item.wdata_i      = vif.wdata_i;
        item.be_i 	= vif.be_i;
        item.we_i 	= vif.we_i;

        // Bắt Output (Kết quả trả về từ Register File)
        // Lưu ý: Register File thường là Read Async (bất đồng bộ)
        // Nên có địa chỉ là có data ngay, bắt luôn được.
        #1;
	item.rdata_o    	= vif.rdata_o;
        // Gửi về Scoreboard
        mon_port.write(item);
    end
    end
endtask
endclass

// SCOREBOARD 
class dmem_scoreboard extends uvm_scoreboard;
    // 1.Inital Factory 
    `uvm_component_utils(dmem_scoreboard)

    // 2.Input data from Monitor
    // Cú pháp: uvm_analysis_imp #(LOẠI_GÓI_TIN, TÊN_CLASS_HIỆN_TẠI)
    uvm_analysis_imp #(dmem_item, dmem_scoreboard) scb_export;

    // 3.Reference Model
    bit [31:0] ref_mem [int];

    // 4.Constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
        scb_export = new("scb_export", this);
        
        // Khởi tạo tất cả thanh ghi về 0
        foreach(ref_mem[i]) begin
            ref_mem[i] = 0;
        end
    endfunction

    // 5. Function write - 
    // Đây là nơi xử lý logic so sánh chính
    function void write(dmem_item trans);
	    bit [31:0] exp_data;
	    int word_idx;
        // ---------------------------------------------------------
        // BƯỚC A:	MAPPING ADDRESS
        // Logic: Change address from byte to array index
        // --------------------------------------------------------
	word_idx	=	trans.addr_i >> 2;
	// Check bounds
	    return;
	        // ---------------------------------------------------------
        // BƯỚC B: UPDATE MODEL
        // LOGIC FOR WRITE MODEL 
        // ---------------------------------------------------------
	if (trans.we_i) begin
		if (trans.be_i[0]) ref_mem[word_idx][7:0] = trans.wdata_i[7:0];
		if (trans.be_i[1]) ref_mem[word_idx][15:8] = trans.wdata_i[15:8];
		if (trans.be_i[2]) ref_mem[word_idx][23:16] = trans.wdata_i[23:16];
		if (trans.be_i[3]) ref_mem[word_idx][31:24] = trans.wdata_i[31:24];
		`uvm_info("SCB_WRITE", $sformatf("Stored Addr:%0h (Idx:%0d) | Data:%0h | BE:%b",
                                             trans.addr_i, word_idx, ref_mem[word_idx], trans.be_i), UVM_HIGH)
        end
	// --------------------------------------------------------
        // BƯỚC 3: XỬ LÝ LOGIC ĐỌC (COMPARE)
        // --------------------------------------------------------
        else begin
            // DUT logic: if (req_i && we_i) -> rdata_o = mem_array[...]

            // Lấy dữ liệu vàng từ Reference Model
            if (!ref_mem.exists(word_idx)) begin
                ref_mem[word_idx] = 32'h0;
            end
	    exp_data = ref_mem[word_idx];
            // So sánh
            if (trans.rdata_o !== exp_data) begin
                `uvm_error("SCB_FAIL", $sformatf("READ FAIL WE : %0b| REQ: %0b|BE: %0b| Addr:%0h | DUT:%0h | EXP:%0h",trans.we_i,trans.req_i,trans.be_i,trans.addr_i, trans.rdata_o, exp_data))
            end else begin
                `uvm_info("SCB_PASS", $sformatf("READ PASS Addr:%0h | Data:%0h",
                                                trans.addr_i, trans.rdata_o), UVM_HIGH)
            end
        end
    endfunction

endclass

    // ---------------------------------------------------------
    // 5. AGENT & ENV (Bộ khung chứa các thành phần trên)
    // ---------------------------------------------------------
    class dmem_agent extends uvm_agent;
        `uvm_component_utils(dmem_agent)
        dmem_driver    driver;
        dmem_monitor   monitor;
        uvm_sequencer #(dmem_item) sequencer;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = dmem_driver::type_id::create("driver", this);
            monitor   = dmem_monitor::type_id::create("monitor", this);
            sequencer = uvm_sequencer#(dmem_item)::type_id::create("sequencer", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class dmem_env extends uvm_env;
        `uvm_component_utils(dmem_env)
        dmem_agent      agent;
        dmem_scoreboard scb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = dmem_agent::type_id::create("agent", this);
            scb   = dmem_scoreboard::type_id::create("scb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
       		super.connect_phase(phase);
		agent.monitor.mon_port.connect(scb.scb_export);
        endfunction
    endclass

    // ---------------------------------------------------------
    // 6. TEST 
	// Sequence loop 
    class dmem_rand_sequence extends uvm_sequence #(dmem_item);
    `uvm_object_utils(dmem_rand_sequence)
	bit [3:0] valid_be_list[] = '{4'b1111, 4'b0011, 4'b1100, 4'b0001, 4'b0010, 4'b0100, 4'b1000};
    function new(string name = "dmem_rand_sequence");
        super.new(name);
    endfunction

    task body();
        repeat(2000) begin // Test 2000 gói tin
            req = dmem_item::type_id::create("req");
            start_item(req);
            req.addr_i	= $urandom_range(0, 1023) << 2;
	    req.wdata_i 	= $urandom();
	    req.we_i	= $urandom_range(0, 1);
	    req.be_i	= valid_be_list[$urandom_range(0, valid_be_list.size() - 1)];
	    req.delay 	= $urandom_range(0, 5);
	    finish_item(req);
        end
    endtask
endclass
// Call sequence
class dmem_basic_test extends uvm_test;
    `uvm_component_utils(dmem_basic_test)
    dmem_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = dmem_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        dmem_rand_sequence seq;
        seq = dmem_rand_sequence::type_id::create("seq");

        phase.raise_objection(this);
        // Start sequence
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass


module tb_top;
    // 1. Khai báo Clock
import uvm_pkg::* ;
    bit clk;
    always #5 clk = ~clk; // Chu kỳ 10ns (100MHz)

    // 2. Khởi tạo Interface
    // (Lưu ý: Interface dmem_if đã định nghĩa ở bước trước)
    dmem_if vif(clk);

    // 3. Kết nối DUT (Device Under Test) - DATA MEMORY
    dmem dut (
        .clk_i   (clk),
        .rst_i   (vif.rst_i),

        // Control Signals
        .req_i   (vif.req_i),    // Chip Select
        .we_i    (vif.we_i),     // Write Enable
        .be_i    (vif.be_i),     // Byte Enable

        // Data/Address Signals
        .addr_i  (vif.addr_i),
        .wdata_i (vif.wdata_i),  // Input data
        .rdata_o (vif.rdata_o)   // Output data
    );

       
    
    initial begin
        // A. Khởi tạo giá trị ban đầu an toàn
        vif.rst_i   = 0;  
        vif.req_i   = 0;
        vif.we_i    = 0;
        vif.be_i    = 0;
        vif.addr_i  = 0;
        vif.wdata_i = 0;
	// 2. Đăng ký Interface (Quan trọng: Phải làm TRƯỚC run_test)
        uvm_config_db#(virtual dmem_if)::set(null, "*", "vif", vif);

        // 3. Gọi Test NGAY LẬP TỨC (Không được có delay # nào ở đây)
        run_test();
	end

	initial begin

        // B. Đăng ký Interface vào UVM Config DB
        #10;
        // Để Driver và Monitor có thể tìm thấy 'vif'
	vif.rst_i = 1;
        repeat (10) @(posedge clk);
        
        vif.rst_i = 0;  // Thả Reset -> DUT bắt đầu hoạt động
        @(posedge clk);
        // D. Gọi Test UVM
        
       // run_test("dmem_basic_test");
        // Tên test phải trùng với class name trong file dmem_test.sv
    end

    // 5. (Tùy chọn) Dump sóng để Debug trên phần mềm (GTKWave/Verdi)
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end

    // 6. Monitor in ra màn hình Console (Dạng bảng)
    initial begin
        // In tiêu đề cột
        $display("\n==========================================================================================");
        $display("   Time   | Rst | Req | WE |  BE  |    Addr    |    WData     |    RData     | Status ");
        $display("----------+-----+-----+----+------+------------+--------------+--------------+--------");

        // Format:
        // %t : Thời gian
        // %b : Bit
        // %h : Hex (8 số hex cho 32-bit)
        $monitor("%9t |  %b  |  %b  |  %b | %b | 0x%h | 0x%h | 0x%h | %s",
                 $time,
                 vif.rst_i,
                 vif.req_i,
                 vif.we_i,
                 vif.be_i,
                 vif.addr_i,
                 vif.wdata_i,
                 vif.rdata_o,
                 (vif.req_i === 1) ? (vif.we_i ? "WRITE" : "READ ") : "IDLE "
                 );
    end

endmodule
