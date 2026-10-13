
GHDL=ghdl

PROGS=RelLnkCrcGenTb RelLnkCrcCheckTb

all: $(PROGS)

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

$(PROGS):%Tb: %Tb.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ $@

clean:
	$(RM) *.o work-*.cf $(PROGS) dump.ghw

RelLnkCrcCheckTb.o: RelLnkPkg.o RelLnkCrcCheck.o RelLnkCrcGen.o
RelLnkCrcGenTb.o: RelLnkPkg.o RelLnkCrcCheck.o RelLnkCrcGen.o

RelLnkCrcCheck.o: RelLnkPkg.o CrcPkg.o RelLnkFifo.o

RelLnkCrcGen.o: RelLnkPkg.o CrcPkg.o
