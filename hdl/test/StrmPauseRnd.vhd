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

use     work.RndPkg.all;

entity StrmPauseRnd is
   generic (
      LD_PAUSE_G      : natural;
      SEED_1_G        : positive;
      SEED_2_G        : positive;
      FIXED_STALL_G   : integer := -1;
      DATA_WIDTH_G    : natural := 8
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      datInp          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldInp          : in  std_logic;
      lstInp          : in  std_logic;
      rdyInp          : out std_logic;

      datOut          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldOut          : out std_logic;
      lstOut          : out std_logic;
      rdyOut          : in  std_logic
   );
end entity StrmPauseRnd;

architecture rtl of StrmPauseRnd is
   signal trg  : std_logic := '1';
   signal ack  : std_logic;
   signal pass : unsigned(LD_PAUSE_G - 1 downto 0) := (others => '0');
   signal paus : unsigned(LD_PAUSE_G - 1 downto 0) := (others => '0');
begin

   G_RND_STALL : if ( FIXED_STALL_G < 0 ) generate
   begin
      P_RND : process ( clk ) is
         variable s1 : positive := SEED_1_G;
         variable s2 : positive := SEED_2_G;
         variable  u : unsigned(pass'range);
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               s1 := SEED_1_G;
               s2 := SEED_2_G;
               trg <= '0';
            else
               trg <= '0';
               if ( ack = '1' ) then
                  rnd(s1,s2,u);
                  pass <= u;
                  rnd(s1,s2,u);
                  paus <= u;
                  trg  <= '1';
               end if;
            end if;
         end if;
      end process P_RND;
   end generate G_RND_STALL;

   G_FIXED_STALL : if ( FIXED_STALL_G >= 0 ) generate
   begin
      trg  <= '1';
      pass <= (others => '0');
      paus <= to_unsigned(FIXED_STALL_G, paus'length);
   end generate G_FIXED_STALL;

   U_PAUSE_OUT : entity work.StrmPause
      generic map (
         LD_PAUSE_G      => pass'length,
         DATA_WIDTH_G    => DATA_WIDTH_G
      )
      port map (
         clk             => clk,
         rst             => rst,

         trg             => trg,
         -- let 'pass' transactions go undisturbed before the pause is enforced
         pass            => pass,
         pause           => paus,
         -- asserted for the VLD/RDY cycle when the pause expired
         pauseAck        => ack,

         datInp          => datInp,
         vldInp          => vldInp,
         lstInp          => lstInp,
         rdyInp          => rdyInp,

         datOut          => datOut,
         vldOut          => vldOut,
         lstOut          => lstOut,
         rdyOut          => rdyOut
      );
end architecture rtl;
