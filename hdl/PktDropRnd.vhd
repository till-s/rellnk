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

-- drop packets

entity PktDropRnd is
   generic (
      LD_RND_G        : natural;
      SEED_1_G        : positive;
      SEED_2_G        : positive;
      DATA_WIDTH_G    : natural := 8
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      ena             : in  std_logic := '1';
      ack             : out std_logic;

      datInp          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldInp          : in  std_logic;
      lstInp          : in  std_logic;
      rdyInp          : out std_logic;

      datOut          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldOut          : out std_logic;
      lstOut          : out std_logic;
      rdyOut          : in  std_logic
   );
end entity PktDropRnd;

architecture rtl of PktDropRnd is

   signal trgLoc      : std_logic := '0';
   signal rnds        : signed(LD_RND_G downto 0);

begin

   P_SEQ  : process ( clk ) is
      variable s1 : positive := SEED_1_G;
      variable s2 : positive := SEED_2_G;
      variable  u : unsigned(LD_RND_G - 1 downto 0);
      variable  s : signed  (LD_RND_G     downto 0);
   begin
      if ( rising_edge( clk ) ) then
         trgLoc <= '0';
         if ( rst = '1' ) then
	    s1     := SEED_1_G;
	    s2     := SEED_2_G;
         else
	    rnd(s1, s1, u);
	    s := signed(resize(u, s'length)) - 1;
            rnds   <= s;
	    trgLoc <= (s(s'left) and ena);
         end if;
      end if;
   end process P_SEQ;

   U_DUMP : entity work.PktDrop
      generic map (
         DATA_WIDTH_G    => DATA_WIDTH_G
      )
      port map (
         clk             => clk,
         rst             => rst,

         trg             => trgLoc,
         ack             => ack,

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
