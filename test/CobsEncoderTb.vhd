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

entity CobsEncoderTb is
end entity CobsEncoderTb;

architecture sim of CobsEncoderTb is

   constant LOG_DBG_C               : boolean  := false;
   -- test max. throughput (watch waveform); normally we exercise flow control
   -- using random delays.
   constant THROUGHPUT_C            : boolean  := false;
   constant LD_ENC_DAT_FIFO_DEPTH_C : positive := 8;
   constant LD_ENC_HDR_FIFO_DEPTH_C : positive := 2;
   constant RAND_NUM_FRAMES_C       : natural := 1000;

   subtype Slv8Type  is std_logic_vector(7 downto 0);
   subtype Slv9Type  is std_logic_vector(8 downto 0);
   type    Slv8Array is array(natural range <>) of Slv8Type;
   type    Slv9Array is array(natural range <>) of Slv9Type;
   type    IntArray  is array(natural range <>) of integer;

   constant FEED_C : Slv9Array := (
      "1" & x"00",
      "1" & x"00",
      "0" & x"00",
      "0" & x"02",
      "0" & x"03",
      "0" & x"00",
      "1" & x"a0",
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
      "1" & x"fe",
      "0" & x"00",
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
      "1" & x"ff",
      "1" & x"00" -- sentinel
   );

   signal clk               : std_logic := '0';

   constant PHAS_BASIC_C    : integer := 2;
   constant PHAS_RANDM_C    : integer := 1;
   constant PHAS_WIPE_C     : integer := 0;

   signal phas              : integer   := PHAS_BASIC_C;
   signal randNumFrames     : natural   := 0;
   signal randMinLen        : natural   := 1000000;
   signal randMaxLen        : natural   := 0;
   signal notRdyCycles      : natural   := 0;
   signal totCycles         : natural   := 0;
   signal notVldCycles      : natural   := 0;

   signal iVld              : std_logic;
   signal iVldRnd           : signed(3  downto 0) := (others => '0');
   signal oRdyRnd           : signed(3  downto 0) := (others => '0');
   signal iLstRnd           : signed(11 downto 0) := (others => '0');
   signal iRdy              : std_logic;
   signal iDat              : std_logic_vector(7 downto 0);
   signal eVld              : std_logic;
   signal eRdy              : std_logic;
   signal eDat              : std_logic_vector(7 downto 0);
   signal oVld              : std_logic;
   signal oRdy              : std_logic := '1';
   signal oLst              : std_logic;
   signal iLst              : std_logic;
   signal oDat              : std_logic_vector(7 downto 0);

   signal iIdx              : integer := 0;
   signal cIdx              : integer := 0;

   signal fifoWrEna         : std_logic;
   signal fifoRdEna         : std_logic;
   signal fifoEmpty         : std_logic;
   signal fifoFull          : std_logic;
   signal fifoDatInp        : std_logic_vector(8 downto 0);
   signal iDatRnd           : std_logic_vector(7 downto 0) := (others => '0');
   signal fifoDatOut        : std_logic_vector(8 downto 0);

   procedure tic is
   begin
      wait until rising_edge(clk);
   end procedure tic;

