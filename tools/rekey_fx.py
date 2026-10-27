# 特效精灵条修复：key_alpha 整条约色失败时（脏底色残留成方块），按每帧四角重新抠底。
# 最终 alpha = min(原 alpha, 新抠 alpha)：干净区域不受二次抠底影响，只清残留的脏底。
# 用法: python rekey_fx.py <png路径> <帧数>
import sys
import numpy as np
from PIL import Image

THRESH_LO = 12.0  # 距帧底色小于此值 -> 背景，全透明
SLOPE = 5.0       # alpha 爬升斜率（dist 63+ 即全不透明）

path, frames = sys.argv[1], int(sys.argv[2])
im = Image.open(path).convert("RGBA")
a = np.asarray(im).astype(np.float32)
w, h = im.size
fw = w // frames
out = a.copy()
for i in range(frames):
    x0, x1 = i * fw, (i + 1) * fw if i < frames - 1 else w
    f = a[:, x0:x1]
    fww = x1 - x0
    corners = np.array([f[0, 0, :3], f[0, fww - 1, :3], f[h - 1, 0, :3], f[h - 1, fww - 1, :3]])
    bg = corners.mean(axis=0)
    dist = np.sqrt(((f[:, :, :3] - bg) ** 2).sum(axis=2))
    new_alpha = np.clip((dist - THRESH_LO) * SLOPE, 0, 255)
    out[:, x0:x1, 3] = np.minimum(f[:, :, 3], new_alpha)
Image.fromarray(out.astype(np.uint8)).save(path)
print(path.split("\\")[-1], "rekeyed,", frames, "frames")
