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

use     work.CrcPkg.all;
use     work.RelLnkPkg.all;

entity RelLnkCrcCheck is
   generic (
      LD_FIFO_DEPTH_G : natural;
      COBS_EOF_G      : std_logic_vector( 7 downto 0) := x"00";
      COBS_CHECK_EN_G : boolean := true;
      HAVE_RDY_INP_G  : boolean := false
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      datInp          : in  std_logic_vector(7 downto 0);
      vldInp          : in  std_logic;
      rdyInp          : out std_logic;

      datOut          : out std_logic_vector(7 downto 0);
      vldOut          : out std_logic;
      rdyOut          : in  std_logic;

      -- disgnostics
      dropping        : out std_logic
   );
end entity RelLnkCrcCheck;

architecture rtl of RelLnkCrcCheck is

   constant CRC_N_BYTES_C : natural := 2;

   signal   fifoFull    : std_logic;
   signal   fifoEmpty   : std_logic;
   signal   fifoWrEna   : std_logic;
   signal   fifoWrDat   : std_logic_vector(7 downto 0);
   signal   fifoRdEna   : std_logic;
   signal   fifoWrUndo  : std_logic;
   signal   fifoWrPtr   : signed(LD_FIFO_DEPTH_G downto 0);
   signal   fifoRdPtr   : signed(LD_FIFO_DEPTH_G downto 0);

   type     StateType   is (RUN, DROP);
   type     Slv9Array   is array (natural range <>) of std_logic_vector(8 downto 0);
   type     Uns8Array   is array (natural range <>) of unsigned(7 downto 0);

   function getValid(constant x : std_logic_vector(8 downto 0)) return std_logic is
   begin
      return x(8);
   end function getValid;

   procedure setValid(variable x : inout std_logic_vector(8 downto 0); constant v : std_logic) is
   begin
      x    := x;
      x(8) := v;
   end procedure setValid;

   function getData(constant x : std_logic_vector(8 downto 0)) return std_logic_vector is
   begin
      return x(7 downto 0);
   end function getData;

   procedure setData(variable x : inout std_logic_vector(8 downto 0); constant v : std_logic_vector(7 downto 0)) is
   begin
      x          := x;
      x(v'range) := v;
   end procedure setData;

   function isGuardValid(constant x : Slv9Array) return boolean is
   begin
      return getValid(x(0)) = '1';
   end function isGuardValid;

   function getGuardBit(constant x : Slv9Array) return std_logic is
   begin
      return getData(x(0))(0);
   end function getGuardBit;

   type     RegType     is record
      state             : StateType;
      cmPtr             : signed(LD_FIFO_DEPTH_G     downto 0);
      msgLength         : signed(LD_FIFO_DEPTH_G + 1 downto 0);
      cobsCnt           : Uns8Array(0 to CRC_N_BYTES_C);
      -- delay incoming data so that we can strip the CRC
      -- msbit serves as a 'valid' flag
      crc               : std_logic_vector(CRC_POLY_LE_C'range);
      crcDiscard        : Slv9Array(0 to CRC_N_BYTES_C - 1);
   end record RegType;

   constant REG_INIT_C  : RegType := (
      state             => RUN,
      cmPtr             => (others => '0'),
      msgLength         => to_signed((2**LD_FIFO_DEPTH_G) + CRC_N_BYTES_C - 1, LD_FIFO_DEPTH_G + 2),
      cobsCnt           => (others => (others => '0')),
      crc               => CRC_INIT_LE_C,
      crcDiscard        => (others => (others => '0'))
   );

   procedure restart(variable s : inout RegType) is
   begin
      s           := s;
      s.crc       := CRC_INIT_LE_C;
      s.msgLength := to_signed((2**LD_FIFO_DEPTH_G) + CRC_N_BYTES_C - 1, LD_FIFO_DEPTH_G + 2);
      if ( COBS_CHECK_EN_G ) then
         s.cobsCnt(s.cobsCnt'high) := (others => '0');
         -- oldest count must be valid (=0); back-to-back 0x00
         -- is valid!
         s.cobsCnt(s.cobsCnt'low)  := (others => '0');
         for i in s.cobsCnt'low + 1 to s.cobsCnt'high - 1 loop
            -- just ensure the other delayed counts are non-zero (invalid)
            s.cobsCnt(i)(0) := '1';
         end loop;
      end if;
      for i in s.crcDiscard'range loop
         setValid(s.crcDiscard(i), '0');
      end loop;
   end procedure restart;

   signal   r           : RegType := REG_INIT_C;
   signal   rin         : RegType;

begin

   P_COMB : process ( r, datInp, vldInp, fifoFull, fifoWrPtr ) is
      variable v         : RegType;
      variable rdyInpLoc : std_logic;
   begin
      v          :=  r;
      fifoWrUndo <= '0';
      rdyInpLoc  := '0';
      fifoWrEna  <= getValid(r.crcDiscard(0)) and not fifoFull;
      fifoWrDat  <= getData (r.crcDiscard(0));

      case ( r.state ) is
         when RUN   =>
            if ( fifoFull = '0' ) then
               setValid(v.crcDiscard(0), '0');
               -- remove head
            end if;

            -- propagate input data through the 'crcDiscard' pipeline
            for i in v.crcDiscard'low to v.crcDiscard'high - 1 loop
               if ( getValid(v.crcDiscard(i)) = '0' ) then
                  v.crcDiscard(i)      := r.crcDiscard(i+1);
                  setValid(v.crcDiscard(i+1), '0');
               end if;
            end loop;
            rdyInpLoc := not getValid(v.crcDiscard(v.crcDiscard'high));
            if ( vldInp = '1' ) then
               if ( r.msgLength < 0 ) then
                  -- message too long;
                  v.state := DROP;
                  restart(v);
               elsif ( rdyInpLoc = '1' ) then
                  setValid(v.crcDiscard(v.crcDiscard'high), '1');
                  setData (v.crcDiscard(v.crcDiscard'high), datInp);
                  v.crc                           := CrcWrdWiseLE(CRC_POLY_LE_C, r.crc, datInp);
                  v.msgLength                     := r.msgLength - 1;
                  if ( COBS_CHECK_EN_G ) then
                     for i in r.cobsCnt'low to r.cobsCnt'high - 1 loop
                        v.cobsCnt(i) := r.cobsCnt(i + 1);
                     end loop;
                     if ( r.cobsCnt(r.cobsCnt'high) = 0 ) then
                        v.cobsCnt(v.cobsCnt'high)    := unsigned(datInp) - 1;
                     else
                        v.cobsCnt(v.cobsCnt'high)    := r.cobsCnt(r.cobsCnt'high) - 1;
                     end if;
                  end if;
                  if ( COBS_EOF_G = datInp ) then
                     if (     isGuardValid(r.crcDiscard)
                          and CRC_OK_LE_F(getGuardBit(r.crcDiscard), r.crc)
                          and (not COBS_CHECK_EN_G or r.cobsCnt(0) = 0)
                        ) then
                        fifoWrEna  <= '1';
                        fifoWrDat  <= COBS_EOF_G;
                        -- commit packet in fifo including the EOF we are just writing
                        v.cmPtr    := fifoWrPtr + 1;
                     else
                        -- drop data in fifo
                        fifoWrUndo <= '1';
                     end if;
                     restart(v);
                  end if;
               elsif ( not HAVE_RDY_INP_G ) then
                  -- cannot accept; must drop
                  v.state := DROP;
                  restart(v);
               end if;
            end if;

          when DROP  =>
             fifoWrUndo <= '1';
             rdyInpLoc  := '1';
             if ( (vldInp = '1') and (COBS_EOF_G = datInp) ) then
                v.state := RUN;
             end if;
      end case;

      rdyInp     <= rdyInpLoc;
      rin        <=  v;
   end process P_COMB;


   P_SEQ  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   U_FIFO : entity work.RelLnkFifo
      generic map (
         LD_FIFO_DEPTH_G => LD_FIFO_DEPTH_G,
         DATA_WIDTH_G    => 8
      )
      port map (
         clk             => clk,
         rst             => rst,

         datInp          => fifoWrDat,
         wrEna           => fifoWrEna,
         -- reset write pointer to commit; if wrUndo is asserted concurrently
         -- with 'wrEna' then the written item is discarded.
         wrUndo          => fifoWrUndo,
         full            => fifoFull,
         wrPtr           => fifoWrPtr,
         -- 'commit' pointer read possible up to here
         cmPtr           => r.cmPtr,
         
         datOut          => datOut,
         rdEna           => fifoRdEna,
         rdPtr           => fifoRdPtr,
	 hlPtr           => fifoRdPtr,
         empty           => fifoEmpty
      );

   vldOut    <= not fifoEmpty;
   fifoRdEna <= rdyOut and not fifoEmpty;
   dropping  <= fifoWrUndo;


end architecture rtl;

