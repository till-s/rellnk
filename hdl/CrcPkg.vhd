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

package CrcPkg is
   function CrcBitWiseLE(constant POLY: in std_logic_vector; constant data: in std_logic_vector) return std_logic_vector;

   function CrcWrdWiseLE(constant POLY: in std_logic_vector; constant crc : in std_logic_vector; constant data: in std_logic_vector) return std_logic_vector;

   function CrcBitWiseBE(constant POLY: in std_logic_vector; constant data: in std_logic_vector) return std_logic_vector;
end package CrcPkg;

package body CrcPkg is
   function max_loc(constant a,b : in integer) return integer is
   begin
      if ( a > b ) then return a; else return b; end if;
   end function max_loc;

   function CrcBitWiseLE(constant POLY: in std_logic_vector; constant data: in std_logic_vector) return std_logic_vector is
      variable v : std_logic_vector(max_loc(POLY'length, data'length) - 1 downto 0);
      variable s : std_logic;
   begin
      v := std_logic_vector(resize(unsigned(data), v'length));
      for i in 1 to data'length loop
         s := v(0);
         v := '0' & v(v'left downto 1);
         if ( s = '1' ) then
            v := v xor std_logic_vector(resize(unsigned(POLY), v'length));
         end if;
      end loop;
      return v;
   end function CrcBitWiseLE;

   function CrcWrdWiseLE(constant POLY: in std_logic_vector; constant crc : in std_logic_vector; constant data: in std_logic_vector) return std_logic_vector is
   begin
      return std_logic_vector(shift_right(unsigned(crc), data'length)) xor CrcBitWiseLE(POLY, crc(data'range) xor data);
   end function CrcWrdWiseLE;

   function CrcBitWiseBE(constant POLY: in std_logic_vector; constant data: in std_logic_vector) return std_logic_vector is
      variable v : std_logic_vector(max_loc(POLY'length, data'length) - 1 downto 0);
      variable s : std_logic;
   begin
      v := std_logic_vector(resize(unsigned(data), v'length));
      for i in 1 to data'length loop
         s := v(v'left);
         v := v(v'left - 1 downto 0) & '0';
         if ( s = '1' ) then
            v := v xor POLY;
         end if;
      end loop;
      return v;
   end function CrcBitWiseBE;

end package body CrcPkg;
