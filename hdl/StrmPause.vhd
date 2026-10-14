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

-- stop a stream of a number of clock cycles

entity StrmPause is
   generic (
      LD_PAUSE_G      : natural;
      DATA_WIDTH_G    : natural := 8
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      trg             : in  std_logic := '0';
      -- let 'pass' transactions go undesturbed before the pause is enforced
      pass            : in  unsigned(LD_PAUSE_G - 1 downto 0) := (others => '0');
      pause           : in  unsigned(LD_PAUSE_G - 1 downto 0) := (others => '0');
      -- asserted for the VLD/RDY cycle when the pause expired
      pauseAck        : out std_logic;

      datInp          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldInp          : in  std_logic;
      lstInp          : in  std_logic;
      rdyInp          : out std_logic;

      datOut          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldOut          : out std_logic;
      lstOut          : out std_logic;
      rdyOut          : in  std_logic
   );
end entity StrmPause;

architecture rtl of StrmPause is

   type StateType is (IDLE, PASSING, STALL);

   type     RegType   is record
      state             : StateType;
      trg               : std_logic;
      pass              : unsigned(pass'range);
      pause             : unsigned(pause'range);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state             => IDLE,
      trg               => '0',
      pass              => (others => '0'),
      pause             => (others => '0')
   );

   signal   r           : RegType := REG_INIT_C;
   signal   rin         : RegType;

 
begin

   P_COMB : process (
      r,
      trg, pass, pause,
      datInp, vldInp, lstInp, rdyOut
   ) is
      variable v         : RegType;
   begin
      v            :=  r;
      datOut       <= datInp;
      lstOut       <= lstInp;
      lstOut       <= lstInp;
      vldOut       <= '0';
      rdyInp       <= '0';
      pauseAck     <= '0';
      case ( r.state ) is
         when IDLE =>
            if ( trg = '1' ) then
               v.pass  := pass;
               v.pause := pause;
               v.trg   := '1';
            end if;
            if ( v.trg = '1' ) then
               if ( pass = 0 ) then
                  if ( vldInp = '1' ) then
                     v.state  := STALL;
                     if ( rdyOut = '1' ) then
                        if ( pause = 0 ) then
                           pauseAck <= '1';
                           vldOut   <= '1';
                           rdyInp   <= '1';
                           v.trg    := '0';
                           -- no change of state
                           v.state := r.state;
                        end if;
                     end if;
                  end if;
               else
                  vldOut  <= vldInp;
                  rdyInp  <= rdyOut;
                  v.state := PASSING;
                  if ( ( vldInp and rdyOut) = '1' ) then
                     v.pass := pass - 1;
                     if ( v.pass = 0 ) then
                        if ( pause = 0 ) then
                           pauseAck <= '1';
                           v.trg    := '0';
                           -- no change of state
                           v.state := r.state;
                        else
                           v.state := STALL;
                        end if;
                     end if;
                  end if;
               end if;
            end if;

         when PASSING =>
            vldOut  <= vldInp;
            rdyInp  <= rdyOut;
            if ( (vldInp and rdyOut) = '1' ) then
               if ( r.pass = 0 ) then
                  if ( r.pause = 0 ) then
                     v.trg    := '0';
                     v.state  := IDLE;
                     pauseAck <= '1';
                  else
                     v.state  := STALL;
                  end if;
               else
                  v.pass  := r.pass - 1; 
               end if;
            end if;

         -- enter this state only when vldInp can be deasserted,
         -- i.e., when previously either vldInp = 0 or vldInp and rdyInp = 1
         when STALL =>
            if ( r.pause = 0 ) then
               vldOut <= vldInp;
               rdyInp <= rdyOut;
               if ( (rdyOut and vldInp) = '1' ) then
                  pauseAck <= '1';
                  v.trg   := '0';
                  v.state := IDLE;
               end if;
            else
               v.pause := r.pause - 1;
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
