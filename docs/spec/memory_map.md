# Hard-coded Input Memory Map

Block A (command controller and local storage) stores the initial cube inputs in a 32-bit-wide BRAM containing 1,024 words (4 KiB). This map covers only the hard-coded vertex, face, and texture inputs; frame/depth buffers and CPU/X-bus registers are outside its scope.

BRAM addresses are **word addresses**, starting at zero. Each word contains four bytes, so `byte_offset = 4 * word_address`. All ranges below are inclusive and relative to the start of this BRAM; no system bus base address is assigned.

## Input regions

| Input | BRAM word addresses (decimal) | Byte offsets (hex, inclusive) | Size |
| --- | --- | --- | --- |
| Vertices 1–24 | 0–143 | 0x000–0x23F | 576 bytes |
| Faces 1–12 | 144–179 | 0x240–0x2CF | 144 bytes |
| Texture 1 | 180–243 | 0x2D0–0x3CF | 256 bytes |
| Texture 2 | 244–307 | 0x3D0–0x4CF | 256 bytes |
| Texture 3 | 308–371 | 0x4D0–0x5CF | 256 bytes |
| Texture 4 | 372–435 | 0x5D0–0x6CF | 256 bytes |
| Texture 5 | 436–499 | 0x6D0–0x7CF | 256 bytes |
| Texture 6 | 500–563 | 0x7D0–0x8CF | 256 bytes |
| Reserved (initialize to zero) | 564–1023 | 0x8D0–0xFFF | 1,840 bytes |
| **Used input storage** | **0–563 (564 words)** | **0x000–0x8CF** | **2,256 bytes** |

## Base definitions

The region bases are derived by placing the inputs consecutively:

| Constant | Word address (decimal) | Byte offset (hex) | Definition |
| --- | --- | --- | --- |
| `VERTEX_BASE` | 0 | 0x000 | Start of BRAM |
| `FACE_BASE` | 144 | 0x240 | `VERTEX_BASE + 24 * 6` |
| `TEXTURE_BASE` | 180 | 0x2D0 | `FACE_BASE + 12 * 3` |
| `RESERVED_BASE` | 564 | 0x8D0 | `TEXTURE_BASE + 6 * 64` |

Vertex, face, and texture IDs are **1-based**. For vertex ID `v` (1–24), face ID `f` (1–12), and texture ID `t` (1–6), the record bases in words are:

```text
V_base(v) = VERTEX_BASE  + 6  * (v - 1)
F_base(f) = FACE_BASE    + 3  * (f - 1)
T_base(t) = TEXTURE_BASE + 64 * (t - 1)
```

Multiply any base by four to obtain its byte offset.

## Vertex fields

Each vertex occupies six words (24 bytes), in the order `X, Y, Z, Xt, Yt, TextureID`.

| Field | Word address | Byte offset within vertex | Encoding |
| --- | --- | --- | --- |
| X | `V_base(v) + 0` | 0x00 | Signed 32-bit 16.16 fixed point |
| Y | `V_base(v) + 1` | 0x04 | Signed 32-bit 16.16 fixed point |
| Z | `V_base(v) + 2` | 0x08 | Signed 32-bit 16.16 fixed point |
| Xt | `V_base(v) + 3` | 0x0C | 32-bit integer, 0–15 |
| Yt | `V_base(v) + 4` | 0x10 | 32-bit integer, 0–15 |
| TextureID | `V_base(v) + 5` | 0x14 | 32-bit integer, 1–6 |

For example, vertex 1 occupies words 0–5, vertex 2 occupies words 6–11, and vertex 24 occupies words 138–143. Coordinate encodings include `+1.0 = 0x00010000`, `0.0 = 0x00000000`, and `-1.0 = 0xFFFF0000` (two's complement). Store original model coordinates at the intended model scale.

## Face fields

Each triangular face occupies three words (12 bytes). Preserve the software renderer's vertex order to preserve winding.

| Field | Word address | Byte offset within face | Encoding / meaning |
| --- | --- | --- | --- |
| A | `F_base(f) + 0` | 0x00 | 32-bit integer, first vertex ID (1–24) |
| B | `F_base(f) + 1` | 0x04 | 32-bit integer, second vertex ID (1–24) |
| C | `F_base(f) + 2` | 0x08 | 32-bit integer, third vertex ID (1–24) |

## Texture addressing and packing

Each of the six textures contains 16 × 16 RGB332 texels: 256 bytes, packed four texels per word (64 words). Texels are stored in row order: `(0,0), (1,0), ..., (15,0), (0,1), ...`. Row zero corresponds to `Yt = 0`.

For texture coordinates `u = Xt` and `y = Yt`, both in 0–15:

```text
p            = 16 * y + u
word_address = T_base(t) + floor(p / 4)
byte_lane    = p mod 4
byte_offset  = 4 * T_base(t) + p
```

| Byte lane | Word bits | Contents |
| --- | --- | --- |
| 0 | [7:0] | First texel |
| 1 | [15:8] | Second texel |
| 2 | [23:16] | Third texel |
| 3 | [31:24] | Fourth texel |

Within each texel, red occupies bits `[7:5]`, green `[4:2]`, and blue `[1:0]`.

Source: [final memory-map discussion in the shared project context](https://chatgpt.com/share/6add1941-6c38-83e9-857a-5dc1654b5137). This documents the proposed input layout; it does not supply the asset values or an initialization file.
