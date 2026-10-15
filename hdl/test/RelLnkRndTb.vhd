library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.RndPkg.all;
use     work.RelLnkPkg.all;

entity RelLnkRndTb is
end entity RelLnkRndTb;

architecture rtl of RelLnkRndTb is

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

   constant N_PKTS_C         : positive  := 2000;

   constant LD_DROP_C        : positive  := 4;
   constant DROP_ENA_C       : std_logic := '1';

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

   type Slv9Array  is array (natural range <>) of std_logic_vector(8 downto 0);
   type Slv10Array is array (natural range <>) of std_logic_vector(9 downto 0);

   signal idx                : natural   := 0;
   signal got                : natural   := 0;
   signal don                : boolean   := false;
   signal phase              : natural   := 0;

   constant END_PHASE_C : integer := 4;

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
      variable s1      : positive := PKT_SEED_1_C;
      variable s2      : positive := PKT_SEED_2_C;
      variable s1Chk   : positive := PKT_SEED_1_C;
      variable s2Chk   : positive := PKT_SEED_2_C;
      variable u       : unsigned(LD_PLD_SIZE_C - 1 downto 0);
      variable lst     : signed(LD_PLD_SIZE_C downto 0) := (others => '0');
      variable lstChk  : signed(LD_PLD_SIZE_C downto 0) := (others => '0');
      variable d       : std_logic_vector(7 downto 0)   := (others => '0');
      variable dChk    : std_logic_vector(7 downto 0)   := (others => '0');
      variable pkts    : integer  := N_PKTS_C;
   begin
      if ( rising_edge( clk ) ) then

         if ( ((vldInpI = '0') and (pkts > 0))) then
            -- init
            vldInpI <= '1';
         end if;

         if ( (vldInpI and rdyInpO) = '1' ) then
            if ( lst < 0 ) then
               rnd(s1,s2,u);
               lst     := signed(resize(u, lst'length));
               if ( pkts = 0 ) then
                  vldInpI <= '0';
               else
                  pkts := pkts - 1;
               end if;
            else
               lst     := lst - 1;
            end if;
            rnd(s1,s2,d);
         end if;
            
         if ( (vldOutO and rdyOutI) = '1' ) then
            assert ( lstOutO = lstChk(lstChk'left) ) severity failure;
            assert ( datOutO = dChk                ) severity failure;
            if ( lstOutO = '1' ) then
               got <= got + 1;
               rnd(s1Chk, s2Chk, u);
               lstChk  := signed(resize(u, lstChk'length));
            else
               lstChk  := lstChk - 1;
            end if;
            rnd(s1Chk, s2Chk, dChk);
         end if;
         if ( got = N_PKTS_C ) then
            report "TEST PASSED";
            don <= true;
         end if;

         lstInpI <= lst(lst'left);
         datInpI <= d;

      end if;
   end process P_FEED;

   U_PING : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => LD_FIFO_DEPTH_C,
         REX_TIMEOUT_G   => to_unsigned(TIMEOUT_C, RelLnkTimeoutType'length),
         FAST_ACK_G      => false,
         REL_LNK_WINSZ_G => WINSZ_C
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

         ena             => DROP_ENA_C,
         ack             => open,

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

         ena             => DROP_ENA_C,
         ack             => open,

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

         datInpTx => x"00",
         vldInpTx => '0',
         lstInpTx => '0',
         rdyInpTx => open,
         datOutRx => datOutI,
         vldOutRx => vldOutI,
         lstOutRx => lstOutI,
         rdyOutRx => rdyOutO,

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


