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

entity CobsCrcLE15CheckTb is
end entity CobsCrcLE15CheckTb;

architecture rtl of CobsCrcLE15CheckTb is

   signal clk                : std_logic := '0';
   signal rst                : std_logic := '0';

   signal datInp             : std_logic_vector(7 downto 0);
   signal vldInp             : std_logic := '0';
   signal rdyInp             : std_logic;

   signal jam                : std_logic_vector(7 downto 0) := (others => '0');
   signal dropping           : std_logic;

   signal datOut             : std_logic_vector(7 downto 0);
   signal datJam             : std_logic_vector(7 downto 0);
   signal vldOut             : std_logic;
   signal rdyOut             : std_logic := '1';

   signal datChk             : std_logic_vector(7 downto 0);
   signal vldChk             : std_logic;
   signal rdyChk             : std_logic := '1';

   type Slv8Array is array (natural range <>) of std_logic_vector(7 downto 0);

   signal idx                : natural   := 0;
   signal don                : boolean   := false;

   -- must be COBS encoded
   constant FEED_C : Slv8Array := (
      x"00", -- npkt 1
      x"00", -- npkt 2
      x"03",
      x"fa", -- some data
      x"0b",
      x"00", -- npkt 3
      x"03",
      x"38", -- produces 0x5800 checksum
      x"4a",
      x"00", -- npkt 4
      x"07",
      x"01",
      x"02",
      x"03",
      x"04",
      x"05",
      x"06",
      x"00", -- npkt 5
      x"04",
      x"0a",
      x"0b",
      x"0c",
      x"00"  -- npkt 6
   );

   procedure tic is
   begin
      wait until rising_edge(clk);
   end procedure tic;

   function dojam(constant o : integer; constant jidx : integer) return std_logic is
   begin
     if (o = jidx) then return '1'; else return '0'; end if;
   end function dojam;

   procedure rcv(variable s : inout natural; signal j: out std_logic; constant jidx: integer := -1) is
      variable o : natural;
   begin
      o := 0;
      L_1 : while ( true ) loop
         L_2 : while (true) loop
            if ( dropping = '1' ) then
               assert jidx >= 0 severity failure;
               while ( dropping = '1' ) loop
                  tic;
               end loop;
               -- restore
               s := s;
               j <= '0';
               return;
            end if;
            if ( (rdyChk and vldChk) = '1' ) then
               exit L_2;
            end if;
            tic;
         end loop;
         report integer'image(s) & " " & integer'image(o) & " " & integer'image(to_integer(unsigned(datChk)));
         assert (datChk = FEED_C(s + o)) report "datChk " & integer'image(to_integer(unsigned(datChk))) severity failure; 
         if ( datChk = x"00" ) then
            s := s + o + 1;
            j <= dojam(o + 1,jidx);
            exit L_1;
         end if;
         o := o + 1;
         tic;
      end loop;
   end procedure rcv;

   procedure snd(signal v : out std_logic; signal i : inout natural; signal j : out std_logic; constant jidx: integer := -1) is
      variable s : natural;
      variable o : natural;
   begin
      tic;
      s := i;
      o := 0;
      i <= s + o;
      j <= dojam(o,jidx);
      v <= '1';
      tic;
      L_1 : while ( true ) loop
         while ( rdyInp = '0' ) loop
            tic;
         end loop;
         if ( datInp = x"00" ) then
            exit L_1;
         end if;
         o := o + 1;
         i <= s + o;
         j <= dojam(o,jidx);
         tic;
      end loop;
      v <= '0';
      j <= '0';
      i <= s + o + 1;
      tic;
   end procedure snd;

   procedure xfr(signal v : out std_logic; signal i : inout natural; signal j : out std_logic; constant jidx: integer := -1) is
      variable s : natural;
   begin
      s := i;
      snd(v, i, j, jidx);
      rcv(s, j, jidx);
      i <= s;
      tic;
   end procedure xfr;

begin

   P_CLK : process is
   begin
      clk <= not clk;
      wait for 1 us;
      if ( don ) then
         wait;
      end if;
   end process P_CLK;

   datInp <= FEED_C(idx) when idx < FEED_C'length else (others => 'U');
   datJam <= datOut xor jam;

   P_FEED : process is
      variable jtst      : integer;
      variable startPkt1 : integer;
      variable startPkt2 : integer;
      variable npkt      : integer;
   begin
      npkt := 0;
      while ( npkt < 4 ) loop
         jtst := idx;
         xfr(vldInp, idx, jam(0), 1);
         if ( idx = jtst ) then
            -- retry
            xfr(vldInp, idx, jam(0), -1);
         end if;
         npkt := npkt + 1;
      end loop;
      rdyChk <= '0';
      tic;
      -- first packet into fifo
      startPkt1 := idx;
      snd(vldInp, idx, jam(0), -1);
      startPkt2 := idx;
      -- 2nd packet does not fit in fifo; should be dropped
      xfr(vldInp, idx, jam(0), 100);
      assert ( idx = startPkt2 ) severity failure;
      -- verify first packet
      rdyChk <= '1';
      rcv(startPkt1, jam(0), -1);
      -- last packet
      xfr(vldInp, idx, jam(0), 1);
      don <= true;
      report "TEST PASSED";
      wait;
   end process P_FEED;


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
         LD_FIFO_DEPTH_G => 3,
         COBS_CHECK_EN_G => true
      )
      port map (
         clk             => clk,
         rst             => rst,
         datInp          => datJam,
         vldInp          => vldOut,
         rdyInp          => open,

         datOut          => datChk,
         vldOut          => vldChk,
         rdyOut          => rdyChk,
         dropping        => dropping
      );


end architecture rtl;
