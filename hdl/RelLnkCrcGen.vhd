library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.CrcPkg.all;
use     work.RelLnkPkg.all;

-- Append little-endian CRC to a COBS-encoded stream.
-- (CRC is computed over the encoded stream in order
-- to maintain the burst-detecting properties of the CRC).
-- A guard bit is used to ensure the CRC does not have
-- null/EOF bytes.

entity RelLnkCrcGen is
   generic (
      POLY_G         : std_logic_vector(14 downto 0)
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic;
      datInp         : in  std_logic_vector(7 downto 0);
      vldInp         : in  std_logic;
      rdyInp         : out std_logic;

      datOut         : out std_logic_vector(7 downto 0);
      vldOut         : out std_logic;
      rdyOut         : in  std_logic
   );
end entity RelLnkCrcGen;

architecture rtl of RelLnkCrcGen is

   constant EOF_C      : std_logic_vector(7 downto 0)   := x"00"; 
   constant CRC_INIT_C : std_logic_vector(POLY_G'range) := (others => '1');

   -- 'left' part of the polynomial; since this is little-endian these
   -- bits correspond to the 'lower' order terms
   constant P_L_C      : std_logic_vector(14 downto 7) := POLY_G(14 downto 7);
   -- 'right' part of the polynomial; since this is little-endian these
   -- bits correspond to the 'higher' order terms
   constant P_R_C      : std_logic_vector( 6 downto 0) := POLY_G( 6 downto 0 );

   type StateType is (RUN, FIX_CRC, APPEND_CRC_1, APPEND_CRC_2, APPEND_EOF);

   function shift_right(constant x : std_logic_vector; constant s : natural)
   return std_logic_vector is
   begin
      return std_logic_vector(shift_right(unsigned(x),s));
   end function shift_right;

   type RegType   is record
      state       : StateType;
      crc         : std_logic_vector(POLY_G'range);
      guard       : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => RUN,
      crc         => CRC_INIT_C,
      guard       => '0'
   );

   signal r       : RegType := REG_INIT_C;
   signal rin     : RegType;

begin

   P_COMB : process (r, datInp, vldInp, rdyOut) is
      variable v : RegType;
   begin
      v          := r;
      datOut     <= datInp;
      vldOut     <= vldInp;
      rdyInp     <= rdyOut;
      case ( r.state ) is
         when RUN        =>
            if ( ( vldInp and rdyOut ) = '1' ) then
               v.crc := shift_right(r.crc, 8) xor CrcBitWiseLE(POLY_G, r.crc(7 downto 0) xor datInp);
               if ( EOF_C = datInp ) then
                  -- stop output (but consume input)
                  vldOut  <= '0';
                  v.state := FIX_CRC;
                  -- EOF does not go into CRC but add the guard bit ('0' for now)
                  v.crc   := shift_right(r.crc, 1) xor CrcBitWiseLE(POLY_G, r.crc(0 downto 0) xor "0");
               end if;
            end if;

         when FIX_CRC    =>
            rdyInp <= '0'; -- stop input
            vldOut <= '0'; -- stop output
            -- massage the guard bit
            if    ( r.crc(P_L_C'range) = EOF_C ) then
               v.guard := '1';
               v.crc   := r.crc xor POLY_G;
            elsif ( r.crc(P_R_C'range) = (P_R_C xor P_R_C) ) then -- (X xor X) for zero
               v.guard := '1';
               v.crc   := r.crc xor POLY_G;
               -- corner case where XORing the guard bit and its crc would
               -- zero out the leftmost 8 bits. Mark this by using a magic
               -- value with bits in both halves set.
               -- (both halves of the CRC AND the guard bits being
               -- nonzero cannot happen otherwise).
               if ( r.crc(P_L_C'range) = P_L_C ) then
                  v.crc := r.crc xor POLY_G xor MAGIC_LE_C;
               end if;
            end if;
            v.state := APPEND_CRC_1;

         when APPEND_CRC_1 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '1';
            datOut <= r.crc(P_R_C'range) & r.guard;
            if ( rdyOut = '1' ) then
               v.state := APPEND_CRC_2;
            end if;

         when APPEND_CRC_2 =>
            rdyInp <= '0'; -- stop input
            vldOut <= '1';
            datOut <= r.crc(P_L_C'range);
            if ( rdyOut = '1' ) then
               v.state := APPEND_EOF;
            end if;

         when APPEND_EOF   =>
            rdyInp  <= '0'; -- stop input
            vldOut  <= '1';
            datOut  <= EOF_C;
            v.crc   := CRC_INIT_C;
            v.guard := '0';
            if ( rdyOut = '1' ) then
               v.state := RUN;
            end if;
      end case;
      rin        <= v;
   end process;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

end architecture rtl;
