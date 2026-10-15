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

-- drop packets

entity PktDrop is
   generic (
      DATA_WIDTH_G    : natural := 8
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      -- drop next packet
      trg             : in  std_logic := '0';
      -- done (VLD and RDY and LST of dropped packet)
      ack             : out std_logic := '0';

      datInp          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldInp          : in  std_logic;
      lstInp          : in  std_logic;
      rdyInp          : out std_logic;

      datOut          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldOut          : out std_logic;
      lstOut          : out std_logic;
      rdyOut          : in  std_logic
   );
end entity PktDrop;

architecture rtl of PktDrop is

   type StateType is (IDLE, DUMP);

   type     RegType   is record
      state             : StateType;
      trg               : std_logic;
      sof               : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state             => IDLE,
      trg               => '0',
      sof               => '0'
   );

   signal   r           : RegType := REG_INIT_C;
   signal   rin         : RegType;

 
begin

   P_COMB : process (
      r,
      trg,
      datInp, vldInp, lstInp, rdyOut
   ) is
      variable v         : RegType;
   begin
      v            :=  r;
      datOut       <= datInp;
      lstOut       <= lstInp;
      vldOut       <= vldInp;
      rdyInp       <= rdyOut;
      ack          <= '0';
      if ( vldInp = '1' ) then
         v.sof     := (rdyOut and lstInp);
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( trg = '1' ) then
               v.trg   := '1';
            end if;
            -- wait for next SOF; use v.sof to avoid
            -- vld and not rdy in this cycle
            if ( (v.trg and v.sof) = '1' ) then
               v.state := DUMP;
            end if;

         when DUMP =>
            v.trg   := '0';
            vldOut  <= '0';
            rdyInp  <= '1';
            if ( (vldInp and lstInp) = '1' ) then
               ack  <= '1';
               v.state := IDLE;
            end if;
      end case;
      rin          <= v;
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

end architecture rtl;
