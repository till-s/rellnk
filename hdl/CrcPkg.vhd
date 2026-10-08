library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package CrcPkg is
   function CrcBitWiseLE(constant POLY: in std_logic_vector; constant data: in std_logic_vector) return std_logic_vector;

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
            v := v xor POLY;
         end if;
      end loop;
      return v;
   end function CrcBitWiseLE;

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
