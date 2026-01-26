`timescale 1ns/1ps

package memory_pkg;

    // --- SYSTEM CONFIGURATION ---
    localparam int IMEM_SIZE_BYTES = 4096;  // 4KB
    localparam int DMEM_SIZE_BYTES = 4096;  // 4KB
    localparam int XLEN            = 32;    // Data Width (RISC-V 32-bit)

    // ========================================================================
    localparam logic [31:0] MAP_IMEM_BASE = 32'h0000_0000;
    localparam logic [31:0] MAP_IMEM_MASK = 32'hF000_0000; // Check 4 bit đầu

    // --- Data Memory (DMEM) ---
    // Mặc định: 0x2000_0000 
    localparam logic [31:0] MAP_DMEM_BASE = 32'h2000_0000;
    localparam logic [31:0] MAP_DMEM_MASK = 32'hF000_0000; 

    // --- Peripherals (IO) ---
    // Mặc định: 0x4000_0000 
    localparam logic [31:0] MAP_IO_BASE   = 32'h4000_0000;
    localparam logic [31:0] MAP_IO_MASK   = 32'hF000_0000;

    // --- SDRAM (External) ---
    // Mặc định: 0x6000_0000
    localparam logic [31:0] MAP_SDRAM_BASE = 32'h6000_0000;
    localparam logic [31:0] MAP_SDRAM_MASK = 32'hF000_0000;

    // ========================================================================
    //  DEVICE SELECTION TYPES
    // ========================================================================
    // Enum đại diện cho các chip select (dcsel)
    typedef enum logic [1:0] {
        DEV_IMEM   = 2'b00,
        DEV_DMEM   = 2'b01,
        DEV_IO     = 2'b10,
        DEV_SDRAM  = 2'b11,
        DEV_NONE   = 2'bxx // Trạng thái lỗi hoặc không chọn gì
    } dev_sel_t;
    // ========================================================================
    // 3. PERIPHERAL ADDRESS MAP (IO LEVEL) - [PHẦN BẠN ĐANG THIẾU]
    // ========================================================================
    typedef enum logic [15:0] {
        ADDR_GPIO           = 16'h0000,
        ADDR_SEGMENTS       = 16'h0001,
        ADDR_UART           = 16'h0002,
        ADDR_ADC            = 16'h0003,
        ADDR_I2C            = 16'h0004,
        ADDR_TIMER          = 16'h0005,
        
        ADDR_DIF_FIL        = 16'h0008,
        ADDR_STEP_MOT       = 16'h0009,
        ADDR_LCD            = 16'h000A,
        ADDR_NN_ACCEL       = 16'h000B,
        
        ADDR_FIR_FIL        = 16'h000D,
        ADDR_KEY            = 16'h000E,
        ADDR_CRC            = 16'h000F,
        
        ADDR_SPWM           = 16'h0011,
        ADDR_ACCEL          = 16'h0012,
        ADDR_CORDIC         = 16'h0015,
        ADDR_RS485          = 16'h0017,
        ADDR_RGB            = 16'h0020,
        
        ADDR_UNKNOWN        = 16'hxxxx // Cho các trường hợp default
    } periph_addr_t;
    // ========================================================================
    //  SMART DECODING FUNCTION (LOGIC TỰ ĐỘNG)
    // ========================================================================
    // Hàm này sẽ tự động tính toán dựa trên các tham số ở phần 1.
    // Bạn KHÔNG cần sửa hàm này khi thay đổi địa chỉ.
    
    function automatic dev_sel_t decode_address(input logic [31:0] addr);
        // Logic so khớp: (Addr AND Mask) == Base
        
        if ((addr & MAP_IMEM_MASK) == MAP_IMEM_BASE) 
            return DEV_IMEM;
            
        else if ((addr & MAP_DMEM_MASK) == MAP_DMEM_BASE) 
            return DEV_DMEM;
            
        else if ((addr & MAP_IO_MASK) == MAP_IO_BASE) 
            return DEV_IO;
            
        else if ((addr & MAP_SDRAM_MASK) == MAP_SDRAM_BASE) 
            return DEV_SDRAM;
            
        else 
            return DEV_NONE;
    endfunction

endpackage

