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
use     work.CobsCrcPkg.all;

-- Append little-endian CRC to a COBS-encoded stream.
-- (CRC is computed over the encoded stream in order
-- to maintain the burst-detecting properties of the CRC).
-- A guard bit is used to ensure the CRC does not have
-- null/EOF bytes.

entity CobsCrcGen is
   generic (
      COBS_EOF_G     : std_logic_vector(7 downto 0) := x"00"
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic;
      datInp         : in  std_logic_vector(7 downto 0);
      vldInp         : in  std_logic;
      rdyInp         : out std_logic;

      datOut         : out std_logic_vector(7 downto 0);
      vldOut         : out std_logic;
      rdyOut         : in  std_logic
   );
end entity CobsCrcGen;

architecture rtl of CobsCrcGen is

   -- 'left' part of the polynomial; since this is little-endian these
   -- bits correspond to the 'lower' order terms
   constant P_L_C      : std_logic_vector(14 downto 7) := CRC15_POLY_LE_C(14 downto 7);
   -- 'right' part of the polynomial; since this is little-endian these
   -- bits correspond to the 'higher' order terms
   constant P_R_C      : std_logic_vector( 6 downto 0) := CRC15_POLY_LE_C( 6 downto 0 );

   type StateType is (RUN, FIX_CRC, APPEND_CRC_1, APPEND_CRC_2, APPEND_EOF);

   type RegType   is record
      state       : StateType;
      crc         : std_logic_vector(CRC15_POLY_LE_C'range);
      guard       : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => RUN,
      crc         => CRC15_INIT_LE_C,
      guard       => '0'
   );

   signal r       : RegType := REG_INIT_C;
   signal rin     : RegType;

begin

   P_COMB : process (r, datInp, vldInp, rdyOut) is
      variable v          : RegType;
      constant BIT_ZERO_C : std_logic_vector(0 downto 0) := "0";
   begin
      v          := r;
      datOut     <= datInp;
      vldOut     <= vldInp;
      rdyInp     <= rdyOut;
      case ( r.state ) is
         when RUN        =>
            if ( ( vldInp and rdyOut ) = '1' ) then
               v.crc := CrcWrdWiseLE(CRC15_POLY_LE_C, r.crc, datInp);
               if ( COBS_EOF_G = datInp ) then
                  -- stop output (but consume input)
                  vldOut  <= '0';
                  v.state := FIX_CRC;
                  -- EOF does not go into CRC but add the guard bit ('0' for now)
                  v.crc   := CrcWrdWiseLE(CRC15_POLY_LE_C, r.crc, BIT_ZERO_C);
               end if;
            end if;

         when FIX_CRC    =>
            rdyInp <= '0'; -- stop input
            vldOut <= '0'; -- stop output
            -- massage the guard bit
            if    ( r.crc(P_L_C'range) = COBS_EOF_G ) then
               v.guard := '1';
               v.crc   := r.crc xor CRC15_POLY_LE_C;
            elsif ( r.crc(P_R_C'range) = (P_R_C xor P_R_C) ) then -- (X xor X) for zero
               v.guard := '1';
               v.crc   := r.crc xor CRC15_POLY_LE_C;
               -- corner case where XORing the guard bit and its crc would
               -- zero out the leftmost 8 bits. Mark this by using a magic
               -- value with bits in both halves set.
               -- (both halves of the CRC AND the guard bits being
               -- nonzero cannot happen otherwise).
               if ( r.crc(P_L_C'range) = P_L_C ) then
                  v.crc := r.crc xor CRC15_POLY_LE_C xor MAGIC15_LE_C;
               end if;
            end if;
            v.state := APPEND_CRC_1;

         when APPEND_CRC_1 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '1';
            datOut <= r.crc(P_R_C'range) & r.guard;
            if ( rdyOut = '1' ) then
               v.state := APPEND_CRC_2;
            end if;

         when APPEND_CRC_2 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '1';
            datOut <= r.crc(P_L_C'range);
            if ( rdyOut = '1' ) then
               v.state := APPEND_EOF;
            end if;

         when APPEND_EOF   =>
            rdyInp  <= '0'; -- stop input
            vldOut  <= '1';
            datOut  <= COBS_EOF_G;
            v.crc   := CRC15_INIT_LE_C;
            v.guard := '0';
            if ( rdyOut = '1' ) then
               v.state := RUN;
            end if;
      end case;
      rin        <= v;
   end process;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

end architecture rtl;
