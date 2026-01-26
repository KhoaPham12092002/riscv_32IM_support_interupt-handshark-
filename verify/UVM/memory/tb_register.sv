import uvm_pkg::* ;
`include "uvm_macros.svh"

// INTERFACE 
interface reg_if ( input logic clk_i );
    logic        rst_i;        
    
    // (Write Port) - From Write Back (WB)
    logic        w_ena_i;       
    logic [4:0]  w_address_i;   
    logic [31:0] w_data;      

    // (Read Ports) - Output data immediately to Execute (EX)
    logic [4:0]  r1_address_i;  
    logic [31:0] r1_data_o;  

    logic [4:0]  r2_address_i; 
    logic [31:0] r2_data_o;   
endinterface



// SEQUENCE ITEM# ** Error: ** while parsing macro expansion: 'uvm_field_int' starting at /home/key/workspace/project2/project_2/verify/UVM/memory/tb_register.sv(51)
class reg_item extends uvm_sequence_item;
	// Input
	rand bit [4:0]	r1_address_i	;
	rand bit [4:0]	r2_address_i	;
	rand bit [4:0]	w_address_i	;
	rand bit [31:0]	w_data		;
	rand bit w_ena_i		;
	// Output
	bit [31:0] 	r1_data_o	;
	bit [31:0]	r2_data_o	;
	
	// This func to print,copy,compare value of variable
	// `uvm_object_utils_begin(reg_item) :It registers your class with the factory and automates common methods for your variables
	// `uvm_fiel_int([name],flag|flag or empty) :It adds this specific variable to the automation list.
	// Flag :
	// UVM_NOCOMPARE :use for variable not important or alway change(time,)
	// UVM_NOPRINT : use for long name or don`t need watch
	// UVM_NOCOPY : use for variable only use in 1 project 
	// UVM_HEX,UVM_DEC, UVM_BIN, UVM_OCT, UVM_STRING : use type data print
	// FOR INPUT 
	`uvm_object_utils_begin(reg_item)
	`uvm_field_int(r1_address_i,	UVM_ALL_ON | UVM_HEX)	
	`uvm_field_int(r2_address_i,	UVM_ALL_ON | UVM_HEX)
	`uvm_field_int(w_address_i,    	UVM_ALL_ON | UVM_HEX)
	`uvm_field_int(w_data,    	UVM_ALL_ON | UVM_BIN)
	`uvm_field_int(w_ena_i,    	UVM_ALL_ON | UVM_HEX)
	// FOR OUTPUT
	`uvm_field_int(r1_data_o,    UVM_ALL_ON | UVM_HEX)
	`uvm_field_int(r2_data_o,    UVM_ALL_ON | UVM_HEX)
	`uvm_object_utils_end
	constraint basic_c {}
function new(string name = "reg_item");
		super.new(name);
	endfunction
endclass

// DRIVER
class reg_driver extends uvm_driver #(reg_item);
	`uvm_component_utils(reg_driver)
	virtual reg_if vif;
	function new( string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		if (!uvm_config_db#(virtual reg_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "No Interface Found!")
	endfunction
	task run_phase(uvm_phase phase);
		forever begin 
			seq_item_port.get_next_item(req);
			@(posedge vif.clk_i);
			vif.rst_i         <= 0; // Đảm bảo không reset khi đang chạy
        		vif.w_ena_i       <= req.w_ena_i;
        		vif.w_address_i   <= req.w_address_i;
        		vif.w_data        <= req.w_data;
        
       			vif.r1_address_i  <= req.r1_address_i;
        		vif.r2_address_i  <= req.r2_address_i;
			@(posedge vif.clk_i);
			// notice done
			seq_item_port.item_done();
		end
	endtask
endclass
// MONITOR
class reg_monitor extends uvm_monitor;
	`uvm_component_utils(reg_monitor)
	virtual reg_if vif;
	uvm_analysis_port #(reg_item) mon_port;
	
	function new(string name, uvm_component parent);
		super.new(name,parent);
		mon_port = new("mon_port", this);
	endfunction

	// get interface 
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Lấy virtual interface từ config_db
        if (!uvm_config_db#(virtual reg_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON", "Không thể lấy vif! Kiểm tra lại lệnh set ở tb_top.")
        end
    endfunction
	task run_phase(uvm_phase phase);
    reg_item item;
    forever begin
        @(posedge vif.clk_i);
        // Chờ 1 chút (1ns) để tín hiệu ổn định rồi mới bắt
        #1; 
        
        // Tạo gói tin mới
        item = reg_item::type_id::create("item");

        // NỐI DÂY NGƯỢC LẠI
        // Bên TRÁI là Class (Dữ liệu) = Bên PHẢI là Interface (Dây cứng)
        
        // Bắt Input (để biết Driver vừa lái cái gì)
        item.w_ena_i      = vif.w_ena_i;
        item.w_address_i  = vif.w_address_i;
        item.w_data       = vif.w_data;
        item.r1_address_i = vif.r1_address_i;
        item.r2_address_i = vif.r2_address_i;

        // Bắt Output (Kết quả trả về từ Register File)
        // Lưu ý: Register File thường là Read Async (bất đồng bộ)
        // Nên có địa chỉ là có data ngay, bắt luôn được.
        item.r1_data_o    = vif.r1_data_o;
        item.r2_data_o    = vif.r2_data_o;

        // Gửi về Scoreboard
        mon_port.write(item);
    end
endtask
endclass

// SCOREBOARD 
class reg_scoreboard extends uvm_scoreboard;
    // 1. Đăng ký với Factory (Đây là Component)
    `uvm_component_utils(reg_scoreboard)

    // 2. Cổng nhận dữ liệu từ Monitor
    // Cú pháp: uvm_analysis_imp #(LOẠI_GÓI_TIN, TÊN_CLASS_HIỆN_TẠI)
    uvm_analysis_imp #(reg_item, reg_scoreboard) scb_export;

    // 3. Mô hình tham chiếu (Reference Model)
    // Mảng lưu trữ 32 thanh ghi, mỗi thanh 32-bit
    bit [31:0] ref_regs [32];

    // 4. Hàm khởi tạo (Constructor)
    function new(string name, uvm_component parent);
        super.new(name, parent);
        scb_export = new("scb_export", this);
        
        // Khởi tạo tất cả thanh ghi về 0
        foreach(ref_regs[i]) begin
            ref_regs[i] = 0;
        end
    endfunction

    // 5. Hàm write - Được gọi tự động khi Monitor gửi gói tin sang
    // Đây là nơi xử lý logic so sánh chính
    function void write(reg_item item);
        bit [31:0] exp_r1_data;
        bit [31:0] exp_r2_data;

        // ---------------------------------------------------------
        // BƯỚC A: KIỂM TRA DỮ LIỆU ĐỌC (READ CHECK)
        // Logic: So sánh dữ liệu DUT trả về (Output) với Reference Model
        // ---------------------------------------------------------

        // --- Kiểm tra Cổng đọc 1 (Read Port 1) ---
        if (item.r1_address_i == 0) begin
            exp_r1_data = 0; // Thanh ghi x0 luôn bằng 0
        end else begin
            exp_r1_data = ref_regs[item.r1_address_i];
        end

        if (item.r1_data_o !== exp_r1_data) begin
            `uvm_error("SCB", $sformatf("Read Port 1 Mismatch! Addr: %0d | DUT: %h | EXP: %h", 
                                        item.r1_address_i, item.r1_data_o, exp_r1_data))
        end else begin
            `uvm_info("SCB", $sformatf("Read Port 1 PASS: Addr %0d = %h", 
                                       item.r1_address_i, item.r1_data_o), UVM_HIGH)
        end

        // --- Kiểm tra Cổng đọc 2 (Read Port 2) ---
        if (item.r2_address_i == 0) begin
            exp_r2_data = 0; // Thanh ghi x0 luôn bằng 0
        end else begin
            exp_r2_data = ref_regs[item.r2_address_i];
        end

        if (item.r2_data_o !== exp_r2_data) begin
            `uvm_error("SCB", $sformatf("Read Port 2 Mismatch! Addr: %0d | DUT: %h | EXP: %h", 
                                        item.r2_address_i, item.r2_data_o, exp_r2_data))
        end else begin
            `uvm_info("SCB", $sformatf("Read Port 2 PASS: Addr %0d = %h", 
                                       item.r2_address_i, item.r2_data_o), UVM_HIGH)
        end

        // ---------------------------------------------------------
        // BƯỚC B: CẬP NHẬT DỮ LIỆU GHI (WRITE UPDATE)
        // Logic: Cập nhật Reference Model để chuẩn bị cho chu kỳ sau
        // ---------------------------------------------------------
        
        // Điều kiện ghi: Write Enable = 1 VÀ Địa chỉ ghi khác 0
        if (item.w_ena_i == 1 && item.w_address_i != 0) begin
            
            // Cập nhật giá trị vào mảng tham chiếu
            ref_regs[item.w_address_i] = item.w_data;

            `uvm_info("SCB", $sformatf("Update Model: Wrote %h into Reg[%0d]", 
                                       item.w_data, item.w_address_i), UVM_HIGH)
        end
        // Lưu ý: Nếu ghi vào địa chỉ 0, ta KHÔNG làm gì cả (để ref_regs[0] luôn giữ là 0)

        if (item.r1_data_o == exp_r1_data) begin
        `uvm_info("SCB", $sformatf("PASS! Addr:%0h | Exp:%0h | Act:%0h", item.r1_address_i, exp_r1_data, item.r1_data_o), UVM_LOW)
    end else begin
        `uvm_error("SCB", $sformatf("FAIL! Addr:%0h | Exp:%0h | Act:%0h", item.r1_address_i, exp_r1_data, item.r1_data_o))
    end
    endfunction

    
endclass

    // ---------------------------------------------------------
    // 5. AGENT & ENV (Bộ khung chứa các thành phần trên)
    // ---------------------------------------------------------
    class reg_agent extends uvm_agent;
        `uvm_component_utils(reg_agent)
        reg_driver    driver;
        reg_monitor   monitor;
        uvm_sequencer #(reg_item) sequencer;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = reg_driver::type_id::create("driver", this);
            monitor   = reg_monitor::type_id::create("monitor", this);
            sequencer = uvm_sequencer#(reg_item)::type_id::create("sequencer", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class reg_env extends uvm_env;
        `uvm_component_utils(reg_env)
        reg_agent      agent;
        reg_scoreboard scb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = reg_agent::type_id::create("agent", this);
            scb   = reg_scoreboard::type_id::create("scb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
       		super.connect_phase(phase);
		agent.monitor.mon_port.connect(scb.scb_export);
        endfunction
    endclass

    // ---------------------------------------------------------
    // 6. TEST (Kịch bản kiểm tra)
    // ---------------------------------------------------------
    class reg_basic_test extends uvm_test;
        `uvm_component_utils(reg_basic_test)
        reg_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = reg_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            reg_item item;
            phase.raise_objection(this);

            // Tạo 1000 giao dịch ngẫu nhiên
            repeat(5000) begin
                item = reg_item::type_id::create("item");
                item.r1_address_i = $urandom_range(0, 31);
		item.r2_address_i = $urandom_range(0, 31);
		item.w_ena_i = $urandom_range(0, 1);
		item.w_address_i = $urandom_range(0, 31);
		item.w_data = $urandom();
        `uvm_info("TEST", $sformatf("Sending item: W_Addr=%0h, W_Data=%0h", item.w_address_i, item.w_data), UVM_LOW)
		env.agent.sequencer.execute_item(item); // Gửi item xuống Driver
            end

            #300;
            phase.drop_objection(this);
        endtask
    	endclass


module tb_top;
import uvm_pkg::*;
`include "uvm_macros.svh"
    logic clk;

    // Tạo Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Instance Interface
    reg_if vif(clk);

    // Instance DUT (Device Under Test)
    register  dut (// 1. Clock & Reset
        .clk_i          (clk),           // Nối với biến clk của tb_top
        .rst_i         (vif.rst_i),     // Nối với dây rst trong interface (Lưu ý: Check xem RTL là rst_i hay rst_ni)

        // 2. Write Port (Cổng ghi)
        .w_ena_i        (vif.w_ena_i),
        .w_address_i    (vif.w_address_i),
        .w_data       (vif.w_data),    // RTL thường có đuôi _i, Interface của bạn đặt là w_data

        // 3. Read Port 1 (Cổng đọc 1)
        .r1_address_i   (vif.r1_address_i),
       	.r1_data_o      (vif.r1_data_o),

        // 4. Read Port 2 (Cổng đọc 2)
        .r2_address_i   (vif.r2_address_i),
        .r2_data_o      (vif.r2_data_o)
    );
        

    // Block khởi chạy UVM
    initial begin
        // 1. Khởi tạo giá trị mặc định an toàn (Để tránh trôi nổi - Z)
        // QUAN TRỌNG: Phải tắt Write Enable ngay lập tức!
        vif.w_ena_i = 0; 
        
        // Các tín hiệu khác gán 0 cho sạch đẹp
        vif.w_address_i  = 0;
        vif.r1_address_i = 0;
        vif.r2_address_i = 0;
        vif.w_data       = 0;

        // 2. Thực hiện RESET (Giả sử Active High như code bạn gửi)
        vif.rst_i = 1;   // Giữ nút Reset
        #20;             // Giữ trong 20ns
        vif.rst_i = 0;   // Thả nút Reset ra -> Chip bắt đầu chạy
    end
        // Đăng ký Interface vào Config DB để Driver/Monitor tìm thấy
        initial begin
        uvm_config_db#(virtual reg_if)::set(null, "*", "vif", vif);

        // Chạy Test
        run_test("imem_basic_test");
    end
initial begin
        // In tiêu đề cột (Kéo dài ra để đủ chỗ cho 3 cổng)
        $display("----------------------------------------------------------------------------------------------------");
        $display("Time  | Rst | WE | W_Addr |   W_Data   || R1_Addr |   R1_Data  || R2_Addr |   R2_Data  ");
        $display("------+-----+----+--------+------------++---------+------------++---------+------------");

        // Format:
        // %t : Thời gian
        // %b : Bit (0/1)
        // %2d: Số thập phân 2 chữ số (Cho địa chỉ 0-31 nhìn cho gọn)
        // %h : Hex (Cho dữ liệu 32-bit)
        $monitor("%5t |  %b  |  %b |   %2d   |  %h  ||   %2d    |  %h  ||   %2d    |  %h",
                 $time, 
                 vif.rst_i,        // Reset
                 vif.w_ena_i,      // Write Enable
                 
                 vif.w_address_i,  // Cổng Ghi
                 vif.w_data,
                 
                 vif.r1_address_i, // Cổng Đọc 1
                 vif.r1_data_o,
                 
                 vif.r2_address_i, // Cổng Đọc 2
                 vif.r2_data_o
                 );
    end
    endmodule
		       
	
	

