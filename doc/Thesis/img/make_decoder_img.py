#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import textwrap

TEXT = """
==================================================
   DECODER VERIFICATION REPORT (GOLDEN MODEL)
==================================================
Total Instructions Tested: 50000
Passed Correctly         : 50000
Failed (Errors)          : 0
--------------------------------------------------
>>> FAILURES BREAKDOWN BY INSTRUCTION <<<
  [+] NONE! All instructions perfectly decoded.
--------------------------------------------------
INSTRUCTION COVERAGE:
  ADD    :  882    ADDI   :  851    AND    :  883
  ANDI   :  800    AUIPC  :  844    BEQ    :  826
  BGE    :  854    BGEU   :  803    BLT    :  851
  BLTU   :  817    BNE    :  840    CSRRC  :  824
  CSRRCI : 1624    CSRRS  :  884    CSRRSI : 1633
  CSRRW  :  828    CSRRWI : 1650    DIV    :  827
  DIVU   :  903    EBREAK :  829    ECALL  :  837
  JAL    :  874    JALR   :  873    LB     :  885
  LBU    :  791    LH     :  799    LHU    :  890
  LUI    :  886    LW     :  818    MRET   :  817
  MUL    :  826    MULH   :  799    MULHSU :  806
  MULHU  :  859    OR     :  831    ORI    :  852
  REM    :  809    REMU   :  814    SB     :  920
  SH     :  821    SLL    :  896    SLLI   :  844
  SLT    :  798    SLTI   :  810    SLTIU  :  798
  SLTU   :  851    SRA    :  835    SRAI   :  806
  SRL    :  829    SRLI   :  805    SUB    :  871
  SW     :  813    XOR    :  806    XORI   :  806
  ILLEGAL/JUNK : 2372
==================================================
>>> PERFECT DECODING! READY FOR TAPE-OUT <<<
  UVM_ERROR : 0     UVM_FATAL : 0
==================================================
""".strip()

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_SIZE  = 18
PAD        = 32
BG_COLOR   = (255, 255, 255)
FG_COLOR   = (20,  20,  20)
HL_COLOR   = (0,   100, 0)    # xanh lá cho dòng PASS/PERFECT

try:
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
except:
    font = ImageFont.load_default()

lines = TEXT.split('\n')

# Đo kích thước
dummy = Image.new('RGB', (1, 1))
draw  = ImageDraw.Draw(dummy)
bbox  = draw.textbbox((0, 0), "W", font=font)
char_h = bbox[3] - bbox[1] + 4

max_w = max(draw.textbbox((0,0), l, font=font)[2] for l in lines)
img_w = max_w + PAD * 2
img_h = char_h * len(lines) + PAD * 2

img  = Image.new('RGB', (img_w, img_h), BG_COLOR)
draw = ImageDraw.Draw(img)

for i, line in enumerate(lines):
    y = PAD + i * char_h
    color = HL_COLOR if any(k in line for k in ['PERFECT', 'NONE!', 'PASS', '>>>']) else FG_COLOR
    draw.text((PAD, y), line, font=font, fill=color)

out = "5_3_decoder_result.png"
img.save(out, dpi=(150, 150))
print(f"Saved: {out}  ({img_w}x{img_h}px)")
