GHDL=ghdl
GHDLFLAGS=-fsynopsys

VPATH=../

PROGS=CobsCrcLE15GenTb CobsCrcLE15CheckTb RelLnkTb RelLnkRndTb

all: $(PROGS)

test: $(PROGS)
	true $(addprefix && ./,$^)

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

$(PROGS):%Tb: %Tb.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ $@

clean:
	$(RM) *.o work-*.cf $(PROGS) dump.ghw

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

.PHONY: clean test all
