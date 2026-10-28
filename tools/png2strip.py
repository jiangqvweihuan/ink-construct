#!/usr/bin/env python3
# -*- coding: utf-8 -*-
## PNG 序列 → 水平精灵条（供 fx.gd 逐帧播放）。
## 用法: python tools/png2strip.py <序列目录> <文件名前缀> <输出png> [--align bottom|center] [--pad 0]
## 单元格尺寸 = 序列中最大宽×高；各帧按对齐方式放入单元格（bottom=底对齐居中，center=居中）。

import argparse
import os
import re
import sys

from PIL import Image


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src_dir")
    ap.add_argument("prefix")
    ap.add_argument("out_png")
    ap.add_argument("--align", choices=["bottom", "center"], default="center")
    ap.add_argument("--pad", type=int, default=0, help="单元格外扩留白像素")
    args = ap.parse_args()

    # 按文件名里的数字序号排序（前缀_00000.png 或 前缀00000.png 都认）
    pat = re.compile(r"^" + re.escape(args.prefix) + r"_?(\d+)\.png$", re.IGNORECASE)
    frames = []
    for name in os.listdir(args.src_dir):
        m = pat.match(name)
        if m:
            frames.append((int(m.group(1)), name))
    if not frames:
        print(f"[X] 没找到序列帧: {args.src_dir}/{args.prefix}*")
        return 1
    frames.sort()

    imgs = [Image.open(os.path.join(args.src_dir, n)).convert("RGBA") for _, n in frames]
    cell_w = max(i.width for i in imgs) + args.pad * 2
    cell_h = max(i.height for i in imgs) + args.pad * 2

    strip = Image.new("RGBA", (cell_w * len(imgs), cell_h), (0, 0, 0, 0))
    for idx, im in enumerate(imgs):
        x = idx * cell_w + (cell_w - im.width) // 2
        if args.align == "bottom":
            y = cell_h - im.height - args.pad
        else:
            y = (cell_h - im.height) // 2
        strip.paste(im, (x, y), im)

    os.makedirs(os.path.dirname(args.out_png) or ".", exist_ok=True)
    strip.save(args.out_png)
    print(f"[OK] {args.out_png}: {len(imgs)} 帧, 单元 {cell_w}x{cell_h}, 对齐 {args.align}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
