# 生成「预警墨环」精灵条：扩散+淡出的椭圆环，带轻微毛边抖动（水墨感），近白色底方便 mod 染色。
# 用途：敌人出手预警（原 gather 贴图是脏绿孔雀眼，观感差）、焚鼎火区预警。
# 用法: python gen_telegraph.py <输出png>
import sys
import math
import random
from PIL import Image, ImageDraw

FRAMES, SIZE = 12, 256
random.seed(7)

strip = Image.new("RGBA", (SIZE * FRAMES, SIZE), (0, 0, 0, 0))
for i in range(FRAMES):
    t = i / (FRAMES - 1)  # 0 -> 1
    rx = 26.0 + 92.0 * t  # 横向扩散
    ry = rx * 0.42  # 透视压扁成地面椭圆
    cx, cy = SIZE / 2, SIZE * 0.72 # 局部帧坐标（画在单帧画布上，再 paste 进条带）
    alpha = int(235 * (1.0 - t * 0.85))  # 越散越淡
    width = max(2, int(7 - 4 * t))
    frame = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    # 用一圈抖动的短弧拼出毛边墨环：半径带噪声，笔触不闭合才像手绘
    steps = 60
    for s in range(steps):
        a0 = s / steps * math.tau
        a1 = a0 + math.tau / steps * random.uniform(0.5, 1.1)
        wob = random.uniform(-3.0, 3.0)
        p0 = (cx + math.cos(a0) * (rx + wob), cy + math.sin(a0) * (ry + wob * 0.42))
        p1 = (cx + math.cos(a1) * (rx + wob), cy + math.sin(a1) * (ry + wob * 0.42))
        d.line([p0, p1], fill=(245, 240, 235, alpha), width=width)
    strip.paste(frame, (SIZE * i, 0))
strip.save(sys.argv[1])
print("telegraph ring strip saved:", sys.argv[1])
