#!/usr/bin/env python3
"""BMP → PNG 转换（仅用标准库）

软光栅（tools/softraster.lua）输出 BMP，因为 Lua 侧没有 zlib。
但 BMP 又不能进仓库（一张 1600×900 就是 5MB），所以这里用 Python 的 zlib
把它压成 PNG，供文档配图与截图比对使用。

    python tools/topng.py in.bmp out.png
"""

import struct
import sys
import zlib


def read_bmp(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"BM":
        raise ValueError("不是 BMP 文件")
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    if bpp not in (24, 32):
        raise ValueError("只支持 24/32 位 BMP，收到 %d" % bpp)

    stride = width * (bpp // 8)
    stride += (-stride) % 4          # BMP 行按 4 字节对齐
    flip = height > 0
    height = abs(height)

    rows = []
    for y in range(height):
        src_y = (height - 1 - y) if flip else y
        start = offset + src_y * stride
        row = bytearray()
        for x in range(width):
            i = start + x * (bpp // 8)
            b, g, r = data[i], data[i + 1], data[i + 2]
            row += bytes((r, g, b))
        rows.append(bytes(row))
    return width, height, rows


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + r for r in rows)      # 每行前置 filter=0

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    w, h, rows = read_bmp(sys.argv[1])
    write_png(sys.argv[2], w, h, rows)
    print("wrote %s (%dx%d)" % (sys.argv[2], w, h))
    return 0


if __name__ == "__main__":
    sys.exit(main())
