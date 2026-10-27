# 精灵条去底色：取四角均色为背景，按 RGB 距离重算 alpha（距离近=透明，远=不透明）
# 用法: python key_alpha.py <目录>   —— 就地改写目录下所有 PNG
import sys, glob
import numpy as np
from PIL import Image

THRESH_LO = 10.0   # 距离低于此值 = 背景，全透明
SLOPE = 4.0        # 距离超出部分的 alpha 斜率（dist 73+ 即全不透明）

for p in sorted(glob.glob(sys.argv[1] + "/*.png")):
    im = Image.open(p).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    w, h = im.size
    corners = np.array([a[0, 0, :3], a[0, w - 1, :3], a[h - 1, 0, :3], a[h - 1, w - 1, :3]])
    bg = corners.mean(axis=0)
    dist = np.sqrt(((a[:, :, :3] - bg) ** 2).sum(axis=2))
    alpha = np.clip((dist - THRESH_LO) * SLOPE, 0, 255)
    a[:, :, 3] = alpha
    Image.fromarray(a.astype(np.uint8)).save(p)
    print(p.split("\\")[-1], "bg=", bg.astype(int), "done")
