module register (
    input  logic        clk_i,
    input  logic        rst_i,         
    
    // (Write Port) - From Write Back (WB)
    input  logic        w_ena_i,       
    input  logic [4:0]  w_addr_i,   
    input  logic [31:0] w_data_i_i,      

    // (Read Ports) - Output data immediately to Execute (EX)
    input  logic [4:0]  r1_addr_i,  
    output logic [31:0] r1_data_o,     
    
    input  logic [4:0]  r2_addr_i,  
    output logic [31:0] r2_data_o      
);
module dmem #(
    parameter int MEM_SIZE = riscv_32im_pkg::DMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,      // Active High Reset (1 = Reset)
    // hand shark interface
    input  logic valid_i,
    output logic ready_o,
    input  logic ready_i,
    output logic valid_o,
    // --- Native Interface ---
    input  logic        we_i,       // Write Enable (1 = Write, 0 = Read)
    input  logic [3:0]  be_i,       // Byte Enable (Mask cho SB, SH, SW)
    input  logic [31:0] addr_i,     // Address
    input  logic [31:0] wdata_i,    // Write Data
    output logic [31:0] rdata_o     // Read Data
);
module imem #(
    parameter string HEX_FILE = "program.hex",
    parameter int    MEM_SIZE = riscv_32im_pkg::IMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,     // Active high Reset
    // --- hand shark Interface ---
    input   logic valid_i,
    output  logic valid_o,
    input   logic ready_i,
    output  logic ready_o,
    // --- Native Interface ---
    input   logic [31:0] addr_i,     // Address
    output  logic [31:0] instr_o     // Instruction Data
);
module alu (
    input  alu_in_t         alu_in,
    output logic Zero,
    output logic  [31:0]      alu_o,
    output logic        vaild_o,
    output logic        ready_o
    );
module riscv_m_unit (
    input  logic         clk,
    input  logic         rst,

    // --- Upstream Interface ---
    input  logic         valid_i,
    output logic         ready_o,
    input  m_in_t        m_in,

    // --- Downstream Interface ---
    output logic         valid_o,
    input  logic         ready_i,
    output logic [31:0]  result_o
);
module decoder 

(
    input logic [31:0]        instr_i,
    output dec_out_t          ctrl_o,   
    output logic [31:0]        imm_o,
    output logic [4:0]       rd_addr_o,
    output logic [4:0]       rs1_addr_o,
    output logic [4:0]       rs2_addr_o
    // Upstream (Nhận từ IF/ID Pipeline Reg)
    input  logic        valid_i, 
    output logic        ready_o,
    
    // Downstream (Gửi tới ID/EX Pipeline Reg)
    output logic        valid_o,
    input  logic        ready_i
);
module lsu (
    input  logic        clk_i,
    input  logic        rst_i,

    // Interface with Core
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic        lsu_we_i,    // 1 = Store
    input  logic [2:0]  funct3_i,    // Data type (LB, SB, etc.)
    // Interface handshark
    input  logic        valid_i,
    output logic        ready_o,
    output logic        valid_o,
    input  logic        ready_i ,
    // Interface with DMEM
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    input  logic [31:0] dmem_rdata_i,

    // Writeback to Core (Load Data)
    output logic [31:0] lsu_rdata_o,
    
   // Output for trap 
    output logic lsu_err_o  

);
module pc_gen (
    input  logic        clk_i,
    input  logic        rst_i,

    // --- Handshake Interface (Back-pressure) ---
    // ready_i = 1: Hệ thống (IMEM + Pipeline) sẵn sàng nhận lệnh mới.
    // ready_i = 0: Pipeline bị Stall (Tắc), PC phải đứng im.
    input  logic        ready_i,    
    output logic        valid_o,    // Luôn = 1 (PC Gen luôn muốn lấy lệnh)

    // --- Branch Interface (From EX Stage) ---
    input  logic        branch_taken_i,       // 1 = Lệnh nhảy thực thi thành công
    input  logic [31:0] branch_target_addr_i, // Địa chỉ đích của lệnh nhảy

    // --- Trap/Interrupt Interface (Placeholder for Future) ---
    // Mở comment phần này khi em làm xong CSR/Controller
    /*
    input  logic        trap_taken_i,         // 1 = Có ngắt hoặc ngoại lệ (Trap/Interrupt)
    input  logic [31:0] trap_target_addr_i,   // Địa chỉ vector ngắt (mtvec)
    */

    // --- Output PC ---
    output logic [31:0] pc_o
);
module pipeline_reg (
    input  logic    clk_i,
    input  logic    rst_i,

    // --- Control Interface ---
    input  logic    flush_i,      // Xóa pipeline khi Branch sai (Synchronous Reset)
    
    // --- Upstream (Input) ---
    input  logic    valid_i,      // Data đầu vào hợp lệ
    output logic    ready_o,      // Báo cho tầng trước: Tao sẵn sàng
    input  T_DATA   data_i,       // Dữ liệu đầu vào

    // --- Downstream (Output) ---
    output logic    valid_o,      // Data đầu ra hợp lệ
    input  logic    ready_i,      // Tầng sau báo: Tao sẵn sàng nhận
    output T_DATA   data_o        // Dữ liệu đầu ra
);