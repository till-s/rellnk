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
   --  3.  CRC

   constant CRC_POLY_LE_C : std_logic_vector(14 downto 0) := "101100000110000";
   constant CRC_POLY_BE_C : std_logic_vector(14 downto 0) := "000011000001101";

   -- CRC should be taken *over* the COBS encoded packet (to properly detect
   -- bit-error bursts). Adding one additional bit to avoid EOF markers in
   -- the CRC:
   -- ** All the following analysis is done in a little-endian world **
   -- ** and assumes the CRC and extra bit fit in two bytes          **
   -- 
   -- Appending one zero-bit to the data yields some CRC (including the
   -- zero-bit) the can be split into two bytes. The first byte contains
   -- any trailing data bits, the extra bit and the high-order bits (in polynomial-view)
   -- of the CRC; the second byte contains the low-order 8 bits of the
   -- CRC:
   --    [data_byte],
   --    ...
   --    [data_byte],
   --    [crc-high-order:extra_bit(:optional_last_data_bits)]
   --    [crc-low-order-byte]
   --
   -- 'optional_data-bits' are only present if the CRC is less than 15 bits
   -- long.
   -- The idea is that when the CRC high- or low-order parts are zero
   -- (which would collide with EOF) we can use the extra bit to mitigate
   -- the situation.
   -- Due to the affine property of the CRC : CRC(a^b) = CRC(a)^CRC(b)
   -- setting the extra bit and XORing the CRC with that bit's CRC
   -- yields a valid CRC again.
   -- The CRC of the trailing extra bit is simply the polynomial itself.
   -- Because the lowest order (x^0) of the polynomial is aligned with
   -- the leftmost bit in the 'crc-low-order-byte' it is immediately clear
   -- that when the crc-low-order-byte is initially 0x00 (EOF) then setting
   -- the extra bit and XORing the CRC with the polynomial results in
   -- a non-zero crc-low-order-byte AND a non-zero second-to-last byte
   -- as well (because the extra bit is set).
   --
   -- Thus, we only have to look more carefully at the case when the
   -- crc-high-order bits are are zero. If we flip the extra bit and
   -- XOR the CRC with the polynomial then the crc-low-order byte may
   -- become zero as a result of this XOR operation.
   -- However, there is only one single possibility when this can happen
   --  1. all crc-high-order bits are zero
   --  2. the crc-low-order-byte matches the low-order byte of the polynomial
   -- Because these two conditions cover all the bits of the CRC this
   -- means that only one well-defined value needs to be handled as
   -- a corner case.
   -- 
   -- After XORing the corner-case with the guard bit and the polynomial
   --  1. the crc-hight-order bits match the polynomial low order bits
   --  2. the crc-low-order-byte is zero.
   -- Because in all other cases extra == '1' implies that at least one of
   -- the CRC parts are zero (before XOR with the polynomial) the special
   -- value may encoded to anything matching
   --
   --    extra == '1' AND (CRC XOR POLY)_upper != 0 AND (CRC XOR POLY)_lower != 0
   --                 AND (CRC)_upper          != 0 AND (CRC)_lower          != 0
   --
   -- We can encode the special case so that the CRC has just one bit set; i.e.,
   -- we chose a MAGIC value so that, e.g., crc(MAGIC) = 0x4000 which simplifies
   -- the decoder.
   -- 
   -- For the polynomial 0x5830 the magic value 0xf4a produces a CRC of 0x4000.
   -- This needs to be XORed with the high-order bits of the polynomial.
   -- Since low-order byte of the magical value 
   -- half the final CRC does meet the condition for the magical value.
   constant CRC_INIT_LE_C : std_logic_vector(CRC_POLY_LE_C'range) := (others => '1');
   constant CRC_INIT_BE_C : std_logic_vector(CRC_POLY_BE_C'range) := (others => '1');
   -- magic value to be XORed into the corner-case crc
   constant MAGIC_LE_C    : std_logic_vector(CRC_POLY_LE_C'range) := ("000" & x"f4a");
   constant MAGIC_BE_C    : std_logic_vector(CRC_POLY_BE_C'range) := ("010100101111000");

   function CRC_OK_LE_F(constant g : std_logic; constant crc : std_logic_vector(CRC_POLY_LE_C'range))
   return boolean;

   function CRC_OK_BE_F(constant g : std_logic; constant crc : std_logic_vector(CRC_POLY_BE_C'range))
   return boolean;

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

   function CRC_OK_LE_F(constant g : std_logic; constant crc : std_logic_vector(CRC_POLY_LE_C'range))
   return boolean is
   begin
      return ((not crc(crc'left) or g) = '1') and (unsigned(crc(crc'left - 1 downto 0)) = 0);
   end function CRC_OK_LE_F;

   function CRC_OK_BE_F(constant g : std_logic; constant crc : std_logic_vector(CRC_POLY_BE_C'range))
   return boolean is
   begin
      return ((not crc(0) or g) = '1') and (unsigned(crc(crc'left downto 1)) = 0);
   end function CRC_OK_BE_F;

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

