library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.CrcPkg.all;

entity RelLnkCrcGenTb is
end entity RelLnkCrcGenTb;

architecture rtl of RelLnkCrcGenTb is
   constant POLY_C           : std_logic_vector(14 downto 0) := "101100000110000";
   constant CRC_INIT_C       : std_logic_vector(14 downto 0) := (others => '1');

   -- if XORing the guard bit and it's CRC results in a zero byte then
   -- the encoder sets all CRC bits (and the guard bit).
   -- E.g., if the last byte shall be zeroed by XOring (POLY<<1) & GUARD
   -- then the left byte must match  (POLY<<1) while the right byte must
   -- be zero (otherwise the guard will not be raised). The bad byte
   -- sequence is thus [0x00, 0xb0] which is set to 0xff 0xff; this is
   -- equivalent with XORing [0xff, 0x4f] and thus with XORing the original CRC
   -- (which is 0) with the CRC of [0xff, 0x4f] (caveat: use initial state 0 for this,
   -- since the original message XOR [0xff, 0x4f]  should be equal to the new message;
   -- if the original message has the 0x7fff preamble we must omit from the correction.
   constant MAGIC_C          : std_logic_vector(14 downto 0) := CrcBitWiseLE(POLY_C, x"4fff")(14 downto 0);

   signal magic              : std_logic_vector(MAGIC_C'range) := MAGIC_C;

   signal clk                : std_logic := '0';
   signal rst                : std_logic := '0';

   signal datInp             : std_logic_vector(7 downto 0);
   signal vldInp             : std_logic := '0';
   signal rdyInp             : std_logic;

   signal datOut             : std_logic_vector(7 downto 0);
   signal vldOut             : std_logic;
   signal rdyOut             : std_logic := '1';

   signal crcOut             : std_logic_vector(POLY_C'range) := CRC_INIT_C;
   signal guard              : std_logic_vector(1 downto 0);

   type Slv8Array is array (natural range <>) of std_logic_vector(7 downto 0);

   signal idx                : natural   := 0;
   signal don                : boolean   := false;
   signal i                  : natural   := 1;
   signal j                  : natural   := 1;

   -- iterating over ((i<<8) | j) for i,j 1..255 (to avoid EOF bytes)
   -- scans *almost* all 2**15 CRC values (but a single one). This exercises
   -- the CRC generator...
   signal feed   : Slv8Array(0 to 2) := (
      x"00",
      x"00",
      x"00"
   );

   constant FEED_C : Slv8Array := (
      x"00",
      x"00",
      x"fa", -- some data
      x"0b",
      x"00",
      x"38", -- produces 0x5800 checksum
      x"4a",
      x"00"
   );

   signal seen : natural := 0;
   signal phase: natural := 0;
   signal len  : natural := 0;

   function NEOFS return natural is
      variable v : natural;
   begin
      v := 0;
      for ii in FEED_C'range loop
         if FEED_C(ii) = x"00" then
            v := v + 1;
         end if;
      end loop;
      return v;
   end function NEOFS;
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
   begin
      if ( rising_edge( clk ) ) then
         if ( (vldOut and rdyOut) = '1' ) then
            if ( phase = 1 ) then
               len    <= len + 1;
               guard  <= datOut(0) & guard(guard'left downto 1);
               crcOut <= std_logic_vector(shift_right(unsigned(crcOut),8)) xor CrcBitWiseLE(POLY_C, (crcOut(7 downto 0) xor datOut ));
           end if;
            if ( datOut = x"00" ) then
               if ( phase = 1 ) then
                  assert len    = 4 report "unexpected output length" severity failure;
                  assert (crcOut = (POLY_C xor POLY_C)) or ((guard(0) = '1') and (crcOut = MAGIC_C)) report "unexpected CRC" severity failure;
               end if;
               len    <= 0;
               seen   <= seen + 1;
               crcOut <= CRC_INIT_C;
            end if;
         end if;
         if ( phase = 0 and vldInp = '0' and idx = 0 ) then
            vldInp <= '1';
         end if;
         if ( (rdyInp and vldInp) = '1' ) then
            if ( phase = 0 ) then
               if (idx = FEED_C'high) then
                  vldInp <= '0';
               else
                  idx    <= idx + 1;
               end if;
            elsif ( phase = 1 ) then
               if ( idx = feed'high ) then
                  if ( i = 255 ) then
                     i <= 1;
                     if ( j = 255 ) then
                        vldInp <= '0';
                     else
                        j <= j + 1;
                     end if;
                  else
                     i <= i + 1;
                  end if;
                  idx <= 0;
               else
                  idx <= idx + 1;
               end if;
            end if;
         end if;
         if ( phase = 0 and seen = NEOFS ) then
           phase  <= phase + 1;
           idx    <= 0;
           vldInp <= '1';
         end if;
         if ( seen = NEOFS + 255*255 ) then
            don <= true;
         end if;
      end if;
   end process P_FEED;

   feed(0) <= std_logic_vector(to_unsigned(i, 8));
   feed(1) <= std_logic_vector(to_unsigned(j, 8));
   feed(2) <= x"00";

   datInp <= FEED_C(idx) when phase = 0 else feed(idx);

   U_DUT : entity work.RelLnkCrcGen
      generic map (
         POLY_G => POLY_C
      )
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

end architecture rtl;


