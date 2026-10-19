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

entity CobsCrcLE15_22Gen is
   generic (
      POLY_G         : std_logic_vector := CRC15_POLY_LE_C;
      -- initial value ('leading-zeroes' detection)
      CRC_INIT_G     : std_logic_vector(14 downto 0) := CRC15_INIT_LE_C;

      -- magic value; crc(POLY_G, MAGIC_G) must yield x"4000"; see CobsCrcPkg
      -- only used if POLY_G'length = 15 (single guard bit)
      MAGIC_G        : std_logic_vector := MAGIC15_LE_C;
      -- whether to append inverted CRC ('trailing-zeroes' detection)
      CRC_INVERT_G   : boolean                       := true;
      COBS_EOF_G     : std_logic_vector(7 downto 0)  := x"00"
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic;
      datInp         : in  std_logic_vector(7 downto 0);
      vldInp         : in  std_logic;
      rdyInp         : out std_logic;
      -- user bits that are stored into the first CRC byte (after the last
      -- payload byte). Only available if the poly + 2 guard bits leave space).
      -- Latched on the last data beat (before COBS_EOF_G)
      usrInp         : in  std_logic_vector(CobsCrc15_22UsrBits(POLY_G) - 1 downto 0) := (others => '0');


      datOut         : out std_logic_vector(7 downto 0);
      vldOut         : out std_logic;
      rdyOut         : in  std_logic
   );
end entity CobsCrcLE15_22Gen;

