`timescale 1ns/1ps
import alu_types_pkg::*; 
import decoder_pkg::*;   
import memory_pkg::*;    

module soc_top (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] interrupts, // Đã thêm cổng này
    output logic [31:0] gpio_out    // Đã đổi tên chuẩn (bỏ dummy)
);

    logic [31:0] cpu_i_addr;
    logic [31:0] cpu_i_data;
    
    logic [31:0] cpu_d_addr;
    logic [31:0] cpu_d_data_w; 
    logic [31:0] cpu_d_data_r; 
    mem_ctrl_t   cpu_mem_ctrl; 
    dev_sel_t    current_dev_sel; 
    
    logic [31:0] rdata_imem;   
    logic [31:0] rdata_dmem;   
    logic [31:0] rdata_periph; 
    logic [31:0] rdata_sdram;  
    logic [3:0]  cpu_byte_mask;

    // 1. Adapter Logic (Word Size -> Byte Mask)
    // Chuyển đổi tín hiệu điều khiển độ rộng nhớ thành Mask 4-bit
    always_comb begin
        cpu_byte_mask = 4'b0000;
        case (cpu_mem_ctrl.word_size)
            2'b00: cpu_byte_mask = 4'b1111; // Word
            2'b01: begin // Half-word
                if (cpu_d_addr[1]) cpu_byte_mask = 4'b1100; 
                else               cpu_byte_mask = 4'b0011; 
            end
            2'b11: begin // Byte
                case (cpu_d_addr[1:0])
                    2'b00: cpu_byte_mask = 4'b0001;
                    2'b01: cpu_byte_mask = 4'b0010;
                    2'b10: cpu_byte_mask = 4'b0100;
                    2'b11: cpu_byte_mask = 4'b1000;
                endcase
            end
            default: cpu_byte_mask = 4'b1111;
        endcase
    end

    // 2. Core Instance
    riscv_pipeline_top core (
        .clk(clk), .rst(rst), .interrupts(interrupts), 
        .i_address(cpu_i_addr), .i_data(cpu_i_data),     
        .d_address(cpu_d_addr), .d_data_w(cpu_d_data_w), .d_data_r(cpu_d_data_r), 
        .dmemory_ctrl(cpu_mem_ctrl)
    );

    // 3. Address Decoder
    address_decoder addr_dec (
        .address(cpu_d_addr), .dev_sel(current_dev_sel), .dcsel_raw()               
    );

    // 4. Instruction Memory (Behavioral)
    imemory imem_inst (
        .clk(clk), .rst(rst),
        .i_address(cpu_i_addr), .i_data(cpu_i_data),
        .d_address(cpu_d_addr), .d_read(cpu_mem_ctrl.read),
        .dcsel(current_dev_sel), .d_data_out(rdata_imem)
    );

    // 5. Data Memory (Behavioral with Byte Mask support)
    dmemory dmem_inst (
        .clk(clk), .rst(rst),
        .address(cpu_d_addr), .data(cpu_d_data_w),
        .we(cpu_mem_ctrl.write), .dcsel(current_dev_sel), 
        .dmask(cpu_byte_mask),      
        .signal_ext(cpu_mem_ctrl.signal_ext), 
        .q(rdata_dmem)
    );

    // 6. GPIO / Peripherals
    logic [31:0] gpio_reg;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) gpio_reg <= 32'b0;
        else if (cpu_mem_ctrl.write && (current_dev_sel == DEV_IO) && (cpu_d_addr[19:4] == 16'h0000)) begin
             gpio_reg <= cpu_d_data_w;
        end
    end
    assign gpio_out = gpio_reg;

    iodatabusmux io_mux (
        .daddress(cpu_d_addr),
        .ddata_r_gpio(gpio_reg), .ddata_r_periph(rdata_periph),
        .ddata_r_segments(0), .ddata_r_uart(0), .ddata_r_adc(0), .ddata_r_i2c(0),
        .ddata_r_timer(0), .ddata_r_dif_fil(0), .ddata_r_stepmot(0), .ddata_r_lcd(0),
        .ddata_r_nn_accelerator(0), .ddata_r_fir_fil(0), .ddata_r_spwm(0),
        .ddata_r_crc(0), .ddata_r_key(0), .ddata_r_accelerometer(0),
        .ddata_r_cordic(0), .ddata_r_RS485(0), .ddata_r_rgb(0)
    );

    // 7. System Mux
    assign rdata_sdram = 32'b0; 
    databusmux system_bus_mux (
        .dcsel(current_dev_sel),    
        .idata(rdata_imem),         
        .ddata_r_mem(rdata_dmem),   
        .ddata_r_periph(rdata_periph), 
        .ddata_r_sdram(rdata_sdram),   
        .ddata_r(cpu_d_data_r)      
    );

endmodule