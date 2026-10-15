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

entity RelLnk is
   generic (
      LD_FIFO_DEPTH_G : natural;
      REX_TIMEOUT_G   : RelLnkTimeoutType;
      -- enable sending ACK immediately after receiving the
      -- header; this may abort retransmissions (before the
      -- packet has been received!) but is more responsive
      -- if there are store-and forward elements downstream
      -- (e.g., CRC checking).
      FAST_ACK_G      : boolean;
      REL_LNK_WINSZ_G : positive range 1 to (2**RelLnkSeqNo'length - 1) := 3
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      datInpTx        : in  std_logic_vector(7 downto 0);
      vldInpTx        : in  std_logic;
      lstInpTx        : in  std_logic;
      rdyInpTx        : out std_logic;

      oobInpTx        : in  std_logic_vector(7 downto 0) := (others => '0');

      datOutRx        : out std_logic_vector(7 downto 0);
      vldOutRx        : out std_logic;
      lstOutRx        : out std_logic;
      rdyOutRx        : in  std_logic;

      oobOutRx        : out std_logic_vector(7 downto 0);

      datOutTx        : out std_logic_vector(7 downto 0);
      vldOutTx        : out std_logic;
      lstOutTx        : out std_logic;
      rdyOutTx        : in  std_logic;
      datInpRx        : in  std_logic_vector(7 downto 0);
      vldInpRx        : in  std_logic;
      lstInpRx        : in  std_logic;
      rdyInpRx        : out std_logic
   );
end entity RelLnk;

architecture rtl of RelLnk is

   constant LD_REX_FIFO_DEPTH_C : natural := RelLnkSeqNo'length;

   signal   fifoFull    : std_logic;
   signal   fifoEmpty   : std_logic;
   signal   fifoWrEna   : std_logic;
   signal   fifoWrDat   : std_logic_vector(7 downto 0);
   signal   fifoRdEna   : std_logic;
   signal   fifoRdDat   : std_logic_vector(7 downto 0);
   signal   fifoWrUndo  : std_logic;
   signal   fifoRdUndo  : std_logic;
   signal   fifoWrPtr   : signed(LD_FIFO_DEPTH_G downto 0);
   signal   fifoRdPtr   : signed(LD_FIFO_DEPTH_G downto 0);

   constant REX_FIFO_WIDTH_C : natural := fifoWrPtr'length + RelLnkTimeoutType'length;

   signal   rexFifoWrEna : std_logic;
   signal   rexFifoWrUndo: std_logic;
   signal   rexFifoWrDat : std_logic_vector(REX_FIFO_WIDTH_C - 1 downto 0);
   signal   rexFifoRdDat : std_logic_vector(REX_FIFO_WIDTH_C - 1 downto 0);
   signal   rexFifoRdEna : std_logic;
   signal   rexFifoEmpty : std_logic;
   signal   rexFifoWrPtr : signed(LD_REX_FIFO_DEPTH_C downto 0);
   signal   rexFifoRdPtr : signed(LD_REX_FIFO_DEPTH_C downto 0);
   signal   rexFifoCmPtr : signed(LD_REX_FIFO_DEPTH_C downto 0);


   type     TxStateType is (IDLE, TX_ACK, TX_HDR, TX_OOB, TX_PLD, REX_HDR, REX_PLD, REX_CLEAN, REX_RST_RPTR, REX_ABORT, COMMIT);
   type     RxStateType is (IDLE, DROP, STRIP_HDR, COPY_OOB, COPY_PLD);

   type     Slv9Array   is array (natural range <>) of std_logic_vector(8 downto 0);
   type     Uns8Array   is array (natural range <>) of unsigned(7 downto 0);

   type     RegType   is record
      txState           : TxStateType;
      rxState           : RxStateType;
      txReq             : RelLnkSeqNo;
      txAck             : RelLnkSeqNo;
      txAckDly          : RelLnkSeqNo;
      txOob             : std_logic_vector(7 downto 0);
      rxReq             : RelLnkSeqNo;
      rxAck             : RelLnkSeqNo;
      rxOob             : std_logic_vector(7 downto 0);
      rexReq            : RelLnkSeqNo;
      curTime           : RelLnkTimeoutType;
      rexCmPtr          : signed(LD_REX_FIFO_DEPTH_C downto 0);
      rexRdPtr          : signed(LD_FIFO_DEPTH_G downto 0);
      rexLstPtr         : signed(LD_FIFO_DEPTH_G downto 0);
      fifoHoldPtr       : signed(LD_FIFO_DEPTH_G downto 0);
   end record RegType;

   constant TX_REG_INIT_C : RegType := (
      txState           => IDLE,
      rxState           => IDLE,
      txReq             => to_unsigned(0, RelLnkSeqNo'length),
      txAck             => to_unsigned(0, RelLnkSeqNo'length),
      txAckDly          => to_unsigned(0, RelLnkSeqNo'length),
      txOob             => (others => '0'),
      rxReq             => to_unsigned(0, RelLnkSeqNo'length),
      rxAck             => to_unsigned(0, RelLnkSeqNo'length),
      rxOob             => (others => '0'),
      rexReq            => to_unsigned(0, RelLnkSeqNo'length),
      curTime           => (others => '0'),
      rexCmPtr          => (others => '0'),
      rexRdPtr          => (others => '0'),
      rexLstPtr         => (others => '0'),
      fifoHoldPtr       => (others => '0')
   );

   signal   r           : RegType := TX_REG_INIT_C;
   signal   rin         : RegType;

   function getTimeout(constant x : std_logic_vector) return RelLnkTimeoutType is
   begin
      return RelLnkTimeoutType(x(RelLnkTimeoutType'range));
   end function getTimeout;

   function getLstPtr(constant x : std_logic_vector) return signed is
   begin
      return resize(shift_right(signed(x), RelLnkTimeoutType'length), LD_FIFO_DEPTH_G + 1);
   end function getLstPtr;

begin


   P_COMB : process (
      r,
      datInpTx, vldInpTx, lstInpTx,
      rdyOutTx,
      oobInpTx,
      datInpRx, vldInpRx, lstInpRx,
      rdyOutRx,
      fifoFull, fifoWrPtr, fifoEmpty, fifoRdPtr, fifoRdDat,
      rexFifoEmpty, rexFifoRdDat, rexFifoWrPtr
   ) is
      variable v         : RegType;
      variable txDat     : std_logic_vector(7 downto 0);
   begin
      v            :=  r;
      fifoWrUndo   <= '0';
      fifoRdUndo   <= '0';
      fifoWrEna    <= '0';
      fifoRdEna    <= '0';
      rexFifoWrEna <= '0';
      rexFifoRdEna <= '0';
      rdyInpTx     <= '0';
      vldOutTx     <= '0';
      lstOutTx     <= '0';
      rdyInpRx     <= '0';
      vldOutRx     <= '0';
      lstOutRx     <= '0';
      txDat        := datInpTx;
      rexFifoWrDat <= std_logic_vector(fifoWrPtr) & std_logic_vector(r.curTime + REX_TIMEOUT_G);
      rexFifoWrUndo<= '0';
      datOutRx     <= datInpRx;
      lstOutRx     <= lstInpRx;

      v.curTime    := r.curTime + 1;

      case ( r.rxState ) is
         when IDLE      =>
            if ( vldInpRx = '1' ) then
               -- ACK processing
               if ( hdrGetAck(datInpRx) - r.txAck <= r.txReq - r.txAck ) then
                  -- normal case; ack is in the retransmission queue
                  v.txAckDly := hdrGetAck(datInpRx);
                  v.txAck    := hdrGetAck(datInpRx);
               else
                  -- a redundant ack; ignore
               end if;

               v.rxState := DROP;

               -- REQ processing
               if ( hdrGetMsgTyp(datInpRx) = REL_LNK_MSG_ACK_C ) then
                  -- ignore req number of ACKONLY message
               else
                  if ( hdrGetReq(datInpRx) = r.rxReq + 1 ) then
                     -- new in-order request; 
                     if ( FAST_ACK_G ) then
                        v.rxReq   := r.rxReq + 1;
                     else
                        -- reset and use delayed version
                        v.txAck   := r.txAck;
                     end if;
                     v.rxState := STRIP_HDR;
                  else
                     -- they might not have not seen rxReq; ensure we send an ACK
                     v.rxAck := r.rxReq - 1;
                  end if;
               end if;
            end if;

         when DROP      =>
            rdyInpRx <= '1';
            if ( (vldInpRx and lstInpRx) = '1' ) then
               v.rxState := IDLE;
            end if;

         when STRIP_HDR =>
            rdyInpRx <= '1';
            if ( vldInpRx = '1' ) then
               if ( lstInpRx = '1' ) then
                  if ( FAST_ACK_G ) then
                     v.txAck    := r.txAckDly;
                  end if;
                  v.rxState := IDLE;
               else
                  v.rxState := COPY_OOB;
               end if;
            end if;

         when COPY_OOB  =>
            rdyInpRx <= '1';
            if ( vldInpRx = '1' ) then
               v.rxOob := datInpRx;
               if ( lstInpRx = '1' ) then
                  v.rxState := IDLE;
               else
                  v.rxState := COPY_PLD;
               end if;
            end if;

         when COPY_PLD  =>
            rdyInpRx <= rdyOutRx;
            vldOutRx <= vldInpRx;
            if ( (vldInpRx and lstInpRx and rdyOutRx) = '1' ) then
               if ( not FAST_ACK_G ) then
                  v.txAck    := r.txAckDly;
                  v.rxReq    := r.rxReq + 1;
               end if;
               v.rxState := IDLE;
            end if;
      end case;

      case ( r.txState ) is
         when IDLE     =>
            if ( (not rexFifoEmpty and fifoEmpty) = '1' ) then
               -- fifoEmpty may temporarily assert if
               -- the read pipeline must be refilled.
               -- wait
            elsif ( (fifoEmpty = '0') and ( (r.txAck - hdrGetReq(fifoRdDat)) < REL_LNK_WINSZ_G ) ) then
               -- cleanup the retransmission queue
                  v.txState  := REX_CLEAN;
            elsif ( ((r.txReq - r.txAck) < REL_LNK_WINSZ_G) and ( (vldInpTx = '1') or (oobInpTx /= r.txOob) ) ) then
               -- step sequence number
               v.txReq   := r.txReq + 1;
               v.rxAck   := r.rxReq;
               v.txState := TX_HDR;
            elsif ( r.rxReq /= r.rxAck ) then
               v.rxAck   := r.rxReq;
               v.txState := TX_ACK;
            elsif ( (rexFifoEmpty = '0' ) and (signed(r.curTime - getTimeout(rexFifoRdDat)) >= 0) ) then
               v.txState    := REX_HDR;
               v.rexRdPtr   := r.fifoHoldPtr;
               v.rexLstPtr  := getLstPtr(rexFifoRdDat);
               rexFifoRdEna <= '1';
            end if;

         when REX_CLEAN =>
            if ( rexFifoEmpty = '0' ) then
               -- fifoEmpty may temporarily assert if
               -- the read pipeline must be refilled.
               -- wait
               if ( fifoEmpty  = '0' ) then
                  if ( (r.txAck - hdrGetReq(fifoRdDat)) < REL_LNK_WINSZ_G ) then
                     v.fifoHoldPtr := getLstPtr(rexFifoRdDat) + 1;
                     rexFifoRdEna  <= '1';
                     v.txState     := REX_RST_RPTR;
                  else
                     v.txState     := IDLE;
                  end if;
               end if;
            else
               v.txState     := IDLE;
            end if;

         when REX_RST_RPTR =>
            -- restore read pointer to hold pointer
            fifoRdUndo <= '1';
            v.txState  := REX_CLEAN;
            -- next cycle will have spurious fifoEmpty because
            -- the fifo's read pipeline must be reloaded;
            -- no problem in REX_CLEAN state

	 when TX_ACK =>
            -- pure ACK messages are not retransmitted
            txDat     := mkHdr1(r.txReq, r.rxAck, REL_LNK_MSG_ACK_C);
            vldOutTx  <= '1';
            lstOutTx  <= '1';
            if ( rdyOutTx = '1' ) then
               v.txState := IDLE;
            end if;

	 when TX_HDR =>
            txDat     := mkHdr1(r.txReq, r.rxAck, REL_LNK_MSG_DAT_C);
            vldOutTx  <= '1';
            if ( rdyOutTx = '1' ) then
               fifoWrEna    <= '1';
               v.txState    := TX_OOB;
            end if;

	 when TX_OOB =>
            txDat     := oobInpTx;
            v.txOob   := oobInpTx;
            vldOutTx  <= '1';
            if ( rdyOutTx = '1' ) then
               fifoWrEna    <= '1';
               if ( vldInpTx = '1' ) then
                  v.txState    := TX_PLD;
               else
                  lstOutTx <= '1';
                  v.txState    := COMMIT;
                  -- record write pointer of last byte
                  rexFifoWrEna <= '1';
                  v.rexCmPtr   := rexFifoWrPtr + 1;
               end if;
            end if;

	 when TX_PLD =>
            -- copy payload
            vldOutTx  <= vldInpTx;
            lstOutTx  <= lstInpTx;
            rdyInpTx  <= rdyOutTx;
            if ( (vldInpTx and rdyOutTx) = '1' ) then
               fifoWrEna <= '1';
               if ( lstInpTx = '1' ) then
                  v.txState    := COMMIT;
                  -- record write pointer of last byte
                  rexFifoWrEna <= '1';
                  v.rexCmPtr   := rexFifoWrPtr + 1;
               end if;
            end if;

      when REX_HDR =>
            v.rexReq  := hdrGetReq(fifoRdDat);
            if ( r.txAck - v.rexReq < REL_LNK_WINSZ_G ) then
               -- already ACKED; 
               v.txState     := REX_ABORT;
            else
               -- update ACK field; may have changed since
               -- we sent the original
               v.rxAck   := r.rxReq;
               txDat     := mkHdr1(v.rexReq, v.rxAck, hdrGetMsgTyp(fifoRdDat));
               vldOutTx  <= '1';
               if ( rdyOutTx = '1' ) then
                  fifoRdEna  <= '1';
                  v.rexRdPtr := r.rexRdPtr + 1;
                  v.txState  := REX_PLD;
               end if;
            end if;

         when REX_PLD =>
            txDat     := fifoRdDat;
            vldOutTx  <= not fifoEmpty; -- empty may temporarily assert
            if ( (not fifoEmpty and rdyOutTx) = '1' ) then
               fifoRdEna  <= '1';
               v.rexRdPtr := r.rexRdPtr + 1;
               if ( (r.rexLstPtr = r.rexRdPtr) or ((r.txAck - r.rexReq) < REL_LNK_WINSZ_G) ) then
                  lstOutTx     <= '1';

                  -- successfully transmitted; store new timeout in REX fifo but don't commit in case
                  -- the retransmisions are aborted
                  rexFifoWrDat <= std_logic_vector(r.rexLstPtr) & std_logic_vector(r.curTime + REX_TIMEOUT_G);
                  rexFifoWrEna <= '1';
                  if ( r.txAck - r.rexReq < REL_LNK_WINSZ_G ) then
                     -- abort
                     report "REX ABORT";
                     v.txState     := REX_ABORT;
                  elsif ( rexFifoEmpty = '0' ) then
                     -- no point in checking the timeout; we have to retransmit everything anyways
                     -- and since we leave the retransmission data FIFO unchanged we must recreate the
                     -- pointer FIFO to mirror the former's ordering.
                     -- next packet
                     rexFifoRdEna <= '1';
                     v.txState    := REX_HDR;
                     v.rexLstPtr  := getLstPtr(rexFifoRdDat);
                  else
                     -- nothing else to retransmit; commit
                     v.rexCmPtr   := rexFifoWrPtr + 1;
                     v.txState    := COMMIT;
                     -- reset read pointer
                     fifoRdUndo   <= '1';
                  end if;
               end if;
            end if;

         when REX_ABORT =>
            -- reset the read pointer
            fifoRdUndo <= '1';
            -- must restore the original order of the REX fifo so that it matches
            -- what's in the data fifo. Since retransmission was aborted record
            -- new timeouts
            if ( rexFifoEmpty = '0' ) then
               -- copy read data to the back
               rexFifoWrDat <= std_logic_vector(getLstPtr(rexFifoRdDat)) & std_logic_vector(r.curTime + REX_TIMEOUT_G);
               rexFifoWrEna <= '1';
               rexFifoRdEna <= '1';
            else
               -- commit the written data
               v.rexCmPtr   := rexFifoWrPtr;
               -- proceed to REX_CLEAN via COMMIT -> IDLE
               -- this ensures the fifo empty markers are updated
               v.txState    := COMMIT;
            end if;

         when COMMIT  =>
            -- one cycle for the new rexCmPtr to propagate to the rexFifoEmpty
            v.txState := IDLE;

      end case;

      fifoWrDat    <= txDat;
      datOutTx     <= txDat;
      rexFifoCmPtr <= r.rexCmPtr;
      oobOutRx     <= r.rxOob;

      rin      <=  v;
   end process P_COMB;


   P_SEQ  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= TX_REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   U_REX_FIFO : entity work.RelLnkFifo
      generic map (
         LD_FIFO_DEPTH_G => LD_REX_FIFO_DEPTH_C,
         DATA_WIDTH_G    => rexFifoWrDat'length
      )
      port map (
         clk             => clk,
         rst             => rst,

         datInp          => rexFifoWrDat,
         wrEna           => rexFifoWrEna,
         -- reset write pointer to commit; if wrUndo is asserted concurrently
         -- with 'wrEna' then the written item is discarded.
         wrUndo          => rexFifoWrUndo,
         full            => open,
         wrPtr           => rexFifoWrPtr,
         -- 'commit' pointer read possible up to here
         cmPtr           => rexFifoCmPtr,
         
         datOut          => rexFifoRdDat,
         rdEna           => rexFifoRdEna,
         rdPtr           => rexFifoRdPtr,
         hlPtr           => rexFifoRdPtr,
         empty           => rexFifoEmpty
      );

   U_DAT_FIFO : entity work.RelLnkFifo
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
         cmPtr           => fifoWrPtr,
         
         datOut          => fifoRdDat,
         rdEna           => fifoRdEna,
         rdPtr           => fifoRdPtr,
         hlPtr           => r.fifoHoldPtr,
         rdUndo          => fifoRdUndo,
         empty           => fifoEmpty
      );

end architecture rtl;

