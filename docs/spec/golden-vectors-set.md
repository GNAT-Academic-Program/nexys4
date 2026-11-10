# RQ-38 Golden Vectors (Directed Set)

## Operation table

This is the RQ-38 skeleton table for v1.0, one row per operation, followed by the directed golden vectors each CSV must contain. The vectors were computed from the contract formulas in a scratch check. `gen_vectors.adb` must reproduce them exactly before the 11/3 tag, and its output, not this doc, is what gets committed.

| Op | Inputs (format) | Output (format) | Intermediate width | Rounding | Overflow | Ada expression | VHDL expression | Vector file |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mul\_q16 | Q16.16, Q16.16 | Q16.16 | 64-bit | ties toward +inf: `(a*b + 2^15) >> 16` | Pre: result fits 32 bits | `Mul (A, B)` | `mul_q16(a, b)` | mul.csv |
| viewport\_xy | Q16.16 x, y in -1..1 | Q16.16 sx 0..320, sy 0..240 | 64-bit | exact | Pre: inputs in -1..1 | `Viewport_X (X)`, `Viewport_Y (Y)` | `viewport_x(x)`, `viewport_y(y)` | viewport.csv |
| depth\_map | Q16.16 z in -1..1 | unsigned D bits | 26 + D bits | half up: `((z + 2^16)(2^D - 1) + 2^16) >> 17` | Pre: input in -1..1 | `Depth_Map (Z)` | `depth_map(z)` | viewport.csv |
| tri\_setup | 3 x Q16.16 screen (x, y), 3 depths | A 25b, B 26b, area2 51b, TL 3b, bbox, reject | 51-bit | exact | none (bounded) | `Setup (V)` | `tri_setup(...)` | setup.csv |
| edge\_eval + coverage | setup, px 9b, py 8b | E\_0..2 51b, covered | 51-bit | exact | none (bounded) | `Edge (S, I, Px, Py)`, `Covered` | `edge_eval(...)` | edge.csv |
| depth\_interp | E\_0..2, z\_0..2, area2 | depth D bits | 60-bit / 52-bit | half up: `(2*num + area2) div (2*area2)` | none (bounded) | `Interp_Z (...)` | `interp_z(...)` | interp.csv |
| depth\_test | z, stored z (D bits) | pass | D bits | n/a | n/a | `Z < Stored` | `z < stored` | interp.csv |

**File conventions:** the first line starts with `#` and names the columns. Fields are hex, comma-separated, two's complement at the listed width, padded to whole hex digits: Q16.16 values take 8 digits, 51-bit values 13, and depth 2 (D = 8). Booleans are `0` or `1`.

## mul.csv and viewport.csv

**mul.csv: the 20 directed rows** (RQ-88 also needs 1,000 random rows from a fixed seed). In order, they cover: 1 x 1; zero on each side; 0.5 x -2; -0.5 x 0.5; -1 x -1; +/-1 LSB x 1; the +0.5 and -0.5 LSB ties; one below a tie; +/-1.5 LSB ties; LSB x LSB; max and min x 1; max x 0.5; 181^2 and -181 x 181 near the limit; and pi x -e.

```csv
# a,b,y
00010000,00010000,00010000
00000000,00010000,00000000
00010000,00000000,00000000
00008000,FFFE0000,FFFF0000
FFFF8000,00008000,FFFFC000
FFFF0000,FFFF0000,00010000
00000001,00010000,00000001
FFFFFFFF,00010000,FFFFFFFF
00000001,00008000,00000001
FFFFFFFF,00008000,00000000
00000001,00007FFF,00000000
00000003,00008000,00000002
FFFFFFFD,00008000,FFFFFFFF
00000001,00000001,00000000
7FFFFFFF,00010000,7FFFFFFF
80000000,00010000,80000000
7FFFFFFF,00008000,40000000
00B50000,00B50000,7FF90000
FF4B0000,00B50000,80070000
0003243F,FFFD481F,FFF775D6
```

**viewport.csv: 10 directed rows** covering the four corners, the center, quarter and half points, a 1 LSB input (sx = 160 + 160 LSB), and -0.999/0.999. `sz8` uses D = 8 and `sz16` uses D = 16, which meets RQ-91's "DEPTH\_W = 8 and one other width". Add 500 random rows.

