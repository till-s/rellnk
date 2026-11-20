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

entity CobsDecoderTb is
end entity CobsDecoderTb;

architecture sim of CobsDecoderTb is
   subtype Slv8Type  is std_logic_vector(7 downto 0);
   subtype Slv9Type  is std_logic_vector(8 downto 0);
   type    Slv8Array is array(natural range <>) of Slv8Type;
   type    Slv9Array is array(natural range <>) of Slv9Type;
   type    IntArray  is array(natural range <>) of integer;

   constant FEED_C : Slv9Array := (
      "0" & x"00",
      "0" & x"01",
      "1" & x"01",
      "0" & x"00",
      "0" & x"03",
      "0" & x"02",
      "0" & x"03",
      "0" & x"02",
      "1" & x"a0",
      "0" & x"00",
      "0" & x"01",
      "0" & x"ff",
      "0" & x"01",
      "0" & x"02",
      "0" & x"03",
      "0" & x"04",
      "0" & x"05",
      "0" & x"06",
      "0" & x"07",
      "0" & x"08",
      "0" & x"09",
      "0" & x"0a",
      "0" & x"0b",
      "0" & x"0c",
      "0" & x"0d",
      "0" & x"0e",
      "0" & x"0f",
      "0" & x"10",
      "0" & x"11",
      "0" & x"12",
      "0" & x"13",
      "0" & x"14",
      "0" & x"15",
      "0" & x"16",
      "0" & x"17",
      "0" & x"18",
      "0" & x"19",
      "0" & x"1a",
      "0" & x"1b",
      "0" & x"1c",
      "0" & x"1d",
      "0" & x"1e",
      "0" & x"1f",
      "0" & x"20",
      "0" & x"21",
      "0" & x"22",
      "0" & x"23",
      "0" & x"24",
      "0" & x"25",
      "0" & x"26",
      "0" & x"27",
      "0" & x"28",
      "0" & x"29",
      "0" & x"2a",
      "0" & x"2b",
      "0" & x"2c",
      "0" & x"2d",
      "0" & x"2e",
      "0" & x"2f",
      "0" & x"30",
      "0" & x"31",
      "0" & x"32",
      "0" & x"33",
      "0" & x"34",
      "0" & x"35",
      "0" & x"36",
      "0" & x"37",
      "0" & x"38",
      "0" & x"39",
      "0" & x"3a",
      "0" & x"3b",
      "0" & x"3c",
      "0" & x"3d",
      "0" & x"3e",
      "0" & x"3f",
      "0" & x"40",
      "0" & x"41",
      "0" & x"42",
      "0" & x"43",
      "0" & x"44",
      "0" & x"45",
      "0" & x"46",
      "0" & x"47",
      "0" & x"48",
      "0" & x"49",
      "0" & x"4a",
      "0" & x"4b",
      "0" & x"4c",
      "0" & x"4d",
      "0" & x"4e",
      "0" & x"4f",
      "0" & x"50",
      "0" & x"51",
      "0" & x"52",
      "0" & x"53",
      "0" & x"54",
      "0" & x"55",
      "0" & x"56",
      "0" & x"57",
      "0" & x"58",
      "0" & x"59",
      "0" & x"5a",
      "0" & x"5b",
      "0" & x"5c",
      "0" & x"5d",
      "0" & x"5e",
      "0" & x"5f",
      "0" & x"60",
      "0" & x"61",
      "0" & x"62",
      "0" & x"63",
      "0" & x"64",
      "0" & x"65",
      "0" & x"66",
      "0" & x"67",
      "0" & x"68",
      "0" & x"69",
      "0" & x"6a",
      "0" & x"6b",
      "0" & x"6c",
      "0" & x"6d",
      "0" & x"6e",
      "0" & x"6f",
      "0" & x"70",
      "0" & x"71",
      "0" & x"72",
      "0" & x"73",
      "0" & x"74",
      "0" & x"75",
      "0" & x"76",
      "0" & x"77",
      "0" & x"78",
      "0" & x"79",
      "0" & x"7a",
      "0" & x"7b",
      "0" & x"7c",
      "0" & x"7d",
      "0" & x"7e",
      "0" & x"7f",
      "0" & x"80",
      "0" & x"81",
      "0" & x"82",
      "0" & x"83",
      "0" & x"84",
      "0" & x"85",
      "0" & x"86",
      "0" & x"87",
      "0" & x"88",
      "0" & x"89",
      "0" & x"8a",
      "0" & x"8b",
      "0" & x"8c",
      "0" & x"8d",
      "0" & x"8e",
      "0" & x"8f",
      "0" & x"90",
      "0" & x"91",
      "0" & x"92",
      "0" & x"93",
      "0" & x"94",
      "0" & x"95",
      "0" & x"96",
      "0" & x"97",
      "0" & x"98",
      "0" & x"99",
      "0" & x"9a",
      "0" & x"9b",
      "0" & x"9c",
      "0" & x"9d",
      "0" & x"9e",
      "0" & x"9f",
      "0" & x"a0",
      "0" & x"a1",
      "0" & x"a2",
      "0" & x"a3",
      "0" & x"a4",
      "0" & x"a5",
      "0" & x"a6",
      "0" & x"a7",
      "0" & x"a8",
      "0" & x"a9",
      "0" & x"aa",
      "0" & x"ab",
      "0" & x"ac",
      "0" & x"ad",
      "0" & x"ae",
      "0" & x"af",
      "0" & x"b0",
      "0" & x"b1",
      "0" & x"b2",
      "0" & x"b3",
      "0" & x"b4",
      "0" & x"b5",
      "0" & x"b6",
      "0" & x"b7",
      "0" & x"b8",
      "0" & x"b9",
      "0" & x"ba",
      "0" & x"bb",
      "0" & x"bc",
      "0" & x"bd",
      "0" & x"be",
      "0" & x"bf",
      "0" & x"c0",
      "0" & x"c1",
      "0" & x"c2",
      "0" & x"c3",
      "0" & x"c4",
      "0" & x"c5",
      "0" & x"c6",
      "0" & x"c7",
      "0" & x"c8",
      "0" & x"c9",
      "0" & x"ca",
      "0" & x"cb",
      "0" & x"cc",
      "0" & x"cd",
      "0" & x"ce",
      "0" & x"cf",
      "0" & x"d0",
      "0" & x"d1",
      "0" & x"d2",
      "0" & x"d3",
      "0" & x"d4",
      "0" & x"d5",
      "0" & x"d6",
      "0" & x"d7",
      "0" & x"d8",
      "0" & x"d9",
      "0" & x"da",
      "0" & x"db",
      "0" & x"dc",
      "0" & x"dd",
      "0" & x"de",
      "0" & x"df",
      "0" & x"e0",
      "0" & x"e1",
      "0" & x"e2",
      "0" & x"e3",
      "0" & x"e4",
      "0" & x"e5",
      "0" & x"e6",
      "0" & x"e7",
      "0" & x"e8",
      "0" & x"e9",
      "0" & x"ea",
      "0" & x"eb",
      "0" & x"ec",
      "0" & x"ed",
      "0" & x"ee",
      "0" & x"ef",
      "0" & x"f0",
      "0" & x"f1",
      "0" & x"f2",
      "0" & x"f3",
      "0" & x"f4",
      "0" & x"f5",
      "0" & x"f6",
      "0" & x"f7",
      "0" & x"f8",
      "0" & x"f9",
      "0" & x"fa",
      "0" & x"fb",
      "0" & x"fc",
      "0" & x"fd",
      "0" & x"fe",
      "0" & x"02",
      "1" & x"ff",
      "0" & x"00",
      "0" & x"00" -- sentinel
   );

   signal clk     : std_logic := '0';
   signal don     : boolean   := false;

   signal iVld    : std_logic;
   signal iRdy    : std_logic;
   signal iDat    : std_logic_vector(7 downto 0);
   signal oVld    : std_logic;
   signal oRdy    : std_logic := '1';
   signal oLst    : std_logic;
   signal oDat    : std_logic_vector(7 downto 0);

   signal iIdx    : integer := 0;

   procedure tic is
   begin
      wait until rising_edge(clk);
   end procedure tic;

begin

   iVld <= '1' when iIdx < FEED_C'high else '0';
   iDat <= FEED_C(iIdx)(iDat'range);

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
            if ( iIdx < FEED_C'high ) then
               iIdx <= iIdx + 1;
            end if;
         end if;
      end if;
   end process P_FEED;

   P_CTL : process is
   begin
      while ( iIdx < FEED_C'high ) loop
         tic;
      end loop;
      don <= true;
      wait;
   end process P_CTL;

   U_DUT : entity work.CobsDecoder
      port map (
         clk       => clk,
         rst       => '0',
         datInp    => iDat,
         vldInp    => iVld,
         rdyInp    => iRdy,
         datOut    => oDat,
         vldOut    => oVld,
         rdyOut    => oRdy,
         lstOut    => oLst
      );

end architecture sim;
