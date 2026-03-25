import uvm_pkg::* ;
`include "uvm_macros.svh"

// INTERFACE 
interface dmem_if ( input logic clk_i );
    logic        rst_i;        
    
    // (Write Port) - From Write Back (WB)
    // Request Channel
    logic        req_valid_i;
    logic        req_ready_o;
    logic [31:0] req_addr_i;
    logic [31:0] req_wdata_i;
    logic [3:0]  req_be_i;
    logic        req_we_i;
    
    // Response Channel
    logic        rsp_valid_o;
    logic        rsp_ready_i;
    logic [31:0] rsp_rdata_o;   
endinterface



// SEQUENCE ITEM
class dmem_item extends uvm_sequence_item;
	// Request phase
        rand logic [31:0] req_addr;
        rand logic [31:0] req_wdata;
        rand logic [3:0]  req_be;
        rand logic        req_we;
        rand int          req_delay;
    // Response Phase
        logic [31:0]      rsp_rdata;
        rand int          rsp_ready_delay;

	

	`uvm_object_utils_begin(dmem_item)
    `uvm_field_int(req_addr,  UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(req_wdata, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(req_be,    UVM_DEFAULT | UVM_BIN)
    `uvm_field_int(req_we,    UVM_DEFAULT | UVM_BIN)
    `uvm_field_int(rsp_rdata, UVM_DEFAULT | UVM_HEX)
	`uvm_object_utils_end
	constraint addr_c {req_addr<4096;}
	constraint delay_c {req_delay inside {[0:5]};}
	constraint be_valid_c { req_be inside {4'b1111, 4'b0011, 4'b1100, 4'b0001, 4'b0010, 4'b0100, 4'b1000}; }
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
	
        vif.req_valid_i   <= 0;
        vif.rsp_ready_i    <= 0;

        wait(vif.rst_i === 1'b0); // Chờ reset kết thúc (Active High)
        @(posedge vif.clk_i);

        fork
            // Thread 1: Drive Requests
            forever begin
                seq_item_port.get_next_item(req);
                repeat(req.req_delay) @(posedge vif.clk_i);

                vif.req_valid_i <= 1'b1;
                vif.req_addr_i  <= req.req_addr;
                vif.req_wdata_i <= req.req_wdata;
                vif.req_be_i    <= req.req_be;
                vif.req_we_i    <= req.req_we;

                do begin @(posedge vif.clk_i); end while (vif.req_ready_o !==1'b1); // Wait for DUT to accept request
                
                vif.req_valid_i <= 1'b0; // De-assert after one cycle
                seq_item_port.item_done();
            end
            // Thread 2: Drive Response Ready (Random Delay)
            forever begin
                int delay = $urandom_range(0, 3);
                repeat(delay) @(posedge vif.clk_i);
                vif.rsp_ready_i <= 1'b1;
                do begin @(posedge vif.clk_i); end while (vif.rsp_valid_o !== 1'b1); // Wait for DUT to assert valid
                vif.rsp_ready_i <= 1'b0; // De-assert after one cycle
            end
        join_none
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
    dmem_item pending[$];
    dmem_item curr;

    wait(vif.rst_i === 1'b0); // Chờ reset kết thúc (Active High)
    repeat (2) @(posedge vif.clk_i);

    forever begin
        @(posedge vif.clk_i);

        if (vif.rst_i) begin
            pending.delete();
        end else begin
            // 1. Bắt Request
                if (vif.req_valid_i && vif.req_ready_o) begin
                    curr = dmem_item::type_id::create("curr");
                    curr.req_addr  = vif.req_addr_i;
                    curr.req_wdata = vif.req_wdata_i;
                    curr.req_be    = vif.req_be_i;
                    curr.req_we    = vif.req_we_i;
                    pending.push_back(curr);
                end
            // 2. Bắt Response
            if (vif.rsp_valid_o && vif.rsp_ready_i && pending.size() > 0) begin
                dmem_item done = pending.pop_front();
                done.rsp_rdata = vif.rsp_rdata_o;
                mon_port.write(done);
            end
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
    int cnt_pass = 0, cnt_fail = 0;

    // 4.Constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
        scb_export = new("scb_export", this);
        endfunction

    // 5. Function write - 
    // Đây là nơi xử lý logic so sánh chính
    function void write(dmem_item trans);
	    bit [31:0] exp_data;
	    int word_idx;
	    word_idx	=	trans.req_addr >> 2;
	    // XỬ LÝ LỆNH GHI (WRITE)
            if (trans.req_we) begin
                if (!ref_mem.exists(word_idx)) ref_mem[word_idx] = 32'h0; // Khởi tạo nếu chưa có
                
                if (trans.req_be[0]) ref_mem[word_idx][7:0]   = trans.req_wdata[7:0];
                if (trans.req_be[1]) ref_mem[word_idx][15:8]  = trans.req_wdata[15:8];
                if (trans.req_be[2]) ref_mem[word_idx][23:16] = trans.req_wdata[23:16];
                if (trans.req_be[3]) ref_mem[word_idx][31:24] = trans.req_wdata[31:24];
                
                // Ghi không sinh ra dữ liệu trả về đáng kể, ta có thể bỏ qua check Read Data
                cnt_pass++; 
            end 
            // XỬ LÝ LỆNH ĐỌC (READ)
            else begin
                exp_data = ref_mem.exists(word_idx) ? ref_mem[word_idx] : 32'h0;
                
                if (trans.rsp_rdata !== exp_data) begin
                    cnt_fail++;
                    `uvm_error("FAIL", $sformatf("Addr:%0h | ACT:%0h | EXP:%0h", trans.req_addr, trans.rsp_rdata, exp_data))
                end else begin
                    cnt_pass++;
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            $display("\n======================================");
            $display("         DMEM SCOREBOARD REPORT       ");
            $display("======================================");
            $display(" Pass: %0d | Fail: %0d", cnt_pass, cnt_fail);
            if (cnt_fail == 0 && cnt_pass > 0) $display(" >>> STATUS: [PASSED] <<<");
            else $display(" >>> STATUS: [FAILED] <<<");
            $display("======================================\n");
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
        repeat(50000) begin // Test 2000 gói tin
            req = dmem_item::type_id::create("req");
            start_item(req);

                // --- MANUAL RANDOMIZATION CHỐNG LỖI LICENSE ---
                // 1. Địa chỉ: Random từ 0 -> 1023, dịch trái 2 bit để luôn chia hết cho 4
                req.req_addr = $urandom_range(0, 1023) << 2; 
                
                // 2. Data: Random full 32-bit
                req.req_wdata = $urandom(); 
                
                // 3. Write Enable: 0 (Đọc) hoặc 1 (Ghi)
                req.req_we = $urandom_range(0, 1); 
                
                // 4. Byte Enable: Bốc ngẫu nhiên 1 trong 7 trường hợp hợp lệ
                req.req_be = valid_be_list[$urandom_range(0, 6)]; 
                
                // 5. Trễ Pipeline (0 -> 3 chu kỳ)
                req.req_delay       = $urandom_range(0, 3);
                req.rsp_ready_delay = $urandom_range(0, 3);

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
        #200;
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
    dmem  #(
        .MEM_SIZE(4096)
    )dut(
        .clk_i       (clk),
        .rst_i       (vif.rst_i),
        .req_valid_i (vif.req_valid_i),
        .req_ready_o (vif.req_ready_o),
        .req_addr_i  (vif.req_addr_i),
        .req_wdata_i (vif.req_wdata_i),
        .req_be_i    (vif.req_be_i),
        .req_we_i    (vif.req_we_i),
        .rsp_valid_o (vif.rsp_valid_o),
        .rsp_ready_i (vif.rsp_ready_i),
        .rsp_rdata_o (vif.rsp_rdata_o)
    );
    // init UVM
     initial begin
        // Đăng ký Interface vào Database ngay lập tức
        uvm_config_db#(virtual dmem_if)::set(null, "*", "vif", vif);

        // Giao quyền cho UVM tại Time = 0
        run_test("dmem_basic_test");
    end

    // Control Reset
    
    initial begin
        // Khởi tạo an toàn ban đầu
        vif.rst_i       = 1; // Bật reset
        vif.req_valid_i = 0;
        vif.rsp_ready_i = 0;
        
        // Chờ 5 nhịp Clock cho hệ thống RTL ổn định
        repeat(5) @(posedge clk);
        
        // Nhả Reset, hệ thống bắt đầu chạy thực sự
        vif.rst_i = 0; 
    end
   // Dump sóng
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end


    /* initial begin
        $display("\n======================================================================================================");
        $display("   Time   | Rst | Req V/R | Rsp V/R | WE |  BE  |    Addr    |   WData    |   RData    |  Action  ");
        $display("----------+-----+---------+---------+----+------+------------+------------+------------+----------");

        // Format giải thích:
        // V/R = Valid / Ready (Ví dụ: 1/1 là bắt tay thành công)
        $monitor("%9t |  %b  |   %b/%b   |   %b/%b   |  %b | %b | 0x%h | 0x%h | 0x%h |  %s ",
                 $time,
                 vif.rst_i,
                 vif.req_valid_i, vif.req_ready_o,  // Kênh Request
                 vif.rsp_valid_o, vif.rsp_ready_i,  // Kênh Response
                 vif.req_we_i,
                 vif.req_be_i,
                 vif.req_addr_i,
                 vif.req_wdata_i,
                 vif.rsp_rdata_o,
                 // Logic phán đoán trạng thái (Bọc ngoặc tròn tổng để chống lỗi cú pháp):
                 ( (vif.req_valid_i && vif.req_we_i)  ? "WRITE " :
                   (vif.req_valid_i && !vif.req_we_i) ? "READ  " : 
                   (vif.rsp_valid_o)                  ? "RSP_OK" : "IDLE  " )
        );
    end */
endmodule
