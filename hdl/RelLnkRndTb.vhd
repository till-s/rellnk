library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.CrcPkg.all;
use     work.RelLnkPkg.all;

entity RelLnkRndTb is
end entity RelLnkRndTb;

architecture rtl of RelLnkRndTb is

   constant LD_PLD_SIZE_C    : natural   := 3;
   constant LD_FIFO_DEPTH_C  : natural   := LD_PLD_SIZE_C + 3; -- (pld + hdr)*winsz

   constant PKT_SEED_1_C     : positive  := 237;
   constant PKT_SEED_2_C     : positive  := 7239;

   constant N_PKTS_C         : positive  := 1000;

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

   signal data2bO            : std_logic_vector(7 downto 0);
   signal data2bI            : std_logic_vector(7 downto 0);
   signal vlda2bO            : std_logic;
   signal vlda2bI            : std_logic;
   signal rdya2bO            : std_logic;
   signal rdya2bI            : std_logic;
   signal lsta2bO            : std_logic;
   signal lsta2bI            : std_logic;

   signal datb2aO            : std_logic_vector(7 downto 0);
   signal datb2aI            : std_logic_vector(7 downto 0);
   signal vldb2aO            : std_logic;
   signal vldb2aI            : std_logic;
   signal rdyb2aO            : std_logic;
   signal rdyb2aI            : std_logic;
   signal lstb2aO            : std_logic;
   signal lstb2aI            : std_logic;

   signal datFbkO            : std_logic_vector(7 downto 0);
   signal vldFbkO            : std_logic := '0';
   signal rdyFbkO            : std_logic;
   signal lstFbkO            : std_logic;
   signal datFbkI            : std_logic_vector(7 downto 0);
   signal vldFbkI            : std_logic := '0';
   signal rdyFbkI            : std_logic;
   signal lstFbkI            : std_logic;

   type Slv9Array  is array (natural range <>) of std_logic_vector(8 downto 0);
   type Slv10Array is array (natural range <>) of std_logic_vector(9 downto 0);

   signal idx                : natural   := 0;
   signal got                : natural   := 0;
   signal don                : boolean   := false;
   signal phase              : natural   := 0;

   constant END_PHASE_C : integer := 4;

   procedure rnd(variable s1, s2: inout positive; variable o : out unsigned) is
      variable v : real;
   begin
      uniform(s1, s2, v);
      o := to_unsigned(integer(floor((2.0**o'length)*v)), o'length);
   end procedure rnd;

   procedure rnd(variable s1, s2: inout positive; variable o : out std_logic_vector) is
      variable v : unsigned(o'range);
   begin
      rnd(s1, s2, v);
      o := std_logic_vector(v);
   end procedure rnd;


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
         REX_TIMEOUT_G   => to_unsigned(50, RelLnkTimeoutType'length),
         FAST_ACK_G      => false
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

         datOutTx => data2bI,
         vldOutTx => vlda2bI,
         lstOutTx => lsta2bI,
         rdyOutTx => rdya2bO,
         datInpRx => datb2aO,
         vldInpRx => vldb2aO,
         lstInpRx => lstb2aO,
         rdyInpRx => rdyb2aI
      );

   U_PONG : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => LD_FIFO_DEPTH_C,
         REX_TIMEOUT_G   => to_unsigned(50, RelLnkTimeoutType'length),
         FAST_ACK_G      => false
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

         datOutTx => datb2aI,
         vldOutTx => vldb2aI,
         lstOutTx => lstb2aI,
         rdyOutTx => rdyb2aO,
         datInpRx => data2bO,
         vldInpRx => vlda2bO,
         lstInpRx => lsta2bO,
         rdyInpRx => rdya2bI
      );

   B_PAUSE_A2B : block is
      constant LD_PAUSE_C : natural := 3;
      signal trg  : std_logic := '1';
      signal ack  : std_logic;
      signal pass : unsigned(LD_PAUSE_C - 1 downto 0) := (others => '0');
      signal paus : unsigned(LD_PAUSE_C - 1 downto 0) := (others => '0');
   begin

   P_RND : process ( clk ) is
      variable s1 : positive := 87;
      variable s2 : positive := 777777;
      variable  u : unsigned(pass'range);
   begin
      if ( rising_edge( clk ) ) then
         trg <= '0';
         if ( ack = '1' ) then
            rnd(s1,s2,u);
            pass <= u;
            rnd(s1,s2,u);
            paus <= u;
            trg  <= '1';
         end if;
      end if;
   end process P_RND;

   U_PAUSE_A2B : entity work.StrmPause
      generic map (
         LD_PAUSE_G      => pass'length,
         DATA_WIDTH_G    => 8
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

         datInp          => data2bI,
         vldInp          => vlda2bI,
         lstInp          => lsta2bI,
         rdyInp          => rdya2bO,

         datOut          => data2bO,
         vldOut          => vlda2bO,
         lstOut          => lsta2bO,
         rdyOut          => rdya2bI
      );

   end block B_PAUSE_A2B;

   B_PAUSE_B2A : block is
      constant LD_PAUSE_C : natural := 3;
      signal trg  : std_logic := '1';
      signal ack  : std_logic;
      signal pass : unsigned(LD_PAUSE_C - 1 downto 0) := (others => '0');
      signal paus : unsigned(LD_PAUSE_C - 1 downto 0) := (others => '0');
   begin

   P_RND : process ( clk ) is
      variable s1 : positive := 99;
      variable s2 : positive := 888777;
      variable  u : unsigned(pass'range);
   begin
      if ( rising_edge( clk ) ) then
         trg <= '0';
         if ( ack = '1' ) then
            rnd(s1,s2,u);
            pass <= u;
            rnd(s1,s2,u);
            paus <= u;
            trg  <= '1';
         end if;
      end if;
   end process P_RND;

   U_PAUSE_B2A : entity work.StrmPause
      generic map (
         LD_PAUSE_G      => pass'length,
         DATA_WIDTH_G    => 8
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

         datInp          => datb2aI,
         vldInp          => vldb2aI,
         lstInp          => lstb2aI,
         rdyInp          => rdyb2aO,

         datOut          => datb2aO,
         vldOut          => vldb2aO,
         lstOut          => lstb2aO,
         rdyOut          => rdyb2aI
      );

   end block B_PAUSE_B2A;


   datInpO <= datInpI;
   vldInpO <= vldInpI;
   lstInpO <= lstInpI;
   rdyInpO <= rdyInpI;

   datOutO <= datOutI;
   vldOutO <= vldOutI;
   lstOutO <= lstOutI;
   rdyOutO <= rdyOutI;

end architecture rtl;


