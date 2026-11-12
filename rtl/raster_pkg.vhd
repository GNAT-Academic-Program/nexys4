-- raster_pkg: types shared by Block D (tri_setup) and E1-E3 (rasterizer)
-- RQ-92. Widths follow numeric contract rule 9 (docs/spec/qogpu_numeric_contract.md)
-- and the Ada reference Qogpu_Raster.Setup_T (sw/ada/ref/src/qogpu_raster.ads).
--
-- All record fields are fixed width (no unconstrained elements) so xsim and
-- synthesis treat them like mem_if_pkg. Depth is held in DEPTH_MAX_W bits and
-- only the low DEPTH_W bits are used, the same convention as MEM_DATA_W.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;
use work.qogpu_fx_pkg.all;

package raster_pkg is
  constant A_W         : positive := 25;  -- A_i = y_i - y_{i+1}, signed Q16 difference
  constant B_W         : positive := 26;  -- B_i = x_{i+1} - x_i, signed Q16 difference
  constant AREA_W      : positive := 51;  -- area2 and E_i, exact 18.32
  constant DEPTH_MAX_W : positive := 16;  -- widest DEPTH_W; low DEPTH_W bits used

  subtype a_t     is signed(A_W - 1 downto 0);
  subtype b_t     is signed(B_W - 1 downto 0);
  subtype area_t  is signed(AREA_W - 1 downto 0);
  subtype depth_t is unsigned(DEPTH_MAX_W - 1 downto 0);

  type q16_arr3_t   is array (0 to 2) of q16_t;
  type a_arr3_t     is array (0 to 2) of a_t;
  type b_arr3_t     is array (0 to 2) of b_t;
  type depth_arr3_t is array (0 to 2) of depth_t;

  -- One triangle after setup: everything E1/E2/E3 and E6 need.
  -- Index i of a/b/tl is edge i, from vertex i to vertex (i+1) mod 3.
  type tri_t is record
    vx, vy : q16_arr3_t;    -- vertex positions, the reference point of each edge function
    z      : depth_arr3_t;  -- vertex depths (low DEPTH_W bits)
    a      : a_arr3_t;      -- after winding normalization (rule 12)
    b      : b_arr3_t;
    area2  : area_t;        -- twice the area, >= 0 after normalization
    tl     : std_logic_vector(2 downto 0);  -- top-left flag per edge (rule 11), bit i = edge i
    xmin, xmax : fb_x_t;    -- bounding box, clamped to 0..319 (rule 8)
    ymin, ymax : fb_y_t;    -- clamped to 0..239
    color  : pixel_t;       -- RGB332, flat per triangle
    last   : std_logic;     -- last triangle of the frame
    empty  : std_logic;     -- area2 = 0: emit no pixels (only sent when last = '1')
  end record;

  constant TRI_ZERO : tri_t := (
    vx => (others => (others => '0')),
    vy => (others => (others => '0')),
    z  => (others => (others => '0')),
    a  => (others => (others => '0')),
    b  => (others => (others => '0')),
    area2 => (others => '0'),
    tl => (others => '0'),
    xmin => (others => '0'),
    xmax => (others => '0'),
    ymin => (others => '0'),
    ymax => (others => '0'),
    color => (others => '0'),
    last => '0',
    empty => '0'
  );
end package;
