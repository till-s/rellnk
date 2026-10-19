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

package RelLnkPkg is
   -- packet structure: 
   --  1.  header  (1 byte); contains SEQ and ACK numbers, 1 bit flag
   --      and user bits. Seq/Ack may be 2 or 3 bits; leaving 3 or
   --      on user bit, respectively.
   --      The flag bit indicates whether the packet carries payload
   --      or protocol data,
   --  2.  payload (or protocol data) bytes

   subtype RelLnkSeqNo     is unsigned(1 downto 0);
   -- extended sequence number
   subtype RelLnkSeqNoExt  is unsigned(RelLnkSeqNo'high + 1 downto 0);
   subtype RelLnkMsgTyp    is unsigned(1 downto 0);

   subtype RelLnkTimeoutType is unsigned(15 downto 0);

   constant REL_LNK_MSG_DAT_C : RelLnkMsgTyp := to_unsigned(0, RelLnkMsgTyp'length);
   constant REL_LNK_MSG_ACK_C : RelLnkMsgTyp := to_unsigned(1, RelLnkMsgTyp'length);

   function mkHdr1(constant req : RelLnkSeqNoExt; constant ack : RelLnkSeqNoExt; constant typ : RelLnkMsgTyp)
   return std_logic_vector;

   subtype AckType is RelLnkSeqNo;
   subtype ReqType is RelLnkSeqNo;

   function hdrGetReq(constant x : std_logic_vector(7 downto 0))
   return ReqType;

   function hdrGetAck(constant x : std_logic_vector(7 downto 0))
   return AckType;

   function hdrGetAckExtend(constant x : std_logic_vector(7 downto 0); constant ref : RelLnkSeqNoExt)
   return RelLnkSeqNoExt;

   function hdrGetReqExtend(constant x : std_logic_vector(7 downto 0); constant ref : RelLnkSeqNoExt)
   return RelLnkSeqNoExt;

   function hdrGetMsgTyp(constant x : std_logic_vector(7 downto 0))
   return RelLnkMsgTyp;

end package RelLnkPkg;

package body RelLnkPkg is

   function mkHdr1(constant req : RelLnkSeqNoExt; constant ack : RelLnkSeqNoExt; constant typ : RelLnkMsgTyp)
   return std_logic_vector is
   begin
      return std_logic_vector(resize(resize(req, ReqType'length) & resize(ack, AckType'length) & typ, 8));
   end function mkHdr1;

   function hdrGetReq(constant x : std_logic_vector(7 downto 0))
   return ReqType is
      variable v : unsigned(x'range);
   begin
      v := shift_right(unsigned(x),  AckType'length + RelLnkMsgTyp'length);
      return ReqType(resize(v, ReqType'length));
   end function hdrGetReq;

   function hdrGetAck(constant x : std_logic_vector(7 downto 0))
   return AckType is
      variable v : unsigned(x'range);
   begin
      v := shift_right(unsigned(x),  RelLnkMsgTyp'length);
      return AckType(resize(v, AckType'length));
   end function hdrGetAck;

   function extend(constant x : unsigned; constant ref : RelLnkSeqNoExt)
   return RelLnkSeqNoExt is
      variable v : RelLnkSeqNoExt;
      variable d : RelLnkSeqNoExt;
   begin
      if ( x'length = RelLnkSeqNoExt'length ) then
         return x;
      end if;
      v := resize(x, v'length);
      d := x - ref;
      v(v'left) := d(d'left);
      return v;
   end function extend;

   function hdrGetAckExtend(constant x : std_logic_vector(7 downto 0); constant ref : RelLnkSeqNoExt)
   return RelLnkSeqNoExt is
      variable v : RelLnkSeqNoExt;
   begin
      v := extend(hdrGetAck(x), ref);
      return v;
   end function hdrGetAckExtend;

   function hdrGetReqExtend(constant x : std_logic_vector(7 downto 0); constant ref : RelLnkSeqNoExt)
   return RelLnkSeqNoExt is
      variable v : RelLnkSeqNoExt;
   begin
      v := extend(hdrGetReq(x), ref);
      return v;
   end function hdrGetReqExtend;

   function hdrGetMsgTyp(constant x : std_logic_vector(7 downto 0))
   return RelLnkMsgTyp is
      variable v : unsigned(x'range);
   begin
      v := shift_right(unsigned(x),  0);
      return RelLnkMsgTyp(resize(v, RelLnkMsgTyp'length));
   end function hdrGetMsgTyp;

end package body RelLnkPkg;
