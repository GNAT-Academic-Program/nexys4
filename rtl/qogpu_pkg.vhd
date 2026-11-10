-- Shared constants and helpers for QOGPU pipeline
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package qogpu_pkg is 
    -- Screen space after Block C
    constant FB_W      : positive := 320;
    constant FB_H      : positive := 240;
    constant FB_PIXELS : positive := FB_W * FB_H; -- 76800
    constant FB_ADDR_W : positive := 17; -- smallest n w/ 2^n >= FB_PIXELS
    constant FB_X_W    : positive := 9; -- 0 .. FB_W-1
    constant FB_Y_W    : positive := 8; -- 0 .. FB_H-1
    constant PIXEL_W   : positive := 8; -- RGB332

    subtype fb_addr_t is unsigned(FB_ADDR_W - 1 downto 0);
    subtype fb_x_t    is unsigned(FB_X_W - 1 downto 0);
    subtype fb_y_t    is unsigned(FB_Y_W - 1 downto 0);
    subtype pixel_t   is std_logic_vector(PIXEL_W - 1 downto 0);

    -- Linear framebuff addr is y * FB_W + x, so caller must be x < FB_W and y < FB_H
    function fb_addr(x : fb_x_t; y : fb_y_t) return fb_addr_t;
end package;

package body qogpu_pkg is
    function fb_addr(x : fb_x_t; y : fb_y_t) return fb_addr_t is 
        variable a : natural;
    begin
        a := to_integer(y) * FB_W + to_integer(x);
        return to_unsigned(a, FB_ADDR_W);
    end function;
end package body;    