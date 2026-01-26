import os

# ==============================================================================
# CẤU HÌNH
# ==============================================================================
# Paste mã máy (từ Venus hoặc GCC) vào đây
# Mỗi dòng là một lệnh 32-bit hex
raw_machine_code = """
00040537
00500093
00400113
022081b3
00352023
06400093
00400113
0220c1b3
00352023
00000063
"""

OUTPUT_FILE = "program.hex"

# ==============================================================================
# XỬ LÝ
# ==============================================================================
def main():
    # 1. Làm sạch dữ liệu đầu vào
    lines = raw_machine_code.strip().split('\n')
    instructions = [line.strip() for line in lines if line.strip()]

    print(f"--- Detected {len(instructions)} instructions ---")

    # 2. Ghi ra file .hex format Verilog
    try:
        with open(OUTPUT_FILE, 'w') as f:
            # Ghi Header địa chỉ bắt đầu (Memory Address 0)
            f.write("@00000000\n")
            
            for i, instr in enumerate(instructions):
                # Đảm bảo đủ 8 ký tự hex
                if len(instr) != 8:
                    print(f"Warning: Instruction {i} '{instr}' length is not 8.")
                
                f.write(f"{instr}\n")
                print(f"Addr {i*4:04X}: {instr}")
        
        print(f"\n[SUCCESS] File '{OUTPUT_FILE}' generated successfully.")
        print(f"Location: {os.path.abspath(OUTPUT_FILE)}")
        
    except IOError as e:
        print(f"[ERROR] Could not write file: {e}")

if __name__ == "__main__":
    main()