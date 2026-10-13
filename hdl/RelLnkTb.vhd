library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.CrcPkg.all;
use     work.RelLnkPkg.all;

entity RelLnkTb is
end entity RelLnkTb;

architecture rtl of RelLnkTb is

   signal clk                : std_logic := '0';
   signal rst                : std_logic := '0';

   signal datInp             : std_logic_vector(7 downto 0);
   signal vldInp             : std_logic := '0';
   signal rdyInp             : std_logic;
   signal lstInp             : std_logic;

   signal datOut             : std_logic_vector(7 downto 0);
   signal vldOut             : std_logic;
   signal rdyOut             : std_logic := '1';
   signal lstOut             : std_logic;

   signal data2b             : std_logic_vector(7 downto 0);
   signal vlda2b             : std_logic;
   signal rdya2b             : std_logic;
   signal lsta2b             : std_logic;

   signal datb2a             : std_logic_vector(7 downto 0);
   signal vldb2a             : std_logic;
   signal rdyb2a             : std_logic;
   signal lstb2a             : std_logic;

   signal datFbk             : std_logic_vector(7 downto 0);
   signal vldFbk             : std_logic := '0';
   signal rdyFbk             : std_logic;
   signal lstFbk             : std_logic;

   type Slv9Array is array (natural range <>) of std_logic_vector(8 downto 0);

   signal idx                : natural   := 0;
   signal got                : natural   := 0;
   signal don                : boolean   := false;

   constant FEED_C : Slv9Array := (
      "0" & x"01",
      "1" & x"02",
      "0" & x"03",
      "1" & x"04",
      "0" & x"05",
      "1" & x"06",
      "0" & x"07",
      "1" & x"08"
   );

begin

   P_CLK : process is
   begin
      clk <= not clk;
      wait for 1 us;
      if ( don ) then
         wait;
      end if;
   end process P_CLK;

   datInp <= FEED_C(idx)(7 downto 0) when idx < FEED_C'length else x"00";
   lstInp <= FEED_C(idx)(8)          when idx < FEED_C'length else '0';
   vldInp <= '1'                     when idx < FEED_C'length else '0';

   P_FEED : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( (vldInp and rdyInp) = '1' ) then
            idx <= idx + 1;
         end if;
         if ( (vldOut and rdyOut) = '1' ) then
            got <= got + 1;
         end if;
         if ( got = FEED_C'length ) then
            don <= true;
         end if;
      end if;
   end process P_FEED;

   U_PING : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => 4,
         REX_TIMEOUT_G   => to_unsigned(1000, RelLnkTimeoutType'length)
      )
      port map (
         clk      => clk,
         rst      => rst,

         datInpTx => datInp,
         vldInpTx => vldInp,
         lstInpTx => lstInp,
         rdyInpTx => rdyInp,
         datOutRx => datOut,
         vldOutRx => vldOut,
         lstOutRx => lstOut,
         rdyOutRx => rdyOut,

         datOutTx => data2b,
         vldOutTx => vlda2b,
         lstOutTx => lsta2b,
         rdyOutTx => rdya2b,
         datInpRx => datb2a,
         vldInpRx => vldb2a,
         lstInpRx => lstb2a,
         rdyInpRx => rdyb2a
      );

   U_PONG : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => 4,
         REX_TIMEOUT_G   => to_unsigned(1000, RelLnkTimeoutType'length)
      )
      port map (
         clk      => clk,
         rst      => rst,

         datInpTx => datFbk,
         vldInpTx => vldFbk,
         lstInpTx => lstFbk,
         rdyInpTx => rdyFbk,
         datOutRx => datFbk,
         vldOutRx => vldFbk,
         lstOutRx => lstFbk,
         rdyOutRx => rdyFbk,

         datOutTx => datb2a,
         vldOutTx => vldb2a,
         lstOutTx => lstb2a,
         rdyOutTx => rdyb2a,
         datInpRx => data2b,
         vldInpRx => vlda2b,
         lstInpRx => lsta2b,
         rdyInpRx => rdya2b
      );
end architecture rtl;


