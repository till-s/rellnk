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

entity CobsCrcLE15GenTb is
end entity CobsCrcLE15GenTb;

architecture rtl of CobsCrcLE15GenTb is

   signal clk                : std_logic := '0';
   signal rst                : std_logic := '0';

   signal datInp             : std_logic_vector(7 downto 0);
   signal vldInp             : std_logic := '0';
   signal rdyInp             : std_logic;

   signal datOut             : std_logic_vector(7 downto 0);
   signal vldOut             : std_logic;
   signal rdyOut             : std_logic := '1';

   signal datChk             : std_logic_vector(7 downto 0);
   signal vldChk             : std_logic;

   signal crcOut             : std_logic_vector(CRC15_POLY_LE_C'range) := CRC15_INIT_LE_C;
   signal guard              : std_logic_vector(1 downto 0);

   type Slv8Array is array (natural range <>) of std_logic_vector(7 downto 0);

   signal idx                : natural   := 0;
   signal don                : boolean   := false;
   signal i                  : natural   := 1;
   signal j                  : natural   := 1;

   -- iterating over ((i<<8) | j) for i,j 1..255 (to avoid EOF bytes)
   -- scans *almost* all 2**15 CRC values (but a single one). This exercises
   -- the CRC generator...
   signal feed   : Slv8Array(0 to 2) := (
      x"00",
      x"00",
      x"00"
   );

   constant FEED_C : Slv8Array := (
      x"00",
      x"00",
      x"fa", -- some data
      x"0b",
      x"00",
      x"38", -- produces 0x5800 checksum
      x"4a",
      x"00"
   );

   signal seen : natural := 0;
   signal phase: natural := 0;
   signal len  : natural := 0;

   signal rxChecked : natural := 0;
   signal rxIdx     : natural := 0;
   signal rxCmp     : unsigned(15 downto 0) := to_unsigned(256*1 + 1, 16);
   signal rxIJ      : unsigned(15 downto 0) := (others => '0');

   function NEOFS return natural is
      variable v : natural;
   begin
      v := 0;
      for ii in FEED_C'range loop
         if FEED_C(ii) = x"00" then
            v := v + 1;
         end if;
      end loop;
      return v;
   end function NEOFS;
begin

   P_CLK : process is
   begin
      clk <= not clk;
      wait for 1 us;
      if ( don ) then
         wait;
      end if;
   end process P_CLK;

   P_FEED : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( (vldOut and rdyOut) = '1' ) then
            if ( phase = 1 ) then
               len    <= len + 1;
               guard  <= datOut(0) & guard(guard'left downto 1);
               crcOut <= CrcWrdWiseLE(CRC15_POLY_LE_C, crcOut, datOut);
           end if;
            if ( datOut = x"00" ) then
               if ( phase = 1 ) then
                  assert len    = 4 report "unexpected output length" severity failure;
                  assert CRC_OK_LE_F(guard(0), crcOut, CRC15_INIT_LE_C) report "unexpected CRC" severity failure;
               end if;
               len    <= 0;
               seen   <= seen + 1;
               crcOut <= CRC15_INIT_LE_C;
            end if;
         end if;
         if ( phase = 0 and vldInp = '0' and idx = 0 ) then
            vldInp <= '1';
         end if;
         if ( (rdyInp and vldInp) = '1' ) then
            if ( phase = 0 ) then
               if (idx = FEED_C'high) then
                  vldInp <= '0';
               else
                  idx    <= idx + 1;
               end if;
            elsif ( phase = 1 ) then
               if ( idx = feed'high ) then
                  if ( i = 255 ) then
                     if ( j = 255 ) then
                        vldInp <= '0';
                     else
                        i <= 1;
                        j <= j + 1;
                     end if;
                  else
                     i <= i + 1;
                  end if;
                  idx <= 0;
               else
                  idx <= idx + 1;
               end if;
            end if;
         end if;
         if ( phase = 0 and seen = NEOFS ) then
           phase  <= phase + 1;
           idx    <= 0;
           vldInp <= '1';
         end if;
         if ( vldChk = '1' ) then
            if ( rxChecked = FEED_C'length + 255*255*feed'length - 1 ) then
               assert ( seen = NEOFS + 255*255 ) severity failure;
               don <= true;
               report "TEST PASSED";
            else
               rxChecked <= rxChecked + 1;
               if ( rxIdx < FEED_C'length ) then
                  assert ( datChk = FEED_C(rxIdx) ) severity failure;
                  rxIdx <= rxIdx + 1;
               else
                  if ( datChk = x"00" ) then
                     assert rxCmp = rxIJ severity failure;
                     rxIJ  <= (others => '0');
                     if ( rxCmp(7 downto 0) = 255 ) then
                        rxCmp <= rxCmp + 2;
                     else
                        rxCmp <= rxCmp + 1;
                     end if;
                  else
                     rxIJ <= shift_left(rxIJ, 8) or resize(unsigned(datChk), rxIJ'length);
                  end if;
               end if;
            end if;
         end if;
      end if;
   end process P_FEED;

   feed(0) <= std_logic_vector(to_unsigned(j, 8));
   feed(1) <= std_logic_vector(to_unsigned(i, 8));
   feed(2) <= x"00";

   datInp <= FEED_C(idx) when phase = 0 else feed(idx);

   U_DUT_GEN : entity work.CobsCrcLE15_22Gen
      port map (
         clk    => clk,
         rst    => rst,
         datInp => datInp,
         vldInp => vldInp,
         rdyInp => rdyInp,
         datOut => datOut,
         vldOut => vldOut,
         rdyOut => rdyOut
      );

   U_DUT_CHK : entity work.CobsCrcLE15_22Check
      generic map (
         LD_FIFO_DEPTH_G => 2,
         COBS_CHECK_EN_G => false
      )
      port map (
         clk    => clk,
         rst    => rst,
         datInp => datOut,
         vldInp => vldOut,
         rdyInp => open,

         datOut => datChk,
         vldOut => vldChk,
         rdyOut => '1'
      );


end architecture rtl;