```csv
# x,y,z,sx,sy,sz8,sz16
FFFF0000,FFFF0000,FFFF0000,00000000,00F00000,00,0000
00000000,00000000,00000000,00A00000,00780000,80,8000
00010000,00010000,00010000,01400000,00000000,FF,FFFF
FFFF0000,00010000,00000000,00000000,00000000,80,8000
00010000,FFFF0000,00000000,01400000,00F00000,80,8000
00004000,00004000,00004000,00C80000,005A0000,9F,9FFF
FFFF8000,00008000,FFFF8000,00500000,003C0000,40,4000
00008000,FFFF8000,00008000,00F00000,00B40000,BF,BFFF
00000001,FFFFFFFF,00000001,00A000A0,00780078,80,8000
FFFF0042,0000FFBE,0000FFBE,00002940,00001EF0,FF,FFDE
```

## setup.csv

Eight directed triangles, given in screen space (Q16.16) as Block D receives them. A and B are shown after winding normalization, and `TL` packs the three top-left flags into bits 0 to 2.

| Tri | Vertices (x, y, z) | Tests | area2 (px^2) | TL flags |
| --- | --- | --- | --- | --- |
| 1 | (40, 30, 10), (200, 30, 200), (40, 180, 100) | Right triangle, horizontal top and vertical left edges | 24,000 | 1, 0, 1 |
| 2 | Tri 1 with v1 and v2 swapped | Reversed winding: must give the same pixels and depths as tri 1 | 24,000 | 1, 0, 1 |
| 3 | (10.25, 20.5, 5), (300.75, 22, 250), (10.25, 21, 128) | Sliver, 49 covered pixels, a tie at pixel (155, 21) | 145.25 | 0, 1, 1 |
| 4 | (20.5, 100.5, 50), (120.5, 150.5, 90), (100.25, 40.75, 30) | Shares edge v0-v1 with tri 5; the edge passes 51 pixel centers | 9,962.5 | 1, 0, 1 |
| 5 | (120.5, 150.5, 90), (20.5, 100.5, 50), (60.75, 200.25, 180) | Other side of the shared edge | 7,962.5 | 0, 1, 0 |
| 6 | (10.5, 10.5, 7), (90.5, 10.5, 250), (10.5, 70.5, 33) | Vertices on pixel centers: ties on all three edges | 4,800 | 1, 0, 1 |
| 7 | (20, 20, 0), (100, 100, 0), (60, 60, 0) | Collinear: zero area, rejected | 0 | 0, 1, 1 |
| 8 | (0, 0, 0), (320, 240, 255), (0, 240, 128) | Touches x = 320 and y = 240: bounding box clamps to 319 and 239 | 76,800 | 0, 0, 1 |

```csv
# tri,x0,y0,z0,x1,y1,z1,x2,y2,z2,A0,B0,A1,B1,A2,B2,area2,TL,xmin,xmax,ymin,ymax,reject
1,00280000,001E0000,0A,00C80000,001E0000,C8,00280000,00B40000,64,0000000,0A00000,F6A0000,F600000,0960000,0000000,05DC000000000,5,028,0C8,1E,B4,0
2,00280000,001E0000,0A,00280000,00B40000,64,00C80000,001E0000,C8,0960000,0000000,F6A0000,F600000,0000000,0A00000,05DC000000000,5,028,0C8,1E,B4,0
3,000A4000,00148000,05,012CC000,00160000,FA,000A4000,00150000,80,FFE8000,1228000,0010000,EDD8000,0008000,0000000,0009140000000,6,00A,12C,14,16,0
4,00148000,00648000,32,00788000,00968000,5A,00644000,0028C000,1E,0320000,F9C0000,F924000,0144000,03BC000,04FC000,026EA80000000,5,014,078,28,96,0
5,00788000,00968000,5A,00148000,00648000,32,003CC000,00C84000,B4,FCE0000,0640000,063C000,FD7C000,FCE4000,FC44000,01F1A80000000,2,014,078,64,C8,0
6,000A8000,000A8000,07,005A8000,000A8000,FA,000A8000,00468000,21,0000000,0500000,FC40000,FB00000,03C0000,0000000,012C000000000,5,00A,05A,0A,46,0
7,00140000,00140000,00,00640000,00640000,00,003C0000,003C0000,00,FB00000,0500000,0280000,FD80000,0280000,FD80000,0000000000000,6,014,064,14,64,1
8,00000000,00000000,00,01400000,00F00000,FF,00000000,00F00000,80,F100000,1400000,0000000,EC00000,0F00000,0000000,12C0000000000,4,000,13F,00,EF,0
```

A is 25 bits and B is 26 bits, both written as 7 hex digits. Add 200 random triangles from a fixed seed, with vertices generated in -1..1 and mapped through viewport\_xy, so every row is reachable from a real scene.

## edge.csv and interp.csv

The generated `edge.csv` holds every pixel in each directed triangle's bounding box. The rows below are the checkpoints to hand-verify: interior pixels, pixels just outside, and every kind of tie. E values are Q18.32, 51 bits, written as 13 hex digits.

