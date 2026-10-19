GHDL=ghdl
GHDLFLAGS=-fsynopsys

VPATH=../

PROGS=CobsCrc15GenTb CobsCrc15CheckTb RelLnkTb RelLnkRndTb

all: $(PROGS)

test: $(PROGS)
	true $(addprefix && ./,$^)

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

$(PROGS):%Tb: %Tb.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ $@

clean:
	$(RM) *.o work-*.cf $(PROGS) dump.ghw

CobsCrc15CheckTb.o: CrcPkg.o CobsCrcPkg.o CobsCrc15Check.o CobsCrc15Gen.o
CobsCrc15GenTb.o: CrcPkg.o CobsCrcPkg.o CobsCrc15Check.o CobsCrc15Gen.o

CobsCrc15Check.o: CobsCrcPkg.o CrcPkg.o PktUtilFifo.o

CobsCrc15Gen.o: CobsCrcPkg.o CrcPkg.o

CobsCrcPkg.o: CrcPkg.o

RelLnk.o: RelLnkPkg.o PktUtilFifo.o

PktDropRnd.o: PktDrop.o RndPkg.o
StrmPauseRnd.o: StrmPause.o RndPkg.o

RelLnkTb.o: RelLnkPkg.o RelLnk.o PktUtilFifo.o
RelLnkRndTb.o: RndPkg.o RelLnkPkg.o RelLnk.o StrmPauseRnd.o PktDropRnd.o

.PHONY: clean test all
