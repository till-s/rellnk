--LB-MIT
--
-- MIT License
--
-- Copyright (c) 2026 Till Straumann
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--
--LE-MIT

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.CrcPkg.all;

package CobsCrcPkg is

   constant CRC15_POLY_LE_C : std_logic_vector(14 downto 0) := "101100000110000";
   constant CRC15_POLY_BE_C : std_logic_vector(14 downto 0) := "000011000001101";

   -- CRC should be taken *over* the COBS encoded packet (to maximize detection
   -- of error bursts). Adding one additional bit to avoid EOF markers in
   -- the CRC:
   -- ** All the following analysis is done in a little-endian world **
   -- ** and assumes the CRC and extra bit fit in two bytes          **
   --
   -- Appending one zero-bit to the data yields some CRC (including the
   -- zero-bit) the can be split into two bytes. The first byte contains
   -- any trailing data bits, the extra bit and the high-order bits (in polynomial-view)
   -- of the CRC; the second byte contains the low-order 8 bits of the
   -- CRC:
   --    [data_byte],
   --    ...
   --    [data_byte],
   --    [crc-high-order:extra_bit(:optional_last_data_bits)]
   --    [crc-low-order-byte]
   --
   -- 'optional_data-bits' are only present if the CRC is less than 15 bits
   -- long.
   -- The idea is that when the CRC high- or low-order parts are zero
   -- (which would collide with EOF) we can use the extra bit to mitigate
   -- the situation.
   -- Due to the affine property of the CRC : CRC(a^b) = CRC(a)^CRC(b)
   -- setting the extra bit and XORing the CRC with that bit's CRC
   -- yields a valid CRC again.
   -- The CRC of the trailing extra bit is simply the polynomial itself.
   -- Because the lowest order (x^0) of the polynomial is aligned with
   -- the leftmost bit in the 'crc-low-order-byte' it is immediately clear
   -- that when the crc-low-order-byte is initially 0x00 (EOF) then setting
   -- the extra bit and XORing the CRC with the polynomial results in
   -- a non-zero crc-low-order-byte AND a non-zero second-to-last byte
   -- as well (because the extra bit is set).
   --
   -- Thus, we only have to look more carefully at the case when the
   -- crc-high-order bits are are zero. If we flip the extra bit and
   -- XOR the CRC with the polynomial then the crc-low-order byte may
   -- become zero as a result of this XOR operation.
   -- However, there is only one single possibility when this can happen
   --  1. all crc-high-order bits are zero
   --  2. the crc-low-order-byte matches the low-order byte of the polynomial
   -- Because these two conditions cover all the bits of the CRC this
   -- means that only one well-defined value needs to be handled as
   -- a corner case.
   --
   -- After XORing the corner-case with the guard bit and the polynomial
   --  1. the crc-high-order bits match the polynomial high order bits
   --  2. the crc-low-order-byte is zero.
   -- Because in all other cases extra == '1' implies that at least one of
   -- the CRC parts are zero (before XOR with the polynomial) the special
   -- value may encoded to anything matching
   --
   --    extra == '1' AND (CRC XOR POLY)_upper != 0 AND (CRC XOR POLY)_lower != 0
   --                 AND (CRC)_upper          != 0 AND (CRC)_lower          != 0
   --
   -- We can encode the special case so that the CRC has just one bit set; i.e.,
   -- we chose a MAGIC value so that, e.g., crc(MAGIC) = 0x4000 which simplifies
   -- the decoder.
   --
   -- For the polynomial 0x5830 the magic value 0xf4a produces a CRC of 0x4000.
   -- This needs to be XORed with the high-order bits of the polynomial.
   -- Since low-order byte of the magical value
   -- half the final CRC does meet the condition for the magical value.
   constant CRC15_INIT_LE_C : std_logic_vector(CRC15_POLY_LE_C'range) := CrcInitAllOnesLE(CRC15_POLY_LE_C);
   constant CRC15_INIT_BE_C : std_logic_vector(CRC15_POLY_BE_C'range) := CrcInitAllOnesBE(CRC15_POLY_BE_C);

   -- magic value to be XORed into the corner-case crc
   constant MAGIC15_LE_C    : std_logic_vector(CRC15_POLY_LE_C'range) := ("000" & x"f4a");
   constant MAGIC15_BE_C    : std_logic_vector(CRC15_POLY_BE_C'range) := ("010100101111000");

   function CRC15_OK_LE_F(
      constant g   : std_logic;
      constant crc : std_logic_vector(CRC15_POLY_LE_C'range);
      constant inv : boolean -- sender inverted CRC
   )
   return boolean;

   function CRC15_OK_BE_F(
      constant g   : std_logic;
      constant crc : std_logic_vector(CRC15_POLY_LE_C'range);
      constant inv : boolean -- sender inverted CRC
   )
   return boolean;

end package CobsCrcPkg;

package body CobsCrcPkg is

   function ite(constant c : boolean; constant t,f: std_logic_vector)
   return std_logic_vector is
   begin
      if ( c ) then return t; else return f; end if;
   end function ite;

   function CRC15_OK_LE_F(
      constant g   : std_logic;
      constant crc : std_logic_vector(CRC15_POLY_LE_C'range);
      constant inv : boolean -- sender inverted CRC
   )
   return boolean is
      constant ZER_C : std_logic_vector(crc'range) := (others => '0');
      constant CMP_C : std_logic_vector(crc'range) := ite(inv, CRC15_INIT_LE_C, ZER_C);
   begin
      return ((crc(crc'left) = CMP_C(CMP_C'left)) or (g = '1')) and (crc(crc'left - 1 downto 0) = CMP_C(crc'left - 1 downto 0));
   end function CRC15_OK_LE_F;

   function CRC15_OK_BE_F(
      constant g   : std_logic;
      constant crc : std_logic_vector(CRC15_POLY_LE_C'range);
      constant inv : boolean -- sender inverted CRC
   )
   return boolean is
   begin
      return ((not crc(0) or g) = '1') and (unsigned(crc(crc'left downto 1)) = 0);
   end function CRC15_OK_BE_F;

end package body CobsCrcPkg;
