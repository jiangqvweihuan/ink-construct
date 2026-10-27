# GIF -> 水平精灵条 PNG + JSON 元数据（帧数/fps/尺寸）
# 用法: python gif2strip.py <gif路径> <输出目录> <名字> [最大高度]
import sys, json
from PIL import Image

gif_path, out_dir, name = sys.argv[1], sys.argv[2], sys.argv[3]
max_h = int(sys.argv[4]) if len(sys.argv) > 4 else 0

im = Image.open(gif_path)
frames = []
dur_ms = 50
try:
    while True:
        f = im.convert("RGBA")
        frames.append(f)
        dur_ms = max(im.info.get("duration", 50), 20)
        im.seek(im.tell() + 1)
except EOFError:
    pass

# 裁掉全透明边框，所有帧用同一包围盒
bbox = None
for f in frames:
    b = f.getbbox()
    if b:
        bbox = b if bbox is None else (min(bbox[0], b[0]), min(bbox[1], b[1]), max(bbox[2], b[2]), max(bbox[3], b[3]))
if bbox is None:
    bbox = (0, 0, frames[0].width, frames[0].height)
frames = [f.crop(bbox) for f in frames]

w, h = frames[0].size
scale = 1.0
if max_h and h > max_h:
    scale = max_h / h
    w, h = int(w * scale), int(h * scale)
    frames = [f.resize((w, h), Image.LANCZOS) for f in frames]

strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
for i, f in enumerate(frames):
    strip.paste(f, (i * w, 0), f)
strip.save(out_dir + "/" + name + ".png")
fps = round(1000.0 / dur_ms, 1)
with open(out_dir + "/" + name + ".json", "w", encoding="utf-8") as fp:
    json.dump({"frames": len(frames), "fps": fps, "w": w, "h": h}, fp)
print(f"{name}: {len(frames)}帧 {fps}fps {w}x{h}")
