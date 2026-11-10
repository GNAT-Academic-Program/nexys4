# Memory Management Discussion and Design Decisions

**Team 05 – QOGPU Graphics Pipeline**

Connor Bodie

10/20/2026

At this point in the design process, we have a functioning software renderer which needs to be accelerated with custom hardware. Before designing specific graphics hardware, certain details must be considered. Firstly, resource limitations and their implications on data management. Our minimum specification target hardware was given as the Mercury 2 FPGA model ME2A-35T-4M. According to the specification sheet of this FPGA ([Mercury 2 specifications](https://www.micro-nova.com/products/p/me2a)), this chip has 4Mbit of off-chip SRAM, and 1,800 kbits of (faster) on-chip BRAM. We will design our system around these constraints.

The largest memory consumers in the current software renderer are the frame and depth buffers. These arrays occupy 3 and 4 bytes of memory per pixel, respectively. At the requested resolution of 600x480, the total memory of these two buffers alone is:

```text
600 pixels*480 pixels*(3 bytes+4 bytes)=2.016MB
```

2.016MB exceeds the total capacity of Mercury 2, so an important design decision must be made here.

First, we considered fundamental software changes for our renderer. The approach outlined in the IBM paper Scanline principle: efficient conversion of display algorithms into scanline mode provides one option. Instead of keeping buffers for the entire frame, do the work for each horizontal cross-section (known as a scanline), then write the frame to the display line-by-line, thus reducing the buffer size requirements from 600x480 to just 600x1. While not directly in the paper, it is logical to conclude that this could also work at the individual pixel level too, eliminating the need for any buffer at all. However, these approaches inflict substantial trade-offs, namely in speed and complexity. The scanline approach would require processing each face geometry once per line, instead of once per frame, a 480x increase in workload (before optimization, but still completely unreasonable). Furthermore, the individual pixel approach would further radicalize this tradeoff, since it would logically require processing each triangle nearly 300,000 times per frame. These approaches will not be considered further.

The next consideration is to compromise on resolution and color pallet. By reducing the resolution to 300x240, we will reduce the buffer size by 4x. We can also represent color with 1 byte instead of 3 by using the RGB332 approach, where we use 3 bits for red and green, and 2 for blue. This would reduce the frame buffer size by another 3x. Similarly, we can drop the depth resolution from 4 bytes to 1, reducing depth buffer size by another 4x. With these compromises, we lose some image quality, but gain simplicity, speed, and are under the memory threshold:

```text
300 pixels*240 pixels*(1 byte+1 byte)=0.144MB=1.152Mbit
```

This is substantially lower than the 4Mbit maximum, giving us room to enhance resolution and color pallet later if desired. This is the approach we will proceed with.

The remainder of the render data includes vertex XYZ and texture coordinates, vertex texture IDs, face index arrays, and RGB332 texture files.  The memory footprint is outlined in the following table:

| Data structure | Calculation | Storage |
| --- | --- | --- |
| Vertex XYZ coordinates | 24 × 3 × 4 bytes | 288 bytes |
| Vertex texture coordinates | 24 × 2 × 4 bytes | 192 bytes |
| Vertex texture IDs | 24 × 4 bytes | 96 bytes |
| Face indices | 12 × 3 × 4 bytes | 144 bytes |
| RGB332 textures | 6 × 16 × 16 × 1 byte | 1,536 bytes |
| Total |  | 2,256 bytes |

2,256 bytes is just under 1% of the Mercury 2’s BRAM capacity, leaving plenty of on-chip capacity for the NEORV32 and GPU hardware.