- **Tri 1 and 2:** identical E values in rotated order and identical coverage. This proves the winding normalization.
- **Tri 3, pixel (155, 21):** E\_1 = 0 on a top-left edge, so it is covered.
- **Tri 4 and 5, pixels (40, 110) and (70, 125):** E\_0 = 0 on the shared edge in both. Tri 4 owns the pixel and tri 5 does not, so it is drawn exactly once.
- **Tri 6:** (10, 10) sits on two top-left edges and is covered; (50, 40) sits on the non-top-left hypotenuse and is not; (90, 10) and (10, 70) are vertices on non-top-left edges and are not covered.
- **Tri 7:** rejected, so every E is 0 and nothing is covered.
- **Tri 8, (319, 239):** inside the clamped bounding box but outside the triangle.

```csv
# tri,px,py,E0,E1,E2,covered
1,028,1E,0005000000000,05D2500000000,0004B00000000,1
1,029,1F,000F000000000,05BEF00000000,000E100000000,1
1,027,1E,0005000000000,05DBB00000000,FFFB500000000,0
1,064,3C,0131000000000,0273D00000000,0237300000000,1
1,078,68,02E9000000000,0000500000000,02F2B00000000,1
1,077,69,02F3000000000,FFFFB00000000,02E9500000000,0
1,0C8,1E,0005000000000,FFF6500000000,05E0B00000000,0
2,028,1E,0004B00000000,05D2500000000,0005000000000,1
2,029,1F,000E100000000,05BEF00000000,000F000000000,1
2,027,1E,FFFB500000000,05DBB00000000,0005000000000,0
2,064,3C,0237300000000,0273D00000000,0131000000000,1
2,078,68,02F2B00000000,0000500000000,02E9000000000,1
2,077,69,02E9500000000,FFFFB00000000,02F3000000000,0
3,09A,15,0004A20000000,FFFFF00000000,0004820000000,0
3,09B,15,00048A0000000,0000000000000,00048A0000000,1
3,0CB,15,00000A0000000,0003000000000,00060A0000000,1
4,028,6E,0000000000000,01F2200000000,007C880000000,1
5,028,6E,0000000000000,0063880000000,018E200000000,0
4,046,7D,0000000000000,0137540000000,0137540000000,1
5,046,7D,0000000000000,00F8D40000000,00F8D40000000,0
4,047,7D,0003200000000,0130780000000,013B100000000,1
5,047,7D,FFFCE00000000,00FF100000000,00F5B80000000,0
6,00A,0A,0000000000000,012C000000000,0000000000000,1
6,032,0A,0000000000000,0096000000000,0096000000000,1
6,00A,28,0096000000000,0096000000000,0000000000000,1
6,032,28,0096000000000,0000000000000,0096000000000,0
6,031,28,0096000000000,0003C00000000,0092400000000,1
6,05A,0A,0000000000000,0000000000000,012C000000000,0
6,00A,46,012C000000000,0000000000000,0000000000000,0
7,014,14,0000000000000,0000000000000,0000000000000,0
7,03C,3C,0000000000000,0000000000000,0000000000000,0
8,000,00,0002800000000,12B6000000000,0007800000000,1
8,000,EF,12AE800000000,000A000000000,0007800000000,1
8,13F,EF,FFFD800000000,000A000000000,12B8800000000,0
8,0A0,78,0002800000000,0956000000000,0967800000000,1
8,0A0,77,FFEE800000000,096A000000000,0967800000000,0
8,13F,00,ED51800000000,12B6000000000,12B8800000000,0
```

**interp.csv** lists covered pixels only, with the interpolated depth at D = 8. Every value lies between its triangle's smallest and largest vertex depth, and tri 6's pixel (10, 10) returns vertex depth 7 exactly.

```csv
# tri,px,py,z
1,028,1E,0B
1,029,1F,0D
1,064,3C,64
1,078,68,96
2,028,1E,0B
2,029,1F,0D
2,064,3C,64
2,078,68,96
3,09B,15,BD
3,0CB,15,A9
4,028,6E,3A
4,046,7D,46
4,047,7D,46
6,00A,0A,07
6,032,0A,81
6,00A,28,14
6,031,28,8A
8,000,00,00
8,000,EF,80
8,0A0,78,80
```

**Depth test rows** (append to `interp.csv` as a second section, or keep as `depth_test.csv`). They cover pass, equal, fail, the cleared far value, and zero.

```csv
# z,stored,pass
0B,FF,1
0B,0B,0
0B,0A,0
0A,0B,1
FF,FF,0
00,00,0
00,01,1
```
