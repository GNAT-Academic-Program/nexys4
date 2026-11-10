#!/usr/bin/env python3
"""Generate the cube BRAM image specified by docs/spec/memory_map.md.

One 32-bit binary word per line; line 1 is address 0. XYZ uses signed
16.16 fixed point. IDs remain 1-based. Textures are black (no texels were
provided), and reserved storage is zero. No third-party packages required.
"""

import argparse
from pathlib import Path

TEXTURE_SZ = 16
BRAM_WORDS = 1024
VERTEX_BASE = 0
FACE_BASE = VERTEX_BASE + 24 * 6
TEXTURE_BASE = FACE_BASE + 12 * 3
RESERVED_BASE = TEXTURE_BASE + 6 * 64
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "rtl" / "data" / "cube_init.txt"

# X, Y, Z, Xt, Yt, Texture_ID, in the supplied Ada vertex order.
VERTICES = (
    (-1,  1,  1,  0,  0, 1),
    ( 1,  1,  1,  0, 15, 1),
    ( 1, -1,  1, 15, 15, 1),
    (-1, -1,  1, 15,  0, 1),
    (-1,  1, -1,  0,  0, 2),
    (-1,  1,  1,  0, 15, 2),
    (-1, -1,  1, 15, 15, 2),
    (-1, -1, -1, 15,  0, 2),
    (-1, -1,  1,  0,  0, 3),
    ( 1, -1,  1,  0, 15, 3),
    ( 1, -1, -1, 15, 15, 3),
    (-1, -1, -1, 15,  0, 3),
    ( 1,  1,  1,  0,  0, 4),
    ( 1,  1, -1,  0, 15, 4),
    ( 1, -1, -1, 15, 15, 4),
    ( 1, -1,  1, 15,  0, 4),
    (-1,  1, -1,  0,  0, 5),
    ( 1,  1, -1,  0, 15, 5),
    ( 1,  1,  1, 15, 15, 5),
    (-1,  1,  1, 15,  0, 5),
    (-1, -1, -1,  0,  0, 6),
    ( 1, -1, -1,  0, 15, 6),
    ( 1,  1, -1, 15, 15, 6),
    (-1,  1, -1, 15,  0, 6),
)

FACES = (
    (1, 2, 4), (3, 4, 2), (5, 6, 8), (7, 8, 6),
    (9, 10, 12), (11, 12, 10), (13, 14, 16), (15, 16, 14),
    (17, 18, 20), (19, 20, 18), (21, 22, 24), (23, 24, 22),
)


def fixed_16_16(value):
    """Encode a coordinate with nearest-even rounding and two's complement."""
    scaled = round(value * (1 << 16))
    if not -(1 << 31) <= scaled < (1 << 31):
        raise ValueError(f"Coordinate outside signed 16.16 range: {value}")
    return scaled & 0xFFFFFFFF


def build_image():
    words = [0] * BRAM_WORDS
    if len(VERTICES) != 24 or len(FACES) != 12:
        raise ValueError("The memory map requires 24 vertices and 12 faces")
    for index, (x, y, z, u, v, texture_id) in enumerate(VERTICES):
        if not (0 <= u < TEXTURE_SZ and 0 <= v < TEXTURE_SZ
                and 1 <= texture_id <= 6):
            raise ValueError(f"Invalid attributes for vertex {index + 1}")
        base = VERTEX_BASE + 6 * index
        words[base:base + 6] = [
            fixed_16_16(x), fixed_16_16(y), fixed_16_16(z), u, v, texture_id
        ]
    for index, face in enumerate(FACES):
        if len(face) != 3 or any(not 1 <= vertex_id <= 24 for vertex_id in face):
            raise ValueError(f"Invalid vertex indices for face {index + 1}")
        base = FACE_BASE + 3 * index
        words[base:base + 3] = face
    # Words 180..563: six zero-filled RGB332 textures (black).
    # Words 564..1023: reserved, zero-filled.
    return words


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT,
                        help="Output path (default: rtl/data/cube_init.txt in repo)")
    args = parser.parse_args()
    words = build_image()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii", newline="\n") as output:
        output.writelines(f"{word:032b}\n" for word in words)
    print(f"Wrote {len(words)} words to {args.output}")
    print("Textures 180..563 and reserved words 564..1023 are zero-filled.")


if __name__ == "__main__":
    main()
