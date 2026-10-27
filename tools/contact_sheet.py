# 把 preview/ 里的精灵条重排成网格接触表，方便一眼看动画内容
import sys, json, os, math
from PIL import Image, ImageDraw

d = sys.argv[1]
cell = 160
names = [n[:-4] for n in os.listdir(d) if n.endswith(".png")]
cols = 2
rows = math.ceil(len(names) / cols)
sheet = Image.new("RGB", (cols * 5 * cell, rows * (3 * cell + 20)), (24, 24, 28))
dr = ImageDraw.Draw(sheet)
for i, name in enumerate(names):
    im = Image.open(d + "/" + name + ".png")
    meta = json.load(open(d + "/" + name + ".json"))
    n, w, h = meta["frames"], meta["w"], meta["h"]
    # 网格最多 5x3 展示帧
    pick = min(n, 15)
    step = max(1, n // pick)
    ox = (i % cols) * 5 * cell
    oy = (i // cols) * (3 * cell + 20)
    dr.text((ox + 4, oy + 2), name, fill=(255, 220, 100))
    for j in range(pick):
        f = im.crop(((j * step) * w, 0, (j * step + 1) * w, h))
        f.thumbnail((cell - 4, cell - 4), Image.LANCZOS)
        bg = Image.new("RGBA", (cell, cell), (60, 60, 66, 255))
        bg.paste(f, ((cell - f.width) // 2, (cell - f.height) // 2), f)
        sheet.paste(bg.convert("RGB"), (ox + (j % 5) * cell, oy + 20 + (j // 5) * cell))
sheet.save(d + "/contact.png")
print("ok", sheet.size)