architecture rtl of CobsCrcLE15_22Gen is

   constant POLY_N_BYTES_C     : natural          := (POLY_G'length + 7)/8;

   -- 'left' part of the polynomial; since this is little-endian these
   -- bits correspond to the 'lower' order terms
   constant P_L_C              : std_logic_vector := POLY_G(POLY_G'left - 0 downto POLY_G'left -  7);

   -- 'middle' part of the polynomial; since this is little-endian these
   -- bits correspond to the 'medium' order terms
   constant P_M_C              : std_logic_vector := POLY_G(POLY_G'left - 8 downto POLY_G'left - 8*(POLY_N_BYTES_C-1) + 1);
   -- 'right' part of the polynomial; since this is little-endian these
   -- bits correspond to the 'highest' order terms
   constant P_R_C              : std_logic_vector := POLY_G(POLY_G'left - 8*(POLY_N_BYTES_C-1) downto 0);

   -- right-shifted polynomial
   constant POLY_R_C           : std_logic_vector := '0' & POLY_G(POLY_G'left downto 1);
   -- ls-bit of right-shifted polynomial spills into guard bits
   constant POLY_R_GRD_C       : std_logic        := POLY_G(0);

   type StateType is (RUN, FIX_CRC_15, FIX_CRC_16_22, APPEND_CRC_1, APPEND_CRC_2, APPEND_CRC_3, APPEND_EOF);

   type RegType   is record
      state       : StateType;
      crc         : std_logic_vector(POLY_G'range);
      usr         : std_logic_vector(usrInp'range);
      guard       : std_logic_vector(CobsCrc15_22GuardBits(POLY_G) - 1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => RUN,
      crc         => CRC_INIT_G,
      usr         => (others => '0'),
      guard       => (others => '0')
   );

   signal r       : RegType := REG_INIT_C;
   signal rin     : RegType;

   function CRC_OUT(constant x : std_logic_vector) return std_logic_vector is
   begin
      if ( CRC_INVERT_G ) then
         return not x;
      else
         return x;
      end if;
   end function CRC_OUT;

begin

   assert POLY_G'left = CRC_INIT_G'left and POLY_G'right = CRC_INIT_G'right
      report "Mismatch between polynomial and initial value ranges"
      severity failure;

   assert CobsCrcLE15_22Acceptable(POLY_G)
      report "CRC Polynomial not acceptable"
      severity failure;

   P_COMB : process (r, datInp, vldInp, rdyOut) is
      variable v          : RegType;
      variable lastBits   : std_logic_vector(r.guard'length + r.usr'length - 1 downto 0);
   begin
      v          := r;
      datOut     <= datInp;
      vldOut     <= vldInp;
      rdyInp     <= rdyOut;
      -- ghdl didn't like concatenation as function arg below when usr'length = 0
      -- it complained about slice direction mismatch; use intermediate var.
      lastBits   := r.guard & r.usr;
      case ( r.state ) is
         when RUN        =>
            if ( ( vldInp and rdyOut ) = '1' ) then
               v.crc := CrcWrdWiseLE(POLY_G, r.crc, datInp);
               v.usr := usrInp;
               if ( COBS_EOF_G = datInp ) then
                  -- stop output (but consume input)
                  vldOut  <= '0';
                  if ( POLY_G'length = 15 ) then
                     v.state := FIX_CRC_15;
                  else
                     v.state := FIX_CRC_16_22;
                  end if;
                  v.usr   := r.usr;
                  -- EOF does not go into CRC but add the guard and usr bits ('0' for now)
		  -- also: (optionally) invert CRC (standard way to detect trailing zeros)
                  v.crc   := CRC_OUT( CrcWrdWiseLE(POLY_G, r.crc, lastBits) );
               end if;
            end if;

         when FIX_CRC_15 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '0'; -- stop output
            -- massage the guard bit
            if    ( r.crc(P_L_C'range) = COBS_EOF_G ) then
               v.guard(0) := '1';
               v.crc   := r.crc xor POLY_G;
            elsif ( r.crc(P_R_C'range) = (P_R_C xor P_R_C) ) then -- (X xor X) for zero
               v.guard(0) := '1';
               v.crc   := r.crc xor POLY_G;
               -- corner case where XORing the guard bit and its crc would
               -- zero out the leftmost 8 bits. Mark this by using a magic
               -- value with bits in both halves set.
               -- (both halves of the CRC AND the guard bits being
               -- nonzero cannot happen otherwise).
               if ( r.crc(P_L_C'range) = P_L_C ) then
                  v.crc := r.crc xor POLY_G xor MAGIC_G;
               end if;
            end if;
            v.state := APPEND_CRC_1;

         when FIX_CRC_16_22 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '0'; -- stop output
            -- select guards

            -- try first guard
            v.crc  := r.crc xor POLY_G;
            if ( v.crc(P_L_C'range) /= COBS_EOF_G and v.crc(P_M_C'range) /= COBS_EOF_G ) then
               -- acceptable; neigher byte is erased by the first guard
               v.guard(1) := '1';
            else
               -- at least one byte would be erased to EOF by applying the first guard; try
               -- the alternate
               v.crc := r.crc xor POLY_R_C;
               if ( v.crc(P_L_C'range) /= COBS_EOF_G and v.crc(P_M_C'range) /= COBS_EOF_G ) then
                  -- acceptable; neigher byte is erased by the alternate guard
                  v.guard := POLY_R_GRD_C & '1';
               else
                  -- the first guard erased at least one of the bytes and so did the
                  -- second; this is only possible if each guard erased a different byte.
                  -- thus, both guards must be applied.
                  v.crc   := r.crc xor POLY_G xor POLY_R_C;
                  v.guard := (POLY_R_GRD_C xor '1') & '1';
               end if;
            end if;
            v.state := APPEND_CRC_1;

         when APPEND_CRC_1 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '1';
            datOut <= r.crc(P_R_C'range) & lastBits;
            if ( rdyOut = '1' ) then
               if ( POLY_G'length = 15 ) then
                  -- proceed directly to last byte
                  v.state := APPEND_CRC_3;
               else
                  v.state := APPEND_CRC_2;
               end if;
            end if;

         when APPEND_CRC_2 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '1';
            datOut <= r.crc(P_L_C'range);
            if ( rdyOut = '1' ) then
               v.state := APPEND_EOF;
            end if;

         when APPEND_CRC_3 =>
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
            v.crc   := CRC_INIT_G;
            v.guard := (others => '0');
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