begin

   P_CLK : process is
   begin
      wait for 10 us;
      clk <= not clk;
      if phas < 0 then
         wait;
      end if;
   end process P_CLK;

   P_MUX : process ( iIdx, phas, fifoFull, fifoEmpty, oRdy, oVld, iRdy, iVld, iVldRnd, iLstRnd, fifoDatInp, fifoRdEna, iDatRnd, oRdyRnd ) is
   begin
      iDat        <= FEED_C(iIdx)(iDat'range);
      iLst        <= FEED_C(iIdx)(8);
      iVld        <= '0';
      fifoWrEna   <= '0';
      fifoRdEna   <= '0';
      fifoDatInp  <= iLstRnd(iLstRnd'left) & iDatRnd;
      oRdy        <= '1';
      case ( phas ) is
         when PHAS_BASIC_C =>
            if ( iIdx < FEED_C'high ) then
               iVld <= '1';
            end if;
         when PHAS_RANDM_C =>
            iVld      <= not fifoFull and iVldRnd(iVldRnd'left);
            iDat      <= fifoDatInp(iDat'range);
            iLst      <= fifoDatInp(fifoDatInp'left);
            fifoWrEna <= iVld and iRdy;

            fifoRdEna <= (not fifoEmpty and oVld and oRdyRnd(oRdyRnd'left));
            oRdy      <= fifoRdEna;

         when others=>
      end case;
   end process P_MUX;


   P_FEED : process ( clk ) is
      variable w  : integer := 0;
      variable s1 : positive := 67;
      variable s2 : positive := 11;
      variable r  : real;
      variable ri : unsigned(iVldRnd'length + 8 - 1 downto 0);
      variable vr : signed(iVldRnd'range);
      variable vl : signed(iLstRnd'range);
      variable fl : natural := 0;
   begin
      if ( rising_edge( clk ) ) then
         if ( (iVld and iRdy) = '1' ) then
            if ( iIdx < FEED_C'high ) then
               iIdx <= iIdx + 1;
            end if;
         end if;
         if ( PHAS_RANDM_C = phas ) then
            if ( (iVld and iRdy) = '1' ) then
               uniform(s1, s2, r);
               ri          := to_unsigned(integer(floor(2.0**(ri'length)*r)), ri'length);
               vr          := signed(ri(ri'left downto ri'length - iVldRnd'length));
               vr(vr'left) := '0';
               if ( THROUGHPUT_C ) then
                  iVldRnd     <= (others => '1');
               else
                  iVldRnd     <= vr - 1;
               end if;
               iDatRnd     <= std_logic_vector(ri(iDatRnd'range));
               fl          := fl + 1;
               if ( iLst = '1' ) then
                  uniform(s1, s2, r);
                  vl          := to_signed(natural(floor(2.0**(vl'length - 1)*r)), vl'length);
                  vl(vl'left) := '0';
                  iLstRnd <= vl - 1;
                  if ( fl > randMaxLen ) then
                     randMaxLen <= fl;
                  end if;
                  if ( fl < randMinLen ) then
                     randMinLen <= fl;
                  end if;
                  randNumFrames <= randNumFrames + 1;
                  fl := 0;
                  if ( randNumFrames = RAND_NUM_FRAMES_C ) then
                     iVldRnd <= (others => '0');
                  end if;
               else
                  iLstRnd <= iLstRnd - 1;
               end if;
            elsif (iVld = '0' and randNumFrames < RAND_NUM_FRAMES_C) then
               iVldRnd <= iVldRnd - 1;
            end if;
         end if;
         uniform(s1, s2, r);
      end if;
   end process P_FEED;

   P_LOG : process ( clk ) is
      function toStr4(constant x : in std_logic_vector(3 downto 0)) return string is
      begin
         case ( to_integer(unsigned(x)) ) is
           when  0 => return "0";
           when  1 => return "1";
           when  2 => return "2";
           when  3 => return "3";
           when  4 => return "4";
           when  5 => return "5";
           when  6 => return "6";
           when  7 => return "7";
           when  8 => return "8";
           when  9 => return "9";
           when 10 => return "A";
           when 11 => return "B";
           when 12 => return "C";
           when 13 => return "D";
           when 14 => return "E";
           when 15 => return "F";
           when others => return "U";
         end case;
      end function toStr4;

      function toStr8(constant x : in std_logic_vector(7 downto 0)) return string is
      begin
         return toStr4(x(7 downto 4)) & toStr4(x(3 downto 0));
      end function toStr8;

      function ite(constant c : boolean; constant t,f : string) return string is
      begin
         if ( c ) then return t; else return f; end if;
      end function ite;

   begin
      if ( LOG_DBG_C and rising_edge(clk) ) then
        if ( (iVld and iRdy) = '1' ) then
           report toStr8(iDat) & ite(iLst = '1', "L" , " ");
        end if;
        if ( (eVld and eRdy) = '1' ) then
           report "     " & toStr8(eDat);
        end if;
      end if;
   end process P_LOG;

   P_CHECK : process ( clk ) is
      variable framesOut : natural := 0;
      variable s1 : positive := 5;
      variable s2 : positive := 97;
      variable r  : real;
      variable vr : signed(oRdyRnd'range);
   begin
      if ( rising_edge(clk) ) then
         totCycles <= totCycles + 1;
         if ( (iVld and iRdy) = '0' ) then
            notRdyCycles <= notRdyCycles + 1;
         end if;
         if ( (oVld and oRdy) = '0' ) then
            notVldCycles <= notVldCycles + 1;
         end if;
         if ( phas = PHAS_BASIC_C ) then
            if ( ( oVld and oRdy ) = '1' ) then
               assert oLst & oDat = FEED_C(cIdx) report "data mismatch" severity failure;
               if ( cIdx < FEED_C'high ) then
                  cIdx <= cIdx + 1;
               end if;
            end if;
            if ( cIdx = FEED_C'high ) then
               phas <= phas - 1;
            end if;
         elsif ( phas = PHAS_RANDM_C ) then
            if ( (oVld and oRdy) = '1' ) then
               assert fifoEmpty = '0' report "internal error - fifo is empty" severity failure;
               assert fifoDatOut = oLst & oDat report "random data/last mismatch" severity failure;
               if ( fifoDatOut(fifoDatOut'left) = '1' ) then
                  framesOut := framesOut + 1;
                  if ( framesOut = RAND_NUM_FRAMES_C ) then
                     phas <= phas - 1;
                  end if;
               end if;
               uniform(s1, s2, r);
               vr          := signed(to_unsigned(integer(floor(2.0**vr'length*r)), vr'length));
               vr(vr'left) := '0';
               if ( THROUGHPUT_C ) then
                  oRdyRnd <= (others => '1');
               else
                  oRdyRnd     <= vr - 1;
               end if;
            elsif (oRdyRnd >= 0) then
               oRdyRnd <= oRdyRnd - 1;
            end if;
         elsif ( phas = PHAS_WIPE_C ) then
            report "TEST PASSED";
            report integer'image(framesOut) & " random frames processed";
            if ( framesOut > 0 ) then
               report "Min frame length: " & integer'image(randMinLen);
               report "Max frame length: " & integer'image(randMaxLen);
            end if;
            if ( THROUGHPUT_C ) then
               report "Input  stalled for " & integer'image(notRdyCycles) & "/" & integer'image(totCycles) & " cycles ("
                     & real'image(100.0*real(notRdyCycles)/real(totCycles)) & "%)";
               report "Output stalled for " & integer'image(notVldCycles) & "/" & integer'image(totCycles) & " cycles ("
                     & real'image(100.0*real(notVldCycles)/real(totCycles)) & "%)";
            end if;
            phas <= phas - 1;
         end if;
      end if;
   end process P_CHECK;

   U_DUT_E : entity work.CobsEncoder
      generic map (
         LD_DAT_FIFO_DEPTH_G => LD_ENC_DAT_FIFO_DEPTH_C,
         LD_HDR_FIFO_DEPTH_G => LD_ENC_HDR_FIFO_DEPTH_C
      )
      port map (
         clk       => clk,
         rst       => '0',
         datInp    => iDat,
         vldInp    => iVld,
         rdyInp    => iRdy,
         lstInp    => iLst,
         datOut    => eDat,
         vldOut    => eVld,
         rdyOut    => eRdy
      );

   U_DUT_D : entity work.CobsDecoder
      port map (
         clk       => clk,
         rst       => '0',
         datInp    => eDat,
         vldInp    => eVld,
         rdyInp    => eRdy,
         datOut    => oDat,
         vldOut    => oVld,
         rdyOut    => oRdy,
         lstOut    => oLst
      );

   U_RND_FIFO : entity work.CobsFifo
      generic map (
         LD_FIFO_DEPTH_G => 9,
         DATA_WIDTH_G    => fifoDatInp'length
      )
      port map (
         clk       => clk,
         rst       => '0',
         datInp    => fifoDatInp,
         wrEna     => fifoWrEna,
         full      => fifoFull,
         datOut    => fifoDatOut,
         rdEna     => fifoRdEna,
         empty     => fifoEmpty
      );

end architecture sim;
