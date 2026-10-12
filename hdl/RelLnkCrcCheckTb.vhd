library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.CrcPkg.all;
use     work.RelLnkPkg.all;

entity RelLnkCrcCheckTb is
end entity RelLnkCrcCheckTb;

architecture rtl of RelLnkCrcCheckTb is

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

   type Slv8Array is array (natural range <>) of std_logic_vector(7 downto 0);

   signal idx                : natural   := 0;
   signal don                : boolean   := false;

   -- must be COBS encoded
   constant FEED_C : Slv8Array := (
      x"00",
      x"00",
      x"03",
      x"fa", -- some data
      x"0b",
      x"00",
      x"03",
      x"38", -- produces 0x5800 checksum
      x"4a",
      x"00"
   );

   procedure tic is
   begin
      wait until rising_edge(clk);
   end procedure tic;

   function dojam(constant o : integer; constant jidx : integer) return std_logic is
   begin
     if (o = jidx) then return '1'; else return '0'; end if;
   end function dojam;

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
      while ( datInp /= x"00" ) loop
         o := o + 1;
         i <= s + o;
         j <= dojam(o,jidx);
         tic;
      end loop;
      v <= '0';
      tic;
      o := 0;
      L_1 : while ( true ) loop
         while (vldChk = '0') loop
            if ( dropping = '1' ) then
               assert jidx >= 0 severity failure;
               while ( dropping = '1' ) loop
                  tic;
               end loop;
               -- restore
               i <= s;
               j <= '0';
               tic;
               return;
            end if;
            tic;
         end loop;
         report integer'image(s) & " " & integer'image(o);
         assert (datChk = FEED_C(s + o)) severity failure; 
         if ( datChk = x"00" ) then
            i <= s + o + 1;
            j <= dojam(o + 1,jidx);
            tic;
            exit L_1;
         end if;
         o := o + 1;
         tic;
      end loop;
   end procedure snd;

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
      variable jtst : integer;
   begin
      while ( idx < FEED_C'length ) loop
         jtst := idx;
         snd(vldInp, idx, jam(0), 1);
         if ( idx = jtst ) then
            -- retry
            snd(vldInp, idx, jam(0), -1);
         end if;
      end loop;
      don <= true;
      report "TEST PASSED";
      wait;
   end process P_FEED;


   U_DUT_GEN : entity work.RelLnkCrcGen
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

   U_DUT_CHK : entity work.RelLnkCrcCheck
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
         rdyOut          => '1',
         dropping        => dropping
      );


end architecture rtl;
