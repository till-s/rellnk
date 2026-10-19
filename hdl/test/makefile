
GHDL=ghdl
GHDLFLAGS=-fsynopsys

VPATH=../

PROGS=CobsCrcGenTb CobsCrcCheckTb RelLnkTb RelLnkRndTb

all: $(PROGS)

test: $(PROGS)
	for i in $^ ; do ./$$i; done

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

$(PROGS):%Tb: %Tb.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ $@

clean:
	$(RM) *.o work-*.cf $(PROGS) dump.ghw

CobsCrcCheckTb.o: RelLnkPkg.o CobsCrcCheck.o CobsCrcGen.o
CobsCrcGenTb.o: RelLnkPkg.o CobsCrcCheck.o CobsCrcGen.o

CobsCrcCheck.o: RelLnkPkg.o CrcPkg.o RelLnkFifo.o

CobsCrcGen.o: RelLnkPkg.o CrcPkg.o

RelLnk.o: RelLnkPkg.o RelLnkFifo.o

PktDropRnd.o: PktDrop.o RndPkg.o
StrmPauseRnd.o: StrmPause.o RndPkg.o

RelLnkTb.o: RelLnkPkg.o RelLnk.o RelLnkFifo.o
RelLnkRndTb.o: RndPkg.o RelLnkPkg.o RelLnk.o StrmPauseRnd.o PktDropRnd.o

.PHONY: clean test all
