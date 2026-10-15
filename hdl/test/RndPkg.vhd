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
use     ieee.math_real.all;

package RndPkg is

   -- PRN scaled and converted to unsigned/std_logic_vector
   procedure rnd(variable s1, s2: inout positive; variable o : out unsigned);
   procedure rnd(variable s1, s2: inout positive; variable o : out std_logic_vector);

end package RndPkg;

package body RndPkg is

   procedure rnd(variable s1, s2: inout positive; variable o : out unsigned) is
      variable v : real;
   begin
      uniform(s1, s2, v);
      o := to_unsigned(integer(floor((2.0**o'length)*v)), o'length);
   end procedure rnd;

   procedure rnd(variable s1, s2: inout positive; variable o : out std_logic_vector) is
      variable v : unsigned(o'range);
   begin
      rnd(s1, s2, v);
      o := std_logic_vector(v);
   end procedure rnd;

end package body RndPkg;
