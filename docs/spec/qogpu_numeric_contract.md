# Team 05 QOGPU Graphics Pipeline

**Author:** Vance Steele  
**Date:** 10/30/2026  

---

## Numeric Contract

This document provides design decisions, with reasons, for each numeric or rounding rule that must be considered in the graphic pipeline such that the VHDL RTL and the Ada reference are bit exact. Sixteen different rules outline everything:

| # | Rule | Decision | Reason |
|---|---|---|---|
| **1** | Storage format | Signed 16.16, 32 bit 2’s complement | See `memory_map.md` |
| **2** | Screen coords | Block C outputs 16.16 $x$ in $0..320$ and $y$ in $0..240$. Pixels are sampled at their centers s.t. $p_x + 0.5, p_y + 0.5$ | Matches `mvp_block_diagram.md`, scaling by 160 and 120 is exact so no rounding is needed. |
| **3** | Depth format | Unsigned $\text{DEPTH\_W}$ bits that default to size 8. $s_z = \lfloor (2^D - 1) z + 2^{16} + (2^{16} \gg 17) \rfloor$ | 8-bit depth from memory decision and requirements. The formula rounds half up with no clamp for $z$ in $-1.0..1.0$. |
| **4** | Shift | $\gg$ is an arithmetic shift that rounds down. Ada uses $P - (P \bmod 2^{16}) / 2^{16}$ | Ada and VHDL’s integer division truncate towards 0, which differs from floor for negatives. The mod form makes things easier for GNATprove. |
| **5** | Multiplication rounding | $(a \times b + 2^{15}) \gg 16$ where ties $\rightarrow +\infty$ | Floor biases every product by $-\frac{1}{2} \text{ LSB}$, which accumulates through a matrix. The constant enters the DSP48E1 48-bit C input with no extra logic. |
| **6** | Division | No signed division. The singular division has positive operands only and rounds half up | Avoids truncate versus floor mismatch |
| **7** | Overflow | SPARK proves no overflow in Ada and VHDL `assert` checks in xsim, so no wrap or saturate | Proving overflow cannot occur is a stronger decision and creates less work than overflow or wrap |
| **8** | Off-screen vertices | Vertex $x,y,z$ in $-1.0..1.0$. Vertices are never clamped but bounding box is clamped to $0..319$ and $0..239$ | The MVP scene is screen-space data and clamping a vertex would change triangle shape |
| **9** | Edge width | $A_i = y_i - y_{i+1}$ in 25 bits, $B_i = x_{i+1} - x_i$ in 26 bits. $E_i = A_i (x_s - x_i) + B_i (y_s - y_i)$ and `area_sq` are exact 18.32 in 51 bits | Giesen bounds a determinant amount of $p$-bit inputs by $2p+2$ bits. The screen range gives a tighter 51-bit bound ($2 \times 320 \times 240 \times 2^{32} < 2^{50}$) |
| **10** | Interpolation | Barycentric depth of $z = \frac{2 \times \text{num} + \text{area\_sq}}{2 \times \text{area\_sq}}$ where $\text{num} = E_0 z_2 + E_1 z_0 + E_2 z_1$ in 60.52 | Result is always between vertex depths. Quotient has only $D$ bits so an 8-step divider works |
| **11** | Fill rule | Top left fill rule. After orientation is normalized with $y$ pointing down, $\text{TL}_i = A_i > 0 \lor (A_i = 0 \land B_i > 0)$. A pixel is covered if every $E_i > 0 \lor (E_i = 0 \land \text{TL}_i)$ | Giesen implements shared edges as a $-1$ bias on non-top-left edges. Shared edges are drawn once |
| **12** | Degenerate and back facing triangles | $\text{area\_sq} = 0$ rejects all fragments; $\text{area\_sq} < 0$ negates all $A_i$, $B_i$, and $\text{area\_sq}$ | Giesen’s top-left derivation assumes one winding and normalization gives it that winding for any vertex order |
| **13** | Depth comparison | Pass over when $z < \text{stored}$. $z = \text{stored}$ keeps earlier pixel. Clear when $\text{depth} = 2^D - 1$ | Vortex GPU culls strictly behind so equal depths stay deterministic (See RQ-94) |
| **14** | Order | Faces in face-table order and pixels in row-major ($y$ then $x$) | Makes depth ties deterministic, making every frame deterministic |
| **15** | Texture addressing | Deferred until after MVP | Not used by two flat, colored triangles |
| **16** | Ada representation | Hybrid such that every operation works with a raw integer | Using a hybrid approach allows strong typing and bit-exact representation |

---

## Works Cited

* **[1]** “Fixed Point Types,” in *Ada Reference Manual*, AdaCore, p. 3.5.9. Accessed: Oct. 30, 2026. [Online]. Available: [https://docs.adacore.com/live/wave/arm12/html/arm12/arm12-3-5-9.html](https://docs.adacore.com/live/wave/arm12/html/arm12/arm12-3-5-9.html)
* **[2]** GrantMeStrength, “Rasterization Rules - Win32 Apps,” *Microsoft Learn*. Accessed: Oct. 30, 2026. [Online]. Available: [https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d10-graphics-programming-guide-rasterizer-stage-rules](https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d10-graphics-programming-guide-rasterizer-stage-rules)
* **[3]** “Triangle Rasterization in Practice,” *The ryg blog*. Accessed: Oct. 30, 2026. [Online]. Available: [https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/](https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/)