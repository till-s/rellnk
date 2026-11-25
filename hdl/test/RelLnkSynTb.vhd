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
use     work.RelLnkPkg.all;

entity RelLnkSynTb is
end entity RelLnkSynTb;

architecture rtl of RelLnkSynTb is

   type Slv8Array  is array (natural range <>) of std_logic_vector(7 downto 0);
   type Slv9Array  is array (natural range <>) of std_logic_vector(8 downto 0);
   type Slv10Array is array (natural range <>) of std_logic_vector(9 downto 0);

   constant LD_PLD_SIZE_C    : natural   := 3;
   constant LD_FIFO_DEPTH_C  : natural   := LD_PLD_SIZE_C + 3; -- (pld + hdr)*winsz

   function ite(constant c : boolean; constant t,f : integer) return integer is
   begin
      if ( c ) then return t; else return f; end if;
   end function ite;

   constant FIXED_STALL_C    : integer   := -10; --10;
   constant FIXED_STALL_B2A_C: integer   := 8*FIXED_STALL_C;
   constant TIMEOUT_C        : natural   := 2**LD_PLD_SIZE_C * 5 * ite(FIXED_STALL_C > 0, FIXED_STALL_C, 1);
   constant WINSZ_C          : positive  := 3;
   constant LD_PAUSE_C       : natural   := 16;

   constant PKT_SEED_1_C     : positive  := 237;
   constant PKT_SEED_2_C     : positive  := 7239;

   constant N_LOOPS_C        : positive  := 10000;

   constant LD_DROP_C        : positive  := 4;
   constant DROP_ENA_C       : std_logic := '1';

   constant PKT_1_C          : Slv8Array := (x"de", x"ad", x"be", x"ef");

   signal clk                : std_logic := '0';
   signal rst                : std_logic := '0';

   signal datInpO            : std_logic_vector(7 downto 0);
   signal vldInpO            : std_logic := '0';
   signal rdyInpO            : std_logic;
   signal lstInpO            : std_logic;
   signal datInpI            : std_logic_vector(7 downto 0);
   signal vldInpI            : std_logic := '0';
   signal rdyInpI            : std_logic;
   signal lstInpI            : std_logic;

   signal datOutO            : std_logic_vector(7 downto 0);
   signal vldOutO            : std_logic;
   signal rdyOutO            : std_logic := '1';
   signal lstOutO            : std_logic;
   signal datOutI            : std_logic_vector(7 downto 0);
   signal vldOutI            : std_logic;
   signal rdyOutI            : std_logic := '1';
   signal lstOutI            : std_logic;

   signal datRevO            : std_logic_vector(7 downto 0) := (others => '0');
   signal vldRevO            : std_logic := '0';
   signal rdyRevI            : std_logic := '1';
   signal lstRevO            : std_logic := '0';


   signal data2d             : std_logic_vector(7 downto 0);
   signal vlda2d             : std_logic;
   signal rdya2d             : std_logic;
   signal lsta2d             : std_logic;

   signal datd2pab           : std_logic_vector(7 downto 0);
   signal vldd2pab           : std_logic;
   signal rdyd2pab           : std_logic;
   signal lstd2pab           : std_logic;

   signal datp2b             : std_logic_vector(7 downto 0);
   signal vldp2b             : std_logic;
   signal rdyp2b             : std_logic;
   signal lstp2b             : std_logic;

   signal datb2d             : std_logic_vector(7 downto 0);
   signal vldb2d             : std_logic;
   signal rdyb2d             : std_logic;
   signal lstb2d             : std_logic;

   signal datd2pba           : std_logic_vector(7 downto 0);
   signal vldd2pba           : std_logic;
   signal rdyd2pba           : std_logic;
   signal lstd2pba           : std_logic;

   signal datp2a             : std_logic_vector(7 downto 0);
   signal vldp2a             : std_logic;
   signal rdyp2a             : std_logic;
   signal lstp2a             : std_logic;

   signal dropTrga2b         : std_logic := DROP_ENA_C;
   signal dropAcka2b         : std_logic;
   signal dropTrgb2a         : std_logic := DROP_ENA_C;
   signal dropAckb2a         : std_logic;

   signal syncTrga2b         : std_logic := '0';
   signal syncAcka2b         : std_logic;
   signal syncTrgb2a         : std_logic := '0';
   signal syncAckb2a         : std_logic;

   signal idx                : natural   := 0;
   signal got                : natural   := 0;
   signal don                : boolean   := false;
   signal phase              : natural   := 0;

   signal syncIssued         : natural   := 0;
   signal syncProcessed      : natural   := 0;

   constant END_PHASE_C : integer := 4;

   procedure tic is
   begin
      wait until rising_edge(clk);
   end procedure tic;

   procedure waitForEdge(signal x: in std_logic; constant lvl : in std_logic) is
   begin
      while ( x = lvl ) loop
         tic;
      end loop;
      while ( x /= lvl ) loop
         tic;
      end loop;
   end procedure waitForEdge;

   procedure waitForRising(signal x : in std_logic) is
   begin
      waitForEdge(x, '1');
   end procedure waitForRising;

   procedure waitForFalling(signal x : in std_logic) is
   begin
      waitForEdge(x, '0');
   end procedure waitForFalling;

   procedure feed(signal d : out std_logic_vector; signal v,l : out std_logic; signal r : in std_logic; constant a: Slv8Array) is
      variable i : natural;
   begin
    i := a'low;
    v <= '1';
    l <= '0'; 
    d <= a(i);
    while ( i < a'high ) loop
      tic;
      if ( r = '1' ) then
        i := i + 1;
        d <= a(i);
      end if;
    end loop;
    l <= '1';
    while ( i <= a'high ) loop
      tic;
      if ( r = '1' ) then
        v <= '0';
        l <= '0';
        i := i + 1;
      end if;
    end loop;
  end procedure feed;

  procedure feed(signal d : out std_logic_vector; signal v,l : out std_logic; signal r : in std_logic; constant n: positive) is
    constant D_C : Slv8Array(1 to n) := (others => (others => '0'));
  begin
    feed(d, v, l, r, D_C);
  end procedure feed;

  procedure check(signal d : in std_logic_vector; signal v,l : in std_logic; signal r : out std_logic; constant a: Slv8Array) is
    variable i : natural;
  begin
    i := a'low;
    r <= '1';
    while ( i <= a'high ) loop
      tic;
      if ( v = '1' ) then
         assert d = a(i);
         assert ( (l = '1') = (i = a'high) );
         i := i + 1;
      end if;
    end loop;
    r <= '0';
  end procedure check;

  procedure check(signal d : in std_logic_vector; signal v,l : in std_logic; signal r : out std_logic; constant n: positive) is
    constant D_C : Slv8Array(1 to n) := (others => (others => '0'));
  begin
    check(d, v, l, r, D_C);
  end procedure check;


begin

   P_CLK : process is
   begin
      wait for 1 us;
      clk <= not clk;
      if ( don ) then
         wait;
      end if;
   end process P_CLK;

   P_FEED : process is
   begin
      datInpI <= (others => '0');
      for l in 1 to N_LOOPS_C loop
         feed(datInpI, vldInpI, lstInpI, rdyInpO, 5);
         feed(datInpI, vldInpI, lstInpI, rdyInpO, 3);
         while ( syncProcessed /= syncIssued ) loop
            -- wait for the receiver to check the 'good' packet we sent after SYN
            tic;
         end loop;
         syncTrga2b <= '1';
         syncIssued <= syncIssued + 1;
         tic;
         syncTrga2b <= '0';
         tic;
         while ( syncAcka2b = '1' ) loop
           tic;
         end loop;
         -- feed a new packet that the receiver will verify
         feed(datInpI, vldInpI, lstInpI, rdyInpO, PKT_1_C);
      end loop;
      wait;
   end process P_FEED;

   P_CHECK : process is
      variable lst : integer := 0;
   begin
      tic;
      for l in 1 to N_LOOPS_C loop
         -- ignore data
         rdyOutI <= '1';
         -- wait for sync on the receiver side
         waitForFalling(syncAckb2a);
         -- verify the packet that was sent after sync
         check(datOutO, vldOutO, lstOutO, rdyOutI, PKT_1_C);
         syncProcessed <= syncProcessed + 1;
         if ( syncProcessed - lst = 500 ) then
            report integer'image(syncProcessed) & "/" & integer'image(N_LOOPS_C) & " SYN requests processed";
            lst := syncProcessed;
         end if;
      end loop;
      report "Test PASSED";
      don <= true;
      wait;
   end process P_CHECK;

   -- feed stuff in the reverse direction
   P_REV : process ( clk ) is
      variable i : natural := 0;
   begin
      if ( rising_edge( clk ) ) then
         vldRevO <= '1';
         lstRevO <= '0';
         if ( (vldRevO and rdyRevI) = '1' ) then
            if ( i = 5 ) then
               i := 0;
            else
               i := i + 1;
            end if;
         end if;
         datRevO <= std_logic_vector(to_unsigned(i, 8));
         if ( i = 5 ) then
            lstRevO <= '1';
         end if;
      end if;
   end process P_REV;

   U_PING : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => LD_FIFO_DEPTH_C,
         REX_TIMEOUT_G   => to_unsigned(TIMEOUT_C, RelLnkTimeoutType'length),
         FAST_ACK_G      => false,
         REL_LNK_WINSZ_G => WINSZ_C,
         SYN_MASTER_G    => true
      )
      port map (
         clk      => clk,
         rst      => rst,

         datInpTx => datInpO,
         vldInpTx => vldInpO,
         lstInpTx => lstInpO,
         rdyInpTx => rdyInpI,
         datOutRx => open,
         vldOutRx => open,
         lstOutRx => open,
         rdyOutRx => '1',
         synReq   => syncTrga2b,
         synAck   => syncAcka2b,

         datOutTx => data2d,
         vldOutTx => vlda2d,
         lstOutTx => lsta2d,
         rdyOutTx => rdya2d,
         datInpRx => datp2a,
         vldInpRx => vldp2a,
         lstInpRx => lstp2a,
         rdyInpRx => rdyp2a
      );

   U_DROP_A2B : entity work.PktDropRnd
      generic map (
         LD_RND_G        => LD_DROP_C,
         SEED_1_G        => 19863,
         SEED_2_G        => 886541
      )
      port map (
         clk             => clk,
         rst             => rst,

         ena             => dropTrga2b,
         ack             => dropAcka2b,

         datInp          => data2d,
         vldInp          => vlda2d,
         lstInp          => lsta2d,
         rdyInp          => rdya2d,

         datOut          => datd2pab,
         vldOut          => vldd2pab,
         lstOut          => lstd2pab,
         rdyOut          => rdyd2pab
      );

   U_PAUSE_A2B : entity work.StrmPauseRnd
      generic map (
         LD_PAUSE_G      => LD_PAUSE_C,
         SEED_1_G        => 87,
         SEED_2_G        => 777777,
         FIXED_STALL_G   => FIXED_STALL_C
      )
      port map (
         clk             => clk,
         rst             => rst,

         datInp          => datd2pab,
         vldInp          => vldd2pab,
         lstInp          => lstd2pab,
         rdyInp          => rdyd2pab,

         datOut          => datp2b,
         vldOut          => vldp2b,
         lstOut          => lstp2b,
         rdyOut          => rdyp2b
      );

   U_PAUSE_B2A : entity work.StrmPauseRnd
      generic map (
         LD_PAUSE_G      => LD_PAUSE_C,
         SEED_1_G        => 99,
         SEED_2_G        => 888777,
         FIXED_STALL_G   => FIXED_STALL_B2A_C
      )
      port map (
         clk             => clk,
         rst             => rst,

         datInp          => datd2pba,
         vldInp          => vldd2pba,
         lstInp          => lstd2pba,
         rdyInp          => rdyd2pba,

         datOut          => datp2a,
         vldOut          => vldp2a,
         lstOut          => lstp2a,
         rdyOut          => rdyp2a
      );

   U_DROP_B2A : entity work.PktDropRnd
      generic map (
         LD_RND_G        => LD_DROP_C,
         SEED_1_G        => 31798,
         SEED_2_G        => 999231
      )
      port map (
         clk             => clk,
         rst             => rst,

         ena             => dropTrgb2a,
         ack             => dropAckb2a,

         datInp          => datb2d,
         vldInp          => vldb2d,
         lstInp          => lstb2d,
         rdyInp          => rdyb2d,

         datOut          => datd2pba,
         vldOut          => vldd2pba,
         lstOut          => lstd2pba,
         rdyOut          => rdyd2pba
      );

   U_PONG : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => LD_FIFO_DEPTH_C,
         REX_TIMEOUT_G   => to_unsigned(TIMEOUT_C, RelLnkTimeoutType'length),
         FAST_ACK_G      => false,
         REL_LNK_WINSZ_G => WINSZ_C
      )
      port map (
         clk      => clk,
         rst      => rst,

         datInpTx => datRevO,
         vldInpTx => vldRevO,
         lstInpTx => lstRevO,
         rdyInpTx => rdyRevI,
         datOutRx => datOutI,
         vldOutRx => vldOutI,
         lstOutRx => lstOutI,
         rdyOutRx => rdyOutO,
         synReq   => syncTrgb2a,
         synAck   => syncAckb2a,

         datOutTx => datb2d,
         vldOutTx => vldb2d,
         lstOutTx => lstb2d,
         rdyOutTx => rdyb2d,
         datInpRx => datp2b,
         vldInpRx => vldp2b,
         lstInpRx => lstp2b,
         rdyInpRx => rdyp2b
      );

   U_PAUSE_INP : entity work.StrmPauseRnd
      generic map (
         LD_PAUSE_G      => LD_PAUSE_C,
         SEED_1_G        => 7869,
         SEED_2_G        => 555555,
         FIXED_STALL_G   => ite(FIXED_STALL_C >= 0, 0, -1)
      )
      port map (
         clk             => clk,
         rst             => rst,

         datInp          => datInpI,
         vldInp          => vldInpI,
         lstInp          => lstInpI,
         rdyInp          => rdyInpO,

         datOut          => datInpO,
         vldOut          => vldInpO,
         lstOut          => lstInpO,
         rdyOut          => rdyInpI
      );

   U_PAUSE_OUT : entity work.StrmPauseRnd
      generic map (
         LD_PAUSE_G      => LD_PAUSE_C,
         SEED_1_G        => 4109,
         SEED_2_G        => 111986,
         FIXED_STALL_G   => ite(FIXED_STALL_C >= 0, 0, -1)
      )
      port map (
         clk             => clk,
         rst             => rst,

         datInp          => datOutI,
         vldInp          => vldOutI,
         lstInp          => lstOutI,
         rdyInp          => rdyOutO,

         datOut          => datOutO,
         vldOut          => vldOutO,
         lstOut          => lstOutO,
         rdyOut          => rdyOutI
      );

end architecture rtl;
