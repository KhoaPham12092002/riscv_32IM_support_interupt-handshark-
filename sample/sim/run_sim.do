# --- Cấu hình đường dẫn (Relative Paths) ---
set SUB_PATH    "../src//" # link to path
set TB_PATH     "../verif/tb" #link to testbench

# 1. Khởi tạo thư viện work (Xóa cũ tạo mới để đảm bảo sạch sẽ)
if [file exists work] {
    vdel -all
}
vlib work
vmap work work

# 2. Biên dịch các file 

# Biên dịch rtl
vlog -sv $SUB_PATH/ / # write the link to file need test
# Biên dịch Testbench tương ứng
vlog -sv $TB_PATH/ / # write the link to file testbench

# 3. Nạp mô phỏng
# -voptargs="+acc" cho phép bạn xem mọi tín hiệu bên trong 
vsim -voptargs="+acc" work.[name testbench] # before run remenber ti rewrite the name of test bench

# 4. Thêm sóng (Waveform)
add wave -divider "INPUTS"
#add wave sim:/[name testbench]/signal
#example: add wave sim:/tb_add_sub/b

add wave -divider "OUTPUTS"
# add wave -color Yellow sim:/tb_add_sub/sum_dif #add coler for output
# add wave -color Cyan   sim:/tb_add_sub/C
# add wave -color Red    sim:/tb_add_sub/V

# Thêm tín hiệu bên trong khối 
#add wave -divider "INTERNAL CLA LOGIC"
#add wave sim:/tb_add_sub/dut/cin
#add wave sim:/tb_add_sub/dut/C_blk

# 5. Chạy mô phỏng
run -all

# Tự động zoom toàn bộ kết quả
wave zoom full