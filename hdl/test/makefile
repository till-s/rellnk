#LB-MIT
#
# MIT License
#
# Copyright (c) 2026 Till Straumann
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#LE-MIT

GHDL=ghdl
GHDLFLAGS=-fsynopsys

VPATH=../

PROGS+=EOFTagTb CobsDecoderTb CobsEncoderTb
PROGS+=CobsCrcLE15GenTb CobsCrcLE15CheckTb RelLnkTb RelLnkRndTb RelLnkSynTb

all: $(PROGS)

test: $(PROGS)
	@bash -e -c 'for prog in $(PROGS); do ./$$prog --ieee-asserts=disable-at-0; done'
	@echo "Testing with 16-bit polynomial"
	./CobsCrcLE15GenTb -gPOLY_G=49154 --ieee-asserts=disable-at-0

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

$(PROGS):%Tb: %Tb.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ $@

clean:
	$(RM) *.o work-*.cf $(PROGS) dump.ghw

EOFTagTb.o: EOFTag.o

CobsEncoderTb.o: CobsDecoder.o CobsEncoder.o PktUtilFifo.o
CobsDecoderTb.o: CobsDecoder.o
CobsDecoder.o: EOFTag.o
CobsEncoder.o: PktUtilFifo.o

CobsCrcLE15CheckTb.o: CrcPkg.o CobsCrcPkg.o CobsCrcLE15_22Check.o CobsCrcLE15_22Gen.o
CobsCrcLE15GenTb.o: CrcPkg.o CobsCrcPkg.o CobsCrcLE15_22Check.o CobsCrcLE15_22Gen.o

CobsCrcLE15_22Check.o: CobsCrcPkg.o CrcPkg.o PktUtilFifo.o

CobsCrcLE15_22Gen.o: CobsCrcPkg.o CrcPkg.o

CobsCrcPkg.o: CrcPkg.o

RelLnk.o: RelLnkPkg.o PktUtilFifo.o

PktDropRnd.o: PktDrop.o RndPkg.o
StrmPauseRnd.o: StrmPause.o RndPkg.o

RelLnkTb.o: RelLnkPkg.o RelLnk.o PktUtilFifo.o
RelLnkRndTb.o: RndPkg.o RelLnkPkg.o RelLnk.o StrmPauseRnd.o PktDropRnd.o
RelLnkSynTb.o: RndPkg.o RelLnkPkg.o RelLnk.o StrmPauseRnd.o PktDropRnd.o

.PHONY: clean test all
