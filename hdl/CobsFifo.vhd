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

entity CobsFifo is
   generic (
      LD_FIFO_DEPTH_G : natural;
      DATA_WIDTH_G    : natural := 8
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      datInp          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      wrEna           : in  std_logic;
      full            : out std_logic;
      
      datOut          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      rdEna           : in  std_logic;
      empty           : out std_logic
   );
end entity CobsFifo;

architecture rtl of CobsFifo is

   subtype SlvType  is std_logic_vector(DATA_WIDTH_G - 1 downto 0);
   type    SlvArray is array (natural range <>) of SlvType;

   signal wptr              : signed(LD_FIFO_DEPTH_G downto 0) := (others => '0');
   signal rptr              : signed(LD_FIFO_DEPTH_G downto 0) := (others => '0');

   shared variable memory   : SlvArray(0 to 2**LD_FIFO_DEPTH_G - 1);

   signal memoryRen         : std_logic;
   signal memoryWen         : std_logic;

   signal readDataVld       : std_logic := '0';
   signal fullLoc           : std_logic := '0';

begin

   P_MEM_RD : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( memoryRen = '1' ) then
            datOut <= memory( to_integer(unsigned(rptr(LD_FIFO_DEPTH_G - 1 downto 0))) );
         end if;
      end if;
   end process P_MEM_RD;

   P_MEM_WR : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( memoryWen = '1' ) then
            memory( to_integer(unsigned(wptr(LD_FIFO_DEPTH_G - 1 downto 0))) ) := datInp;
         end if;
      end if;
   end process P_MEM_WR;

   empty     <= not readDataVld;
   full      <= fullLoc;

   memoryRen <= not readDataVld or rdEna;
   memoryWen <= wrEna and not fullLoc;

   -- since wptr and rptr are signed and 1-bit longer than LD_FIFO_DEPTH_G
   -- the wptr-rptr difference flips negative when the fifo is full
   fullLoc <= '1' when ( wptr - rptr < 0 ) else '0';

   P_FIFO_RD : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            rptr        <= (others => '0');
            wptr        <= (others => '0');
            readDataVld <= '0';
         else
            if ( memoryRen = '1' ) then
               if ( wptr /= rptr ) then
                  readDataVld  <= '1';
                  rptr         <= rptr + 1;
               else
                  readDataVld  <= '0';
               end if;
            end if;
            if ( memoryWen = '1' ) then
               wptr <= wptr + 1;
            end if;
         end if;
      end if;
   end process P_FIFO_RD;

end architecture rtl;


