# 1. SETUP PATH
set UVM_HOME "/home/key/tool/questa_fse/verilog_src/uvm-1.2"

# 2. CREATE LIBRARY
if {[file exists work]} { vdel -lib work -all }
vlib work

# 3. COMPILE UVM Pkg & DPI (ĐÃ SỬA LỖI C++)
# -ccflags "-DQUESTA": Truyền định nghĩa QUESTA vào cho trình biên dịch C++
echo "--- Compiling UVM Pkg & DPI ---"
vlog -sv +incdir+$UVM_HOME/src +define+QUESTA -ccflags "-DQUESTA -Wno-missing-declarations" \
    $UVM_HOME/src/uvm_pkg.sv \
    $UVM_HOME/src/dpi/uvm_dpi.cc 

# 4. COMPILE DESIGN & TB
echo "--- Compiling Design ---"
vlog -sv +incdir+$UVM_HOME/src \
    decoder_pkg.sv \
    riscv_instr.sv \
    decoder.sv \
    tb_decoder_top.sv

# 5. START SIMULATION
echo "--- Loading Simulation ---"
# -c: Chạy console
vsim -c -voptargs=+acc -L work tb_decoder_top +UVM_TESTNAME=decoder_full_test

# 6. RUN
run -all

