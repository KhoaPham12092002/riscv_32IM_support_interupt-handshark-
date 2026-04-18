# Cấu hình
VERILATOR = verilator
# LINT_FLAGS = --lint-only -Wall --timing
LINT_FLAGS = --lint-only -Wall --timing -Wno-fatal -Wno-EOFNEWLINE -Wno-DECLFILENAME -Wno-IMPORTSTAR -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD
# Khai báo tên module top
TOP_MODULE = riscv_datapath


# Tìm tất cả các file .v và .sv trong thư mục rtl
RTL_DIR = ./src
SRCS = $(shell find $(RTL_DIR) -name "*.sv" -or -name "*.v")

# Link Package (Lưu ý: Package luôn phải đứng trước SRCS)
PKG = ./package/riscv_32im_pkg.sv ./package/riscv_instr.sv

# Target chính
lint:
	$(VERILATOR) $(LINT_FLAGS) $(PKG) $(SRCS) --top-module $(TOP_MODULE)

# Bỏ qua một số cảnh báo cụ thể (đã bổ sung $(PKG) vào đây)
lint_quiet:
	$(VERILATOR) $(LINT_FLAGS) -Wno-UNUSED -Wno-UNDRIVEN $(PKG) $(SRCS) --top-module $(TOP_MODULE)

.PHONY: lint lint_quiet
