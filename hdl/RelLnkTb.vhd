library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_textio.all;
use     std.textio.all;

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
   signal vlda2bO            : std_logic;
   signal vlda2bI            : std_logic;
   signal rdya2bO            : std_logic;
   signal rdya2bI            : std_logic;
   signal lsta2b             : std_logic;

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

   function to_str(constant slv : std_logic_vector) return string is
      variable l : line;
   begin
      hwrite(l, slv);
      return l.all;
   end function to_str;

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
            assert ( lstout & datOut = FEED_C(got) ) severity failure;
            got <= got + 1;
            if ( got = FEED_C'high ) then
               idx   <= 0;
               got   <= 0;
               phase <= phase + 1;
            end if;
         end if;
         if ( got = 0 and phase = END_PHASE_C ) then
            report "TEST PASSED";
            don <= true;
         end if;
      end if;
   end process P_FEED;

   U_PING : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => 4,
         REX_TIMEOUT_G   => to_unsigned(50, RelLnkTimeoutType'length),
         FAST_ACK_G      => false
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
         vldOutTx => vlda2bI,
         lstOutTx => lsta2b,
         rdyOutTx => rdya2bO,
         datInpRx => datb2aO,
         vldInpRx => vldb2aO,
         lstInpRx => lstb2aO,
         rdyInpRx => rdyb2aI
      );

   -- intermediate storage for fed-back packet; otherwise
   -- the connection may stall; e.g. PONG retransmitting -> PONG stalls InpTx
   --  -> stalls PONG's OutRx which prevents it from seeing ACKs to the
   -- retransmissions -> PONG keeps retransmitting.
   B_FIFO : block is
      constant LD_FBK_FIFO_DEPTH_C   : natural := 6;
      signal full, empty             : std_logic;
      signal wena, rena              : std_logic;
      signal wptr, rptr              : signed(LD_FBK_FIFO_DEPTH_C downto 0);
      signal dinp, dout              : std_logic_vector(8 downto 0);
   begin
      U_FIFO : entity work.RelLnkFifo
         generic map (
            LD_FIFO_DEPTH_G => LD_FBK_FIFO_DEPTH_C,
            DATA_WIDTH_G    => dinp'length
         )
         port map (
            clk      => clk,
            rst      => rst,
            datInp   => dinp,
            wrEna    => wena,
            full     => full,
            wrPtr    => wptr,
            cmPtr    => wptr,
            rdPtr    => rptr,
            hlPtr    => rptr,
            rdEna    => rena,
            empty    => empty,
            datOut   => dout
         );
         dinp    <= lstFbkI & datFbkI;
         rdyFbkI <= not full;
         wena    <= (rdyFbkI and vldFbkI);
         vldFbkO <= not empty;
         rena    <= vldFbkO and rdyFbkO;
         lstFbkO <= dout(8);
         datFbkO <= dout(7 downto 0);
   end block B_FIFO;

   U_PONG : entity work.RelLnk
      generic map (
         LD_FIFO_DEPTH_G => 4,
         REX_TIMEOUT_G   => to_unsigned(50, RelLnkTimeoutType'length),
         FAST_ACK_G      => false
      )
      port map (
         clk      => clk,
         rst      => rst,

         datInpTx => datFbkO,
         vldInpTx => vldFbkO,
         lstInpTx => lstFbkO,
         rdyInpTx => rdyFbkO,
         datOutRx => datFbkI,
         vldOutRx => vldFbkI,
         lstOutRx => lstFbkI,
         rdyOutRx => rdyFbkI,

         datOutTx => datb2aI,
         vldOutTx => vldb2aI,
         lstOutTx => lstb2aI,
         rdyOutTx => rdyb2aO,
         datInpRx => data2b,
         vldInpRx => vlda2bO,
         lstInpRx => lsta2b,
         rdyInpRx => rdya2bI
      );

   B_TEST : block is
      type RegType is record
         a2bCnt            : natural;
         b2aCnt            : natural;
         lphase            : integer;
      end record RegType;

      constant REG_INIT_C : RegType := (
         a2bCnt            => 0,
         b2aCnt            => 0,
         lphase            => -1
      );

      signal   r           : RegType := REG_INIT_C;
      signal   rin         : RegType;

      signal   delayLine   : Slv10Array(0 to 40) := (others => (others => '0'));
      signal   delayRdy    : std_logic := '0';
      signal   delayRst    : std_logic := '0';

   begin

      P_COMB : process (
         r,
         data2b,  lsta2b,  rdya2bI, rdya2bO, vlda2bI,
         datb2aI, lstb2aI, rdyb2aI, rdyb2aO, vldb2aI, datb2aO, lstb2aO, vldb2aO,
         phase,
         delayLine
      ) is
         variable v : RegType;
      begin
         v          := r;
         v.lphase   := phase;

         if ( (vlda2bI and rdya2bO and lsta2b) = '1' ) then
            v.a2bCnt := r.a2bCnt + 1;
         end if;

         if ( (vldb2aI and rdyb2aO and lstb2aI) = '1' ) then
            v.b2aCnt := r.b2aCnt + 1;
         end if;

         if ( phase /= r.lphase ) then
            v.a2bCnt := 0;
            v.b2aCnt := 0;
         end if;

         delayRst   <= '1';
         delayRdy   <= '0';

         datb2aO    <= datb2aI;
         lstb2aO    <= lstb2aI;
         vldb2aO    <= vldb2aI;

         vlda2bO    <= vlda2bI;

         rdya2bO    <= rdya2bI;
         rdyb2aO    <= rdyb2aI;

         delayRdy   <= '0';

         if ( phase = 1 and r.a2bCnt = 1 ) then
            -- drop a REQ
            vlda2bO <= '0';
            rdya2bO <= '1';
         end if;

         if ( phase = 2 and r.b2aCnt = 2 ) then
            -- drop an ACK
            vldb2aO <= '0';
            rdyb2aO <= '1';
         end if;

         if ( phase = 3 ) then
            delayRst <= '0';
            lstb2aO  <= delayLine(0)(9);
            vldb2aO  <= delayLine(0)(8);
            datb2aO  <= delayLine(0)(7 downto 0);
            delayRdy <= rdyb2aI;
            rdyb2aO  <= rdyb2aI or not delayLine(0)(8);
         end if;

         rin        <= v;
      end process P_COMB;

      P_SEQ  : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               r         <= REG_INIT_C;
            else
               r <= rin;
            end if;
            if ( (rst or delayRst) = '1' ) then
               delayLine <= (others => (others => '0'));
            else
               if ( (delayRdy = '1') or (delayLine(0)(8) = '0') ) then
                  delayLine(delayLine'high) <= lstb2aI & vldb2aI & datb2aI;
                  for i in delayLine'low to delayLine'high - 1 loop
                     delayLine(i) <= delayLine(i+1);
                  end loop;
               end if;
            end if;
         end if;
      end process P_SEQ;

   end block B_TEST;
end architecture rtl;


