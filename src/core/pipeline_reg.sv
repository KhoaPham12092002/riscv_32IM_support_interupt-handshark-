import riscv_32im_pkg::*;
module pipeline_reg #(
    parameter int WIDTH = 32 // Dùng tham số số nguyên thay vì type
)(
    input  logic             clk_i,
    input  logic             rst_i,

    // --- Control Interface ---
    input  logic             flush_i,      
    
    // --- Upstream (Input) ---
    input  logic             valid_i,      
    output logic             ready_o,      
    input  logic [WIDTH-1:0] data_i,       // Ép kiểu vector dựa trên WIDTH

    // --- Downstream (Output) ---
    output logic             valid_o,      
    input  logic             ready_i,      
    output logic [WIDTH-1:0] data_o        
);
    // Trạng thái của thanh ghi: Full (có dữ liệu) hoặc Empty
    logic full_q; 

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            full_q <= 1'b0;
            data_o <= '0;
        end else if (flush_i) begin
            // Khi flush, coi như thanh ghi rỗng (valid_o sẽ xuống 0)
            full_q <= 1'b0; 
            // Optional: data_o <= '0; // Không cần thiết, chỉ cần valid xuống thấp là an toàn
        end else begin
            // Logic Handshake:
            // Chúng ta nhận dữ liệu mới khi:
            // 1. Tầng trước có data (valid_i)
            // 2. VÀ (Thanh ghi đang trống HOẶC Tầng sau đã nhận data cũ rồi)
            if (valid_i && ready_o) begin
                data_o <= data_i;
                full_q <= 1'b1;
            end 
            // Nếu tầng sau nhận dữ liệu (ready_i) nhưng không có data mới nạp vào -> Rỗng
            else if (ready_i && full_q) begin
                full_q <= 1'b0;
            end
        end
    end

    // Output Valid: Data chỉ hợp lệ khi thanh ghi đang Full
    assign valid_o = full_q;

    // Ready Output: Chúng ta sẵn sàng nhận data mới khi:
    // Thanh ghi chưa đầy (Empty) HOẶC Tầng sau đang sẵn sàng lấy data đi (nghĩa là data cũ sẽ đi ngay lập tức)
    assign ready_o = (~full_q) || ready_i;

endmodule