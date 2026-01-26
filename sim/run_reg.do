# ==========================================================================
# QUESTA/MODELSIM TCL SCRIPT (FIXED -NOVOPT ERROR)
# Execute: vsim -c -do run_reg.do
# ==========================================================================

# 1. SETUP PATHS
set PROJ_ROOT "/home/key/workspace/project2/project_2"
set SRC_DIR   "$PROJ_ROOT/src/memory"
set VERIF_DIR "$PROJ_ROOT/verify/UVM/memory"

# 2. CLEANUP & INIT LIBRARY
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work


# 4. COMPILE (vlog)
# --------------------------------------------------------------------------
# Thêm tham số -O0 (Optimize level 0) để compile nhanh hơn cho debug
puts "\[SCRIPT\] Compiling..."

vlog -sv -timescale "1ns/1ps" \
    +incdir+$SRC_DIR \
    +incdir+$VERIF_DIR \
    -suppress 2181 \
    $SRC_DIR/register.sv \
    $VERIF_DIR/tb_register.sv

# Check xem compile có lỗi không
if {[string match "*Error*" $errorCode]} {
    puts "\[ERROR\] Compilation Failed"
    quit -f
}

# 5. OPTIMIZE & LOAD SIMULATION (vsim)
# --------------------------------------------------------------------------
# QUAN TRỌNG: 
# - Thay vì dùng -novopt (đã bị bỏ), ta dùng -voptargs=+acc
# -voptargs=+acc : Giữ lại visibility của signal để debug/dump wave
puts "\[SCRIPT\] Loading Simulation..."

vsim -voptargs=+acc \
     -sv_seed random \
     +UVM_TESTNAME=reg_basic_test \
     tb_top

# 6. RUN
# --------------------------------------------------------------------------
puts "\[SCRIPT\] Running..."
run -all

# 7. QUIT
quit -f

