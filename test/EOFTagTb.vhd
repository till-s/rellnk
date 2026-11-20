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

entity EOFTagTb is
end entity EOFTagTb;

architecture sim of EOFTagTb is
   subtype Slv8Type  is std_logic_vector(7 downto 0);
   subtype Slv9Type  is std_logic_vector(8 downto 0);
   type    Slv8Array is array(natural range <>) of Slv8Type;
   type    Slv9Array is array(natural range <>) of Slv9Type;
   type    IntArray  is array(natural range <>) of integer;

   constant FEED_C : Slv9Array := (
      "0" & x"00",
      "1" & x"01",
      "0" & x"00",
      "0" & x"00",
      "0" & x"01",
      "0" & x"02",
      "1" & x"03",
      "0" & x"00"
   );

   signal clk     : std_logic := '0';
   signal don     : boolean   := false;
   signal oVld    : std_logic;
   signal iVld    : std_logic := '0';
   signal oRdy    : std_logic := '0';
   signal iRdy    : std_logic;
   signal oLst    : std_logic;
   signal oIdx    : integer   := 0;
   signal iIdx    : integer   := 0;
   signal iDat    : Slv8Type;
   signal oDat    : Slv8Type;
   signal iPhas   : integer   := 0;
   signal oPhas   : integer   := 0;
   signal nOk     : integer   := 0;

   constant IWAI_C: IntArray  := (0, 2);
   constant OWAI_C: IntArray  := (0, 0, 3, 3, -1);

   procedure tic is
   begin
      wait until rising_edge(clk);
   end procedure tic;

   procedure feed is
   begin
      while ( iidx < FEED_C'high ) loop
        tic;
      end loop;
   end procedure feed;

begin

   P_CLK : process is
   begin
      wait for 10 us;
      clk <= not clk;
      if don then
         wait;
      end if;
   end process P_CLK;

   P_FEED : process ( clk ) is
      variable w : integer := 0;
   begin
      if ( rising_edge( clk ) ) then
         if ( (iVld and iRdy) = '1' ) then
            iIdx <= iIdx + 1;
            if ( iIdx = FEED_C'high ) then
               iIdx <= 0;
               if ( iPhas < IWAI_C'high ) then
                  iPhas <= iPhas + 1;
               else
                  iPhas <= 0;
               end if;
               iVld <= '0';
            end if;
            if ( IWAI_C(iPhas) /= 0 ) then
               iVld <= '0';
            end if;
         end if;
         if ( iVld = '0' and IWAI_C(iPhas) >= 0 ) then
            w := w + 1;
            if ( w >= IWAI_C(iPhas) ) then
               iVld <= '1';
               w  := 0;
            end if;
         end if;
      end if;
   end process P_FEED;

   P_CHECK : process ( clk ) is
      variable w : integer := 0;
      variable i : integer;
   begin
      if ( rising_edge( clk ) ) then
         if ( (oRdy and oVld) = '1' ) then
            assert (oLst & oDat) = FEED_C(oidx) report "data mismatch" severity failure;
            nOk <= nOk + 1;
            i := oidx;
            L_NXT : while ( true ) loop
               i := i + 1;
               if ( i >= FEED_C'high ) then
                  i     :=  0;
                  oRdy  <= '0';
                  oPhas <= oPhas + 1;
               end if;
               if ( FEED_C(i) /= "000000000" ) then
                  exit L_NXT;
               end if;
            end loop L_NXT;
            oidx <= i;
            if ( OWAI_C(oPhas) /= 0 ) then
            oidx <= i;
               oRdy <= '0';
            end if;
         end if;
         if ( oRdy = '0' and OWAI_C(oPhas) >= 0 ) then
            L_NXT1 : for n in oIdx to FEED_C'high loop
               if ( FEED_C(n) /= "000000000" ) then
                  oIdx <= n;
                  exit L_NXT1;
               end if;
            end loop L_NXT1;
            w := w + 1;
            if ( w >= OWAI_C(oPhas) ) then
               oRdy <= '1';
               w    := 0;
            end if;
         end if;
      end if;
   end process P_CHECK;


   P_CTL : process is
   begin
      while (oPhas < OWAI_C'high) loop
         tic;
      end loop;
      assert nOk = 16 report "Missing test" severity failure;
      report "Test PASSED";
      don <= true;
      wait;
   end process P_CTL;

   idat <= FEED_C(iIdx)(7 downto 0);

   U_DUT : entity work.EOFTag
      port map (
         clk    => clk,
         rst    => '0',
         datInp => iDat,
         vldInp => iVld,
         rdyInp => iRdy,

         datOut => oDat,
         vldOut => oVld,
         rdyOut => oRdy,
         lstOut => oLst
      );

end architecture sim;

